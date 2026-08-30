#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/timing.sh"

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

FLUTTER_SDK_ROOT="$(cd "$(dirname "$FLUTTER_BIN")/.." && pwd -P)"
FLUTTER_EXTENSION="$FLUTTER_SDK_ROOT/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt"
if [[ ! -f "$FLUTTER_EXTENSION" ]]; then
  echo "Flutter Android extension metadata is missing: $FLUTTER_EXTENSION" >&2
  exit 1
fi
NDK_VERSION_LINE="$(grep -E 'val ndkVersion: String = "[0-9.]+"' "$FLUTTER_EXTENSION")"
EXPECTED_NDK_VERSION="${NDK_VERSION_LINE#*\"}"
EXPECTED_NDK_VERSION="${EXPECTED_NDK_VERSION%%\"*}"
NDK_PROPERTIES="$ANDROID_SDK_ROOT/ndk/$EXPECTED_NDK_VERSION/source.properties"
if [[ -z "$EXPECTED_NDK_VERSION" || ! -f "$NDK_PROPERTIES" ]]; then
  echo "Host-managed Android NDK is missing: $ANDROID_SDK_ROOT/ndk/$EXPECTED_NDK_VERSION" >&2
  exit 1
fi
grep -Eq "^Pkg\\.Revision[[:space:]]*=[[:space:]]*$EXPECTED_NDK_VERSION$" "$NDK_PROPERTIES"
EXPECTED_BUILD_TOOLS_VERSION="34.0.0"
BUILD_TOOLS_PROPERTIES="$ANDROID_SDK_ROOT/build-tools/$EXPECTED_BUILD_TOOLS_VERSION/source.properties"
if [[ ! -f "$BUILD_TOOLS_PROPERTIES" ]]; then
  echo "Host-managed Android Build Tools are missing: $ANDROID_SDK_ROOT/build-tools/$EXPECTED_BUILD_TOOLS_VERSION" >&2
  exit 1
fi
grep -Eq "^Pkg\\.Revision[[:space:]]*=[[:space:]]*$EXPECTED_BUILD_TOOLS_VERSION$" "$BUILD_TOOLS_PROPERTIES"
EXPECTED_ANDROID_PLATFORM="34"
PLATFORM_PROPERTIES="$ANDROID_SDK_ROOT/platforms/android-$EXPECTED_ANDROID_PLATFORM/source.properties"
if [[ ! -f "$PLATFORM_PROPERTIES" ]]; then
  echo "Host-managed Android platform is missing: $ANDROID_SDK_ROOT/platforms/android-$EXPECTED_ANDROID_PLATFORM" >&2
  exit 1
fi
grep -Eq "^AndroidVersion\\.ApiLevel[[:space:]]*=[[:space:]]*$EXPECTED_ANDROID_PLATFORM$" "$PLATFORM_PROPERTIES"
EXPECTED_CMAKE_VERSION="3.22.1"
CMAKE_PROPERTIES="$ANDROID_SDK_ROOT/cmake/$EXPECTED_CMAKE_VERSION/source.properties"
if [[ ! -f "$CMAKE_PROPERTIES" ]]; then
  echo "Host-managed Android CMake is missing: $ANDROID_SDK_ROOT/cmake/$EXPECTED_CMAKE_VERSION" >&2
  exit 1
fi
grep -Eq "^Pkg\\.Revision[[:space:]]*=[[:space:]]*$EXPECTED_CMAKE_VERSION$" "$CMAKE_PROPERTIES"

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

ci_timing "flutter_pub_get" "$FLUTTER_BIN" pub get --enforce-lockfile
ci_timing "flutter_analyze" "$FLUTTER_BIN" analyze
ci_timing "flutter_test" "$FLUTTER_BIN" test
ci_timing "flutter_build_debug" "$FLUTTER_BIN" build apk --debug --no-pub
