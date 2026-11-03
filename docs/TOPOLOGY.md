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
| CT500 | Runtime/deployment and dedicated Flutter CI host | Deployed service/application runtime plus the currently observed protected GitLab Flutter runner; not a general development, manual-build, emulator, or ADB host |
| CT600 | No current Flutter runner registration verified | The release script accepts a future dedicated CT600 Cafe Bridge Flutter runner; no such runner is currently registered |

GitLab API observation on 2026-11-03 KST: runner 13 (`ct500-cafebridge-flutter-release`) was `online`, protected, and tagged `cafe-bridge-android-release`. Its online manager was ID 13, IP `192.168.1.230`, Linux/amd64. This verifies GitLab-side registration and manager status only; it does not verify the host's current service/account, installed tool pins, cache directories, or successful job execution. The 2026-10-21 host record listed `gitlab-runner-cafebridge-flutter.service` and the `flutter-runner` account, but those host details were not re-audited for this update. `.gitlab-ci.yml` currently declares Pub and Gradle caches at `/var/lib/flutter-runner/cache/pub` and `/var/lib/flutter-runner/cache/gradle`; those declarations do not independently verify the directories exist.

WSL2 device checks use `ADB_SERVER_SOCKET=tcp:192.168.1.254:5037` against VM900's managed compatibility ADB server. Do not pair, connect, run `adb tcpip`, start or stop the server, or launch a second ADB server. Device-dependent checks may be reported as not run when no approved Android device is available through that server.

## Repository And Design Policy

- Development occurs in `/home/sangmin/dev/workspaces/cafe-bridge-flutter` on WSL2.
- Flutter `master` is the only retained local and remote branch. On 2026-10-23 the user explicitly approved retiring all other refs, including the protected `main` reference and the unmerged `design`/`release` work, after their status was explained. Historical branch names in plans are not instructions to recreate or merge those branches. The existing unrelated local work remains preserved; branch cleanup does not authorize discarding it.
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

- `.gitlab-ci.yml` routes security, validation, and release jobs by the `cafe-bridge-android-release` tag; it does not pin those jobs to a host. The live GitLab observation above identifies Runner 13 on CT500.
- `.gitlab/ci/android-release.sh` accepts only the exact descriptions `ct500-cafebridge-flutter-release` and `ct600-cafebridge-flutter-release`, and it refuses signing/registration unless `CI_COMMIT_REF_PROTECTED=true`. The observed Runner 13 description matches the first allowlist entry. Any new release host requires a reviewed allowlist update and fresh validation; do not bypass the guard.
- Signing credentials and keystore content exist only as protected CI variables/material. Never read, print, copy, synthesize, or commit them.
- Protected `master`, `release/*`, and tag pushes are configured for security checks, Flutter validation, and a signed APK dry-run artifact, but do not register a production APK. A successful signed dry run is still required before claiming the release path works.
- Production APK registration requires an explicit protected API/trigger promotion or a manual protected web pipeline action.
- A CI dry run means build and artifact verification without production registration.
