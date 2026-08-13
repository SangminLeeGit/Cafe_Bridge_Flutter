#!/usr/bin/env bash
set -Eeuo pipefail

BASE_URL="${CAFE_BRIDGE_CI_BASE_URL:-}"
SECRET="${CAFE_BRIDGE_FLUTTER_CI_CALLBACK_SECRET:-}"
REPORT_COMMIT_SHA="${CI_COMMIT_SHA:-}"
EFFECTIVE_DRY_RUN="${DRY_RUN:-false}"
if [[ "${CI_PIPELINE_SOURCE:-}" == "push" ]]; then
  EFFECTIVE_DRY_RUN=true
fi
case "${EFFECTIVE_DRY_RUN}" in
  1|true|yes|y|on)
    REPORT_COMMIT_SHA="$(printf '%s' "${CI_COMMIT_SHA}:${CI_PIPELINE_ID}" | sha256sum | cut -c1-40)"
    ;;
esac
export REPORT_COMMIT_SHA
if [[ -z "$BASE_URL" || -z "$SECRET" ]]; then
  echo "CI failure callback cannot run: callback configuration is unavailable" >&2
  exit 1
fi

PAYLOAD="$(python3 - <<'PY'
import json
import os

print(json.dumps({
    "repo_full_name": os.environ.get("CI_PROJECT_PATH", ""),
    "branch": os.environ.get("CI_COMMIT_REF_NAME", ""),
    "commit_sha": os.environ.get("REPORT_COMMIT_SHA", ""),
    "status": "failed",
    "ref": (
        f"refs/tags/{os.environ['CI_COMMIT_TAG']}"
        if os.environ.get("CI_COMMIT_TAG")
        else f"refs/heads/{os.environ.get('CI_COMMIT_REF_NAME', '')}"
    ),
    "workflow_run_id": os.environ.get("CI_PIPELINE_ID", ""),
    "requested_by": os.environ.get("REQUESTED_BY", ""),
    "error_message": f"GitLab pipeline {os.environ.get('CI_PIPELINE_ID', '')} failed before release completion",
    "deploy_task_id": os.environ.get("DEPLOY_TASK_ID", ""),
}, ensure_ascii=False, separators=(",", ":")))
PY
)"
DELIVERY_ID="$(python3 -c 'import uuid; print(uuid.uuid4())')"
TIMESTAMP="$(date +%s)"
SIGNATURE="$(TIMESTAMP="$TIMESTAMP" DELIVERY_ID="$DELIVERY_ID" PAYLOAD="$PAYLOAD" SECRET="$SECRET" python3 - <<'PY'
import hashlib
import hmac
import os

message = f"{os.environ['TIMESTAMP']}\n{os.environ['DELIVERY_ID']}\n{os.environ['PAYLOAD']}".encode("utf-8")
print(hmac.new(os.environ["SECRET"].encode("utf-8"), message, hashlib.sha256).hexdigest())
PY
)"

curl -fsS --retry 3 --retry-delay 2 --retry-max-time 30 \
  -X POST \
  -H "Content-Type: application/json" \
  -H "X-Cafe-Bridge-CI-Timestamp: ${TIMESTAMP}" \
  -H "X-Cafe-Bridge-CI-Delivery: ${DELIVERY_ID}" \
  -H "X-Cafe-Bridge-CI-Signature: ${SIGNATURE}" \
  --data "$PAYLOAD" \
  "${BASE_URL%/}/api/ci/flutter-apk/report"

if [[ -n "${CAFE_BRIDGE_FLUTTER_CI_ALERT_WEBHOOK_URL:-}" ]]; then
  curl -fsS --retry 2 --retry-delay 2 --retry-max-time 15 \
    -X POST \
    -H "Content-Type: application/json" \
    --data "$PAYLOAD" \
    "$CAFE_BRIDGE_FLUTTER_CI_ALERT_WEBHOOK_URL" || \
    echo "CI failure alert webhook failed" >&2
fi
