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

"$FLUTTER_BIN" pub get
"$FLUTTER_BIN" analyze
"$FLUTTER_BIN" test
