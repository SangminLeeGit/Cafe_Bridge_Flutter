#!/usr/bin/env bash
set -Eeuo pipefail

FLUTTER_BIN="${CAFE_BRIDGE_FLUTTER_BIN:-}"
ANDROID_SDK_ROOT="${CAFE_BRIDGE_ANDROID_SDK_ROOT:-}"

if [[ -z "$FLUTTER_BIN" || ! -x "$FLUTTER_BIN" ]]; then
  echo "CAFE_BRIDGE_FLUTTER_BIN must point to an executable Flutter binary" >&2
  exit 1
fi
if [[ -z "$ANDROID_SDK_ROOT" || ! -d "$ANDROID_SDK_ROOT" ]]; then
  echo "CAFE_BRIDGE_ANDROID_SDK_ROOT must point to the Android SDK" >&2
  exit 1
fi

export ANDROID_HOME="$ANDROID_SDK_ROOT"
export ANDROID_SDK_ROOT
export PATH="$(dirname "$FLUTTER_BIN"):$ANDROID_SDK_ROOT/platform-tools:$PATH"

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
"$FLUTTER_BIN" analyze
"$FLUTTER_BIN" test
