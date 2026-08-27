# Cafe Bridge Flutter Topology

This document is authoritative for repository platform, host, validation, and release policy. Dated reports describe the state observed when they were written and do not override this policy.

## Platform Scope

- Android is the only supported application target unless a task explicitly requests another platform.
- `android/`, `lib/`, and Android-relevant tests and assets are active.
- Generated `ios/`, `web/`, `linux/`, `macos/`, and `windows/` directories remain in the repository as unsupported, inert Flutter scaffolding. Their presence does not create build, test, release, or maintenance requirements.
- Do not publish an IPA or any non-Android artifact. There is no local signed-release path.

## Host Roles

| Host | Role | Allowed work |
| --- | --- | --- |
| WSL2 | Development tooling | Repository edits, OpenCode, OpenDesign, Flutter/Gradle validation, Android SDK tools, and the shared compatibility ADB client |
| VM900 | Reference and device bridge | Read-only reference/rollback source and owner of the managed ADB server; not an active development workspace |
| CT500 | Runtime and deployment | Deployed service/application runtime only; no development workspace, OpenCode/OpenChamber, Flutter build, emulator, or ADB workflow |
| CT600 | Protected release runner | Security checks, Android validation, signed APK artifacts, and explicit production promotion on the project-specific `cafe-bridge-android-release` runner only; no development workspace, OpenCode/OpenChamber, emulator, or ADB workflow |

WSL2 device checks use `ADB_SERVER_SOCKET=tcp:192.168.1.254:5037` against VM900's managed compatibility ADB server. Do not pair, connect, run `adb tcpip`, start or stop the server, or launch a second ADB server. Device-dependent checks may be reported as not run when no approved Android device is available through that server.

## Repository And Design Policy

- Development occurs in `/home/sangmin/dev/workspaces/cafe-bridge-flutter` on WSL2.
- The checked-out task branch is the source of truth. `main`, `origin/design`, dated design commits, HTML/CSS design exports, and OpenDesign snapshots are references only and must not be merged or copied over active implementation blindly.
- OpenDesign runs on WSL2. Its daemon preview is WSL2-local on `127.0.0.1:7457`; the approved LAN compatibility endpoint is `http://192.168.1.213:7456`. Neither is a CT500 endpoint.
- Product API contracts, role gates, and admin feature scope are outside topology cleanup work.

## Validation

The active baseline is:

```bash
/home/sangmin/dev/sdk/flutter-3.41.7/bin/flutter pub get --enforce-lockfile
/home/sangmin/dev/sdk/flutter-3.41.7/bin/flutter analyze
/home/sangmin/dev/sdk/flutter-3.41.7/bin/flutter test
ANDROID_HOME=/home/sangmin/dev/sdk/android-sdk \
ANDROID_SDK_ROOT=/home/sangmin/dev/sdk/android-sdk \
/home/sangmin/dev/sdk/flutter-3.41.7/bin/flutter build apk --debug
```

Also run shell/YAML syntax checks and `git diff --check` when those files change. Web, iOS, IPA, desktop, AVD, and device tests are not mandatory gates.

## Release And Promotion

- Signed release APKs are built only by CI/CD on CT600's protected `cafe-bridge-android-release` runner. The legacy CT500 runner remains disabled.
- The CT600 shell-runner account uses a non-interactive-safe login profile and keeps mutable build/cache data on `/mnt/sandisk`; do not restore interactive console cleanup or CT500 cache paths.
- Signing credentials and keystore content exist only as protected CI variables/material. Never read, print, copy, synthesize, or commit them.
- Ordinary protected pushes retain security checks, Flutter validation, and signed APK artifacts, but do not register a production APK.
- Production APK registration requires an explicit protected API/trigger promotion or a manual protected web pipeline action.
- A CI dry run means build and artifact verification without production registration.
