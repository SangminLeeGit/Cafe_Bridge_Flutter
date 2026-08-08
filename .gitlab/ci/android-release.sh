#!/usr/bin/env bash
set -Eeuo pipefail

export GITHUB_RUN_ID="${CI_PIPELINE_ID}"
export GITHUB_RUN_NUMBER="${CI_PIPELINE_IID}"
export GITHUB_SHA="${CI_COMMIT_SHA}"
export GITHUB_REF_NAME="${CI_COMMIT_REF_NAME}"
export GITHUB_REPOSITORY="${CI_PROJECT_PATH}"
export GITHUB_ACTOR="${GITLAB_USER_LOGIN:-gitlab-ci}"
export GITHUB_WORKSPACE="${CI_PROJECT_DIR}"
# A dry-run against a commit that already has a registered release is a new
# CI attempt, not a mutation of the immutable release record. Track that
# attempt with a deterministic per-pipeline SHA while release registration
# continues to use the real commit SHA below.
export REPORT_COMMIT_SHA="${CI_COMMIT_SHA}"
case "${DRY_RUN:-false}" in
  1|true|yes|y|on)
    REPORT_COMMIT_SHA="$(printf '%s' "${CI_COMMIT_SHA}:${CI_PIPELINE_ID}" | sha256sum | cut -c1-40)"
    ;;
esac
if [[ -n "${CI_COMMIT_TAG:-}" ]]; then
  export GITHUB_REF="refs/tags/${CI_COMMIT_TAG}"
else
  export GITHUB_REF="refs/heads/${CI_COMMIT_BRANCH}"
fi
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
if (( job_status != 0 )) && [[ -n "${REPORT_URL:-}" && -n "${CAFE_BRIDGE_FLUTTER_CI_CALLBACK_SECRET:-}" ]]; then
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
    "commit_sha": os.environ.get("REPORT_COMMIT_SHA", ""),
    "status": "failed",
    "ref": os.environ.get("GITHUB_REF", ""),
    "workflow_run_id": os.environ.get("GITHUB_RUN_ID", ""),
    "requested_by": os.environ.get("REQUESTED_BY", ""),
    "error_message": "android release workflow failed",
    "deploy_task_id": os.environ.get("DEPLOY_TASK_ID", ""),
}, ensure_ascii=False, separators=(",", ":")))
PY
)"
DELIVERY_ID="$(python3 -c 'import uuid; print(uuid.uuid4())')"
TIMESTAMP="$(date +%s)"
SIGNATURE="$(TIMESTAMP="$TIMESTAMP" DELIVERY_ID="$DELIVERY_ID" PAYLOAD="$PAYLOAD" SECRET="$CAFE_BRIDGE_FLUTTER_CI_CALLBACK_SECRET" python3 - <<'PY'
import hashlib
import hmac
import os

message = f"{os.environ['TIMESTAMP']}\n{os.environ['DELIVERY_ID']}\n{os.environ['PAYLOAD']}".encode("utf-8")
print(hmac.new(os.environ["SECRET"].encode("utf-8"), message, hashlib.sha256).hexdigest())
PY
)"
curl -fsS \
  -X POST \
  -H "Content-Type: application/json" \
  -H "X-Cafe-Bridge-CI-Timestamp: ${TIMESTAMP}" \
  -H "X-Cafe-Bridge-CI-Delivery: ${DELIVERY_ID}" \
  -H "X-Cafe-Bridge-CI-Signature: ${SIGNATURE}" \
  --data "$PAYLOAD" \
  "$REPORT_URL"
)
load_github_env

fi
  if [[ -n "${KEYSTORE_PATH:-}" ]]; then
    rm -f "$KEYSTORE_PATH"
  fi
  exit "${job_status}"
}
trap finalize_job EXIT

echo '[GitLab CI] Prepare CI environment'
(
set -Eeuo pipefail
set -euo pipefail

export CAFE_BRIDGE_CI_BASE_URL CAFE_BRIDGE_FLUTTER_CI_CALLBACK_SECRET
export CAFE_BRIDGE_FLUTTER_BIN CAFE_BRIDGE_ANDROID_SDK_ROOT
export CAFE_BRIDGE_ANDROID_KEYSTORE_BASE64 CAFE_BRIDGE_ANDROID_KEY_ALIAS
export CAFE_BRIDGE_ANDROID_STORE_PASSWORD CAFE_BRIDGE_ANDROID_KEY_PASSWORD
export CAFE_BRIDGE_ANDROID_CERT_SHA256

if [[ -z "${CAFE_BRIDGE_CI_BASE_URL:-}" ]]; then
  echo "CAFE_BRIDGE_CI_BASE_URL secret is required" >&2
  exit 1
fi
if [[ -z "${CAFE_BRIDGE_FLUTTER_CI_CALLBACK_SECRET:-}" ]]; then
  echo "CAFE_BRIDGE_FLUTTER_CI_CALLBACK_SECRET secret is required" >&2
  exit 1
fi
if [[ -z "${CAFE_BRIDGE_ANDROID_KEYSTORE_BASE64:-}" ]]; then
  echo "CAFE_BRIDGE_ANDROID_KEYSTORE_BASE64 is required" >&2
  exit 1
fi
if [[ -z "${CAFE_BRIDGE_ANDROID_KEY_ALIAS:-}" || -z "${CAFE_BRIDGE_ANDROID_STORE_PASSWORD:-}" || -z "${CAFE_BRIDGE_ANDROID_KEY_PASSWORD:-}" ]]; then
  echo "Android release signing credentials are required" >&2
  exit 1
fi
if [[ -z "${CAFE_BRIDGE_ANDROID_CERT_SHA256:-}" ]]; then
  echo "CAFE_BRIDGE_ANDROID_CERT_SHA256 is required" >&2
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
  RAW_REF="${GITHUB_REF:-}"
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

CURRENT_LATEST_BUILD="$(curl -fsS "${CAFE_BRIDGE_CI_BASE_URL%/}/api/app-update/check?platform=android&channel=prod&version=0.0.0&build=0" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(int(data.get("latest_build") or 0))')"
EFFECTIVE_BUILD="$PUBSPEC_BUILD"
if [[ "$CURRENT_LATEST_BUILD" =~ ^[0-9]+$ ]] && (( CURRENT_LATEST_BUILD >= EFFECTIVE_BUILD )); then
  EFFECTIVE_BUILD="$((CURRENT_LATEST_BUILD + 1))"
fi

FLUTTER_BIN="${CAFE_BRIDGE_FLUTTER_BIN:-}"
if [[ -z "$FLUTTER_BIN" || ! -x "$FLUTTER_BIN" ]]; then
  echo "CAFE_BRIDGE_FLUTTER_BIN must point to an executable Flutter binary" >&2
  exit 1
fi

if [[ -z "${CAFE_BRIDGE_ANDROID_SDK_ROOT:-}" || ! -d "${CAFE_BRIDGE_ANDROID_SDK_ROOT}" ]]; then
  echo "CAFE_BRIDGE_ANDROID_SDK_ROOT must point to the Android SDK" >&2
  exit 1
fi

KEYSTORE_PATH="${RUNNER_TEMP}/cafe-bridge-release.jks"
printf '%s' "$CAFE_BRIDGE_ANDROID_KEYSTORE_BASE64" | base64 --decode > "$KEYSTORE_PATH"
chmod 600 "$KEYSTORE_PATH"

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
  echo "ANDROID_HOME=${CAFE_BRIDGE_ANDROID_SDK_ROOT}"
  echo "ANDROID_SDK_ROOT=${CAFE_BRIDGE_ANDROID_SDK_ROOT}"
  echo "KEYSTORE_PATH=$KEYSTORE_PATH"
  echo "APK_PATH=$PWD/build/app/outputs/flutter-apk/app-release.apk"
  echo "REPORT_URL=${CAFE_BRIDGE_CI_BASE_URL%/}/api/ci/flutter-apk/report"
  echo "REGISTER_URL=${CAFE_BRIDGE_CI_BASE_URL%/}/api/ci/flutter-apk/register"
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
    "commit_sha": os.environ["REPORT_COMMIT_SHA"],
    "status": "building",
    "ref": os.environ.get("GITHUB_REF", ""),
    "workflow_run_id": os.environ.get("GITHUB_RUN_ID", ""),
    "requested_by": os.environ.get("REQUESTED_BY", ""),
    "deploy_task_id": os.environ.get("DEPLOY_TASK_ID", ""),
}, ensure_ascii=False, separators=(",", ":")))
PY
)"
DELIVERY_ID="$(python3 -c 'import uuid; print(uuid.uuid4())')"
TIMESTAMP="$(date +%s)"
SIGNATURE="$(TIMESTAMP="$TIMESTAMP" DELIVERY_ID="$DELIVERY_ID" PAYLOAD="$PAYLOAD" SECRET="$CAFE_BRIDGE_FLUTTER_CI_CALLBACK_SECRET" python3 - <<'PY'
import hashlib
import hmac
import os

message = f"{os.environ['TIMESTAMP']}\n{os.environ['DELIVERY_ID']}\n{os.environ['PAYLOAD']}".encode("utf-8")
print(hmac.new(os.environ["SECRET"].encode("utf-8"), message, hashlib.sha256).hexdigest())
PY
)"
curl -fsS \
  -X POST \
  -H "Content-Type: application/json" \
  -H "X-Cafe-Bridge-CI-Timestamp: ${TIMESTAMP}" \
  -H "X-Cafe-Bridge-CI-Delivery: ${DELIVERY_ID}" \
  -H "X-Cafe-Bridge-CI-Signature: ${SIGNATURE}" \
  --data "$PAYLOAD" \
  "$REPORT_URL"
)
load_github_env
echo '[GitLab CI] Build release APK'
(
set -Eeuo pipefail
set -euo pipefail
export PATH="$(dirname "$FLUTTER_BIN"):$PATH"
export ANDROID_HOME ANDROID_SDK_ROOT
export CAFE_BRIDGE_ANDROID_KEYSTORE_PATH="$KEYSTORE_PATH"
cleanup_gradle() {
  if command -v gradle >/dev/null 2>&1; then gradle --stop >/dev/null 2>&1 || true; fi
  pkill -u "$(id -u)" -f 'KotlinCompileDaemon' >/dev/null 2>&1 || true
}
trap cleanup_gradle EXIT INT TERM
EXPECTED_FLUTTER_VERSION="$(tr -d '[:space:]' < .flutter-version)"
EXPECTED_FLUTTER_REVISION="$(tr -d '[:space:]' < .flutter-revision)"
FLUTTER_VERSION_JSON="$("$FLUTTER_BIN" --version --machine)"
ACTUAL_FLUTTER_VERSION="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["frameworkVersion"])' <<< "$FLUTTER_VERSION_JSON")"
ACTUAL_FLUTTER_REVISION="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["frameworkRevision"])' <<< "$FLUTTER_VERSION_JSON")"
if [[ "$ACTUAL_FLUTTER_VERSION" != "$EXPECTED_FLUTTER_VERSION" ]]; then
  echo "Flutter version mismatch: expected $EXPECTED_FLUTTER_VERSION, got $ACTUAL_FLUTTER_VERSION" >&2
  exit 1
fi
if [[ "$ACTUAL_FLUTTER_REVISION" != "$EXPECTED_FLUTTER_REVISION" ]]; then
  echo "Flutter revision mismatch: expected $EXPECTED_FLUTTER_REVISION, got $ACTUAL_FLUTTER_REVISION" >&2
  exit 1
fi
"$FLUTTER_BIN" pub get --enforce-lockfile
"$FLUTTER_BIN" build apk --release --build-name "$VERSION_NAME" --build-number "$BUILD_NUMBER"

APKSIGNER="${ANDROID_SDK_ROOT}/build-tools/35.0.0/apksigner"
if [[ ! -x "$APKSIGNER" ]]; then
  APKSIGNER=""
  for candidate in "${ANDROID_SDK_ROOT}"/build-tools/*/apksigner; do
    if [[ -x "$candidate" ]]; then
      APKSIGNER="$candidate"
    fi
  done
fi
if [[ -z "$APKSIGNER" || ! -x "$APKSIGNER" ]]; then
  echo "apksigner not found under: ${ANDROID_SDK_ROOT}/build-tools" >&2
  exit 1
fi
APKSIGNER_OUTPUT="$("$APKSIGNER" verify --verbose --print-certs "$APK_PATH")"
ACTUAL_CERT_SHA256=""
while IFS= read -r line; do
  case "$line" in
    *"certificate SHA-256 digest:"*)
      ACTUAL_CERT_SHA256="${line##*: }"
      break
      ;;
  esac
done <<< "$APKSIGNER_OUTPUT"
ACTUAL_CERT_SHA256="${ACTUAL_CERT_SHA256//:/}"
if [[ -z "$ACTUAL_CERT_SHA256" || "${ACTUAL_CERT_SHA256,,}" != "${CAFE_BRIDGE_ANDROID_CERT_SHA256,,}" ]]; then
  echo "APK signing certificate fingerprint mismatch" >&2
  exit 1
fi
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
    "commit_sha": os.environ["REPORT_COMMIT_SHA"],
    "status": "succeeded",
    "ref": os.environ.get("GITHUB_REF", ""),
    "workflow_run_id": os.environ.get("GITHUB_RUN_ID", ""),
    "requested_by": os.environ.get("REQUESTED_BY", ""),
    "deploy_task_id": os.environ.get("DEPLOY_TASK_ID", ""),
}, ensure_ascii=False, separators=(",", ":")))
PY
)"
DELIVERY_ID="$(python3 -c 'import uuid; print(uuid.uuid4())')"
TIMESTAMP="$(date +%s)"
SIGNATURE="$(TIMESTAMP="$TIMESTAMP" DELIVERY_ID="$DELIVERY_ID" PAYLOAD="$PAYLOAD" SECRET="$CAFE_BRIDGE_FLUTTER_CI_CALLBACK_SECRET" python3 - <<'PY'
import hashlib
import hmac
import os

message = f"{os.environ['TIMESTAMP']}\n{os.environ['DELIVERY_ID']}\n{os.environ['PAYLOAD']}".encode("utf-8")
print(hmac.new(os.environ["SECRET"].encode("utf-8"), message, hashlib.sha256).hexdigest())
PY
)"
curl -fsS \
  -X POST \
  -H "Content-Type: application/json" \
  -H "X-Cafe-Bridge-CI-Timestamp: ${TIMESTAMP}" \
  -H "X-Cafe-Bridge-CI-Delivery: ${DELIVERY_ID}" \
  -H "X-Cafe-Bridge-CI-Signature: ${SIGNATURE}" \
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
    "ref": os.environ.get("GITHUB_REF", ""),
    "workflow_run_id": os.environ.get("GITHUB_RUN_ID", ""),
    "requested_by": os.environ.get("REQUESTED_BY", ""),
    "release_notes": os.environ.get("RELEASE_NOTES", ""),
    "sha256": os.environ["SHA256"],
    "deploy_task_id": os.environ.get("DEPLOY_TASK_ID", ""),
}, ensure_ascii=False, separators=(",", ":")))
PY
)"
TIMESTAMP="$(date +%s)"
DELIVERY_ID="$(python3 -c 'import uuid; print(uuid.uuid4())')"
SIGNATURE="$(TIMESTAMP="$TIMESTAMP" DELIVERY_ID="$DELIVERY_ID" METADATA_JSON="$METADATA_JSON" SECRET="$CAFE_BRIDGE_FLUTTER_CI_CALLBACK_SECRET" python3 - <<'PY'
import hashlib
import hmac
import os

message = f"{os.environ['TIMESTAMP']}\n{os.environ['DELIVERY_ID']}\n{os.environ['METADATA_JSON']}".encode("utf-8")
print(hmac.new(os.environ["SECRET"].encode("utf-8"), message, hashlib.sha256).hexdigest())
PY
)"
curl -fsS \
  -X POST \
  -H "X-Cafe-Bridge-CI-Timestamp: ${TIMESTAMP}" \
  -H "X-Cafe-Bridge-CI-Delivery: ${DELIVERY_ID}" \
  -H "X-Cafe-Bridge-CI-Signature: ${SIGNATURE}" \
  --form-string "metadata_json=${METADATA_JSON}" \
  -F "apk=@${APK_PATH};type=application/vnd.android.package-archive" \
  "$REGISTER_URL"
)
load_github_env
