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
| VM900 | Development and CI tooling | Repository edits, OpenCode, OpenChamber, OpenDesign, Flutter/Gradle validation, Android SDK tools, and native ADB |
| CT500 | Runtime and deployment | Deployed service/application runtime only; no development workspace, OpenCode/OpenChamber, Flutter build, emulator, or ADB workflow |
| CT600 | Protected release runner | Security checks, Android validation, signed APK artifacts, and explicit production promotion on the project-specific `cafe-bridge-android-release` runner only; no development workspace, OpenCode/OpenChamber, emulator, or ADB workflow |

ADB is native to VM900. Do not use historical remote-ADB bridges or make a historical AVD limitation a current topology requirement. Device-dependent checks may be reported as not run when no approved Android device is attached to VM900.

## Repository And Design Policy

- Development occurs in `/home/sangmin/workspaces/cafe-bridge-flutter` on VM900.
- The checked-out task branch is the source of truth. `main`, `origin/design`, dated design commits, HTML/CSS design exports, and OpenDesign snapshots are references only and must not be merged or copied over active implementation blindly.
- OpenDesign and its localhost preview are VM900-local tools. A `127.0.0.1` OpenDesign URL refers to VM900 and is not a CT500 endpoint or a remotely published service.
- Product API contracts, role gates, and admin feature scope are outside topology cleanup work.

## Validation

The active baseline is:

```bash
/home/sangmin/tools/flutter/bin/flutter pub get --enforce-lockfile
/home/sangmin/tools/flutter/bin/flutter analyze
/home/sangmin/tools/flutter/bin/flutter test
ANDROID_HOME=/opt/android-builder/android-sdk \
ANDROID_SDK_ROOT=/opt/android-builder/android-sdk \
/home/sangmin/tools/flutter/bin/flutter build apk --debug
```

Also run shell/YAML syntax checks and `git diff --check` when those files change. Web, iOS, IPA, desktop, AVD, and device tests are not mandatory gates.

## Release And Promotion

- Signed release APKs are built only by CI/CD on CT600's protected `cafe-bridge-android-release` runner. The legacy CT500 runner remains disabled.
- Signing credentials and keystore content exist only as protected CI variables/material. Never read, print, copy, synthesize, or commit them.
- Ordinary protected pushes retain security checks, Flutter validation, and signed APK artifacts, but do not register a production APK.
- Production APK registration requires an explicit protected API/trigger promotion or a manual protected web pipeline action.
- A CI dry run means build and artifact verification without production registration.
