#!/usr/bin/env bash
set -Eeuo pipefail

export GITHUB_RUN_ID="${CI_PIPELINE_ID}"
export GITHUB_RUN_NUMBER="${CI_PIPELINE_IID}"
export GITHUB_SHA="${CI_COMMIT_SHA}"
export GITHUB_REF_NAME="${CI_COMMIT_REF_NAME}"
export GITHUB_REPOSITORY="${CI_PROJECT_PATH}"
export GITHUB_ACTOR="${GITLAB_USER_LOGIN:-gitlab-ci}"
export GITHUB_WORKSPACE="${CI_PROJECT_DIR}"
if [[ -n "${CI_COMMIT_TAG:-}" ]]; then
  export GITHUB_REF="refs/tags/${CI_COMMIT_TAG}"
else
  export GITHUB_REF="refs/heads/${CI_COMMIT_BRANCH}"
fi
export GITEA_REF="${GITHUB_REF}"
export GITHUB_ENV="${CI_PROJECT_DIR}/.gitlab/github-env"
export RUNNER_TEMP="${CI_PROJECT_DIR}/.gitlab/tmp"
mkdir -p "${RUNNER_TEMP}"
: >"${GITHUB_ENV}"

load_github_env() {
  local line key value delimiter
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)\<\<(.+)$ ]]; then
      key="${BASH_REMATCH[1]}"
      delimiter="${BASH_REMATCH[2]}"
      value=""
      while IFS= read -r line; do
        [[ "${line}" == "${delimiter}" ]] && break
        if [[ -n "${value}" ]]; then value+=$'\n'; fi
        value+="${line}"
      done
      printf -v "${key}" '%s' "${value}"
      export "${key}"
    elif [[ "${line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      printf -v "${key}" '%s' "${BASH_REMATCH[2]}"
      export "${key}"
    fi
  done <"${GITHUB_ENV}"
}
finalize_job() {
  job_status=$?
  set +e
if (( job_status != 0 )); then
echo '[GitLab CI] Report build failure'
(
set -Eeuo pipefail
set -euo pipefail

PAYLOAD="$(python3 - <<'PY'
import json
import os

print(json.dumps({
    "repo_full_name": os.environ.get("REPO_FULL_NAME", ""),
    "branch": os.environ.get("BRANCH_NAME", ""),
    "commit_sha": os.environ.get("COMMIT_SHA", ""),
    "status": "failed",
    "ref": f"refs/heads/{os.environ.get('BRANCH_NAME', '')}",
    "workflow_run_id": os.environ.get("GITHUB_RUN_ID", ""),
    "requested_by": os.environ.get("REQUESTED_BY", ""),
    "error_message": "android release workflow failed",
    "deploy_task_id": os.environ.get("DEPLOY_TASK_ID", ""),
}, ensure_ascii=False, separators=(",", ":")))
PY
)"
TIMESTAMP="$(date +%s)"
SIGNATURE="$(TIMESTAMP="$TIMESTAMP" PAYLOAD="$PAYLOAD" SECRET="$EASYPOS_FLUTTER_CI_CALLBACK_SECRET" python3 - <<'PY'
import hashlib
import hmac
import os

message = f"{os.environ['TIMESTAMP']}\n{os.environ['PAYLOAD']}".encode("utf-8")
print(hmac.new(os.environ["SECRET"].encode("utf-8"), message, hashlib.sha256).hexdigest())
PY
)"
curl -fsS \
  -X POST \
  -H "Content-Type: application/json" \
  -H "X-EasyPOS-CI-Timestamp: ${TIMESTAMP}" \
  -H "X-EasyPOS-CI-Signature: ${SIGNATURE}" \
  --data "$PAYLOAD" \
  "$REPORT_URL"
)
load_github_env

fi
  exit "${job_status}"
}
trap finalize_job EXIT

echo '[GitLab CI] Prepare CI environment'
(
set -Eeuo pipefail
set -euo pipefail

EASYPOS_CI_BASE_URL="${EASYPOS_CI_BASE_URL:-${EASYPOS_CI_BASE_URL:-}}"
EASYPOS_FLUTTER_CI_CALLBACK_SECRET="${EASYPOS_FLUTTER_CI_CALLBACK_SECRET:-${EASYPOS_FLUTTER_CI_CALLBACK_SECRET:-}}"
EASYPOS_FLUTTER_BIN="${EASYPOS_FLUTTER_BIN:-${EASYPOS_FLUTTER_BIN:-}}"
EASYPOS_ANDROID_SDK_ROOT="${EASYPOS_ANDROID_SDK_ROOT:-${EASYPOS_ANDROID_SDK_ROOT:-}}"
export EASYPOS_CI_BASE_URL EASYPOS_FLUTTER_CI_CALLBACK_SECRET EASYPOS_FLUTTER_BIN EASYPOS_ANDROID_SDK_ROOT

if [[ -z "${EASYPOS_CI_BASE_URL:-}" ]]; then
  echo "EASYPOS_CI_BASE_URL secret is required" >&2
  exit 1
fi
if [[ -z "${EASYPOS_FLUTTER_CI_CALLBACK_SECRET:-}" ]]; then
  echo "EASYPOS_FLUTTER_CI_CALLBACK_SECRET secret is required" >&2
  exit 1
fi

REPO_URL="$(git config --get remote.origin.url)"
REPO_FULL_NAME="$(python3 - "$REPO_URL" <<'PY'
import sys
from urllib.parse import urlsplit

value = (sys.argv[1] or "").strip()
if "://" in value:
    path = urlsplit(value).path
elif ":" in value and "@" in value.split(":", 1)[0]:
    path = "/" + value.split(":", 1)[1]
else:
    path = value
parts = [part for part in path.split("/") if part]
if len(parts) < 2:
    raise SystemExit("failed to parse remote origin URL")
owner = parts[-2].strip()
repo = parts[-1].strip()
if repo.endswith(".git"):
    repo = repo[:-4]
print(f"{owner}/{repo}")
PY
)"

BRANCH_NAME="${GITHUB_REF_NAME:-}"
if [[ -z "$BRANCH_NAME" ]]; then
  RAW_REF="${GITHUB_REF:-${GITEA_REF:-}}"
  BRANCH_NAME="${RAW_REF#refs/heads/}"
fi
if [[ -z "$BRANCH_NAME" ]]; then
  BRANCH_NAME="$(git branch --show-current || true)"
fi
if [[ -z "$BRANCH_NAME" ]]; then
  echo "failed to determine branch name" >&2
  exit 1
fi

COMMIT_SHA="$(git rev-parse HEAD)"
INPUT_DEPLOY_TASK_ID="${DEPLOY_TASK_ID:-}"
INPUT_REQUESTED_BY="${REQUESTED_BY:-}"
INPUT_REASON="${REASON:-}"
INPUT_DRY_RUN="${DRY_RUN:-}"

REQUESTED_BY="${INPUT_REQUESTED_BY:-}"
if [[ -z "$REQUESTED_BY" ]]; then
  REQUESTED_BY="$(git log -1 --pretty=%an)"
fi

RELEASE_NOTES="${INPUT_REASON:-}"
if [[ -z "$RELEASE_NOTES" ]]; then
  RELEASE_NOTES="$(git log -1 --pretty=%s)"
fi

DRY_RUN_BUILD="false"
case "${INPUT_DRY_RUN,,}" in
  1|true|yes|y|on)
    DRY_RUN_BUILD="true"
    ;;
esac

VERSION_RAW="$(awk '/^version:/{print $2; exit}' pubspec.yaml)"
VERSION_NAME="${VERSION_RAW%%+*}"
PUBSPEC_BUILD="${VERSION_RAW##*+}"

CURRENT_LATEST_BUILD="$(curl -fsS "${EASYPOS_CI_BASE_URL%/}/api/app-update/check?platform=android&channel=prod&version=0.0.0&build=0" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(int(data.get("latest_build") or 0))')"
EFFECTIVE_BUILD="$PUBSPEC_BUILD"
if [[ "$CURRENT_LATEST_BUILD" =~ ^[0-9]+$ ]] && (( CURRENT_LATEST_BUILD >= EFFECTIVE_BUILD )); then
  EFFECTIVE_BUILD="$((CURRENT_LATEST_BUILD + 1))"
fi

FLUTTER_BIN="${EASYPOS_FLUTTER_BIN:-}"
if [[ -z "$FLUTTER_BIN" ]]; then
  for candidate in \
    "$(command -v flutter 2>/dev/null || true)" \
    "/opt/flutter/bin/flutter" \
    "$HOME/flutter/bin/flutter" \
    "$HOME/tools/flutter/bin/flutter"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      FLUTTER_BIN="$candidate"
      break
    fi
  done
fi
if [[ -z "$FLUTTER_BIN" || ! -x "$FLUTTER_BIN" ]]; then
  echo "flutter binary not found" >&2
  exit 1
fi

if [[ -n "${EASYPOS_ANDROID_SDK_ROOT:-}" && -d "${EASYPOS_ANDROID_SDK_ROOT}" ]]; then
  echo "ANDROID_HOME=${EASYPOS_ANDROID_SDK_ROOT}" >> "$GITHUB_ENV"
  echo "ANDROID_SDK_ROOT=${EASYPOS_ANDROID_SDK_ROOT}" >> "$GITHUB_ENV"
elif [[ -n "${ANDROID_HOME:-}" && -d "${ANDROID_HOME}" ]]; then
  echo "ANDROID_SDK_ROOT=${ANDROID_HOME}" >> "$GITHUB_ENV"
elif [[ -n "${ANDROID_SDK_ROOT:-}" && -d "${ANDROID_SDK_ROOT}" ]]; then
  echo "ANDROID_HOME=${ANDROID_SDK_ROOT}" >> "$GITHUB_ENV"
fi

{
  echo "REPO_FULL_NAME=$REPO_FULL_NAME"
  echo "BRANCH_NAME=$BRANCH_NAME"
  echo "COMMIT_SHA=$COMMIT_SHA"
  echo "REQUESTED_BY=$REQUESTED_BY"
  echo "RELEASE_NOTES=$RELEASE_NOTES"
  echo "VERSION_NAME=$VERSION_NAME"
  echo "PUBSPEC_BUILD=$PUBSPEC_BUILD"
  echo "BUILD_NUMBER=$EFFECTIVE_BUILD"
  echo "FLUTTER_BIN=$FLUTTER_BIN"
  echo "APK_PATH=$PWD/build/app/outputs/flutter-apk/app-release.apk"
  echo "REPORT_URL=${EASYPOS_CI_BASE_URL%/}/api/ci/flutter-apk/report"
  echo "REGISTER_URL=${EASYPOS_CI_BASE_URL%/}/api/ci/flutter-apk/register"
  echo "DEPLOY_TASK_ID=$INPUT_DEPLOY_TASK_ID"
  echo "DRY_RUN_BUILD=$DRY_RUN_BUILD"
} >> "$GITHUB_ENV"
)
load_github_env
echo '[GitLab CI] Report build start'
(
set -Eeuo pipefail
set -euo pipefail

PAYLOAD="$(python3 - <<'PY'
import json
import os

print(json.dumps({
    "repo_full_name": os.environ["REPO_FULL_NAME"],
    "branch": os.environ["BRANCH_NAME"],
    "commit_sha": os.environ["COMMIT_SHA"],
    "status": "building",
    "ref": f"refs/heads/{os.environ['BRANCH_NAME']}",
    "workflow_run_id": os.environ.get("GITHUB_RUN_ID", ""),
    "requested_by": os.environ.get("REQUESTED_BY", ""),
    "deploy_task_id": os.environ.get("DEPLOY_TASK_ID", ""),
}, ensure_ascii=False, separators=(",", ":")))
PY
)"
TIMESTAMP="$(date +%s)"
SIGNATURE="$(TIMESTAMP="$TIMESTAMP" PAYLOAD="$PAYLOAD" SECRET="$EASYPOS_FLUTTER_CI_CALLBACK_SECRET" python3 - <<'PY'
import hashlib
import hmac
import os

message = f"{os.environ['TIMESTAMP']}\n{os.environ['PAYLOAD']}".encode("utf-8")
print(hmac.new(os.environ["SECRET"].encode("utf-8"), message, hashlib.sha256).hexdigest())
PY
)"
curl -fsS \
  -X POST \
  -H "Content-Type: application/json" \
  -H "X-EasyPOS-CI-Timestamp: ${TIMESTAMP}" \
  -H "X-EasyPOS-CI-Signature: ${SIGNATURE}" \
  --data "$PAYLOAD" \
  "$REPORT_URL"
)
load_github_env
echo '[GitLab CI] Build release APK'
(
set -Eeuo pipefail
set -euo pipefail
export PATH="$(dirname "$FLUTTER_BIN"):$PATH"
"$FLUTTER_BIN" pub get
"$FLUTTER_BIN" build apk --release --build-name "$VERSION_NAME" --build-number "$BUILD_NUMBER"
)
load_github_env
echo '[GitLab CI] Complete dry-run without artifact registration'
(
set -Eeuo pipefail
set -euo pipefail
if [[ "${DRY_RUN_BUILD:-false}" != "true" ]]; then
  exit 0
fi

PAYLOAD="$(python3 - <<'PY'
import json
import os

print(json.dumps({
    "repo_full_name": os.environ["REPO_FULL_NAME"],
    "branch": os.environ["BRANCH_NAME"],
    "commit_sha": os.environ["COMMIT_SHA"],
    "status": "succeeded",
    "ref": f"refs/heads/{os.environ['BRANCH_NAME']}",
    "workflow_run_id": os.environ.get("GITHUB_RUN_ID", ""),
    "requested_by": os.environ.get("REQUESTED_BY", ""),
    "deploy_task_id": os.environ.get("DEPLOY_TASK_ID", ""),
}, ensure_ascii=False, separators=(",", ":")))
PY
)"
TIMESTAMP="$(date +%s)"
SIGNATURE="$(TIMESTAMP="$TIMESTAMP" PAYLOAD="$PAYLOAD" SECRET="$EASYPOS_FLUTTER_CI_CALLBACK_SECRET" python3 - <<'PY'
import hashlib
import hmac
import os

message = f"{os.environ['TIMESTAMP']}\n{os.environ['PAYLOAD']}".encode("utf-8")
print(hmac.new(os.environ["SECRET"].encode("utf-8"), message, hashlib.sha256).hexdigest())
PY
)"
curl -fsS \
  -X POST \
  -H "Content-Type: application/json" \
  -H "X-EasyPOS-CI-Timestamp: ${TIMESTAMP}" \
  -H "X-EasyPOS-CI-Signature: ${SIGNATURE}" \
  --data "$PAYLOAD" \
  "$REPORT_URL"
)
load_github_env
echo '[GitLab CI] Register APK release'
(
set -Eeuo pipefail
set -euo pipefail

if [[ "${DRY_RUN_BUILD:-false}" == "true" ]]; then
  exit 0
fi

if [[ ! -f "$APK_PATH" ]]; then
  echo "release APK not found: $APK_PATH" >&2
  exit 1
fi

SHA256="$(sha256sum "$APK_PATH" | awk '{print $1}')"
FILE_SIZE="$(stat -c %s "$APK_PATH")"
METADATA_JSON="$(SHA256="$SHA256" FILE_SIZE="$FILE_SIZE" python3 - <<'PY'
import json
import os

print(json.dumps({
    "repo_full_name": os.environ["REPO_FULL_NAME"],
    "branch": os.environ["BRANCH_NAME"],
    "commit_sha": os.environ["COMMIT_SHA"],
    "version_name": os.environ["VERSION_NAME"],
    "build_number": int(os.environ["BUILD_NUMBER"]),
    "ref": f"refs/heads/{os.environ['BRANCH_NAME']}",
    "workflow_run_id": os.environ.get("GITHUB_RUN_ID", ""),
    "requested_by": os.environ.get("REQUESTED_BY", ""),
    "release_notes": os.environ.get("RELEASE_NOTES", ""),
    "sha256": os.environ["SHA256"],
    "deploy_task_id": os.environ.get("DEPLOY_TASK_ID", ""),
}, ensure_ascii=False, separators=(",", ":")))
PY
)"
TIMESTAMP="$(date +%s)"
SIGNATURE="$(TIMESTAMP="$TIMESTAMP" METADATA_JSON="$METADATA_JSON" SECRET="$EASYPOS_FLUTTER_CI_CALLBACK_SECRET" python3 - <<'PY'
import hashlib
import hmac
import os

message = f"{os.environ['TIMESTAMP']}\n{os.environ['METADATA_JSON']}".encode("utf-8")
print(hmac.new(os.environ["SECRET"].encode("utf-8"), message, hashlib.sha256).hexdigest())
PY
)"
curl -fsS \
  -X POST \
  -H "X-EasyPOS-CI-Timestamp: ${TIMESTAMP}" \
  -H "X-EasyPOS-CI-Signature: ${SIGNATURE}" \
  --form-string "metadata_json=${METADATA_JSON}" \
  -F "apk=@${APK_PATH};type=application/vnd.android.package-archive" \
  "$REGISTER_URL"
)
load_github_env
