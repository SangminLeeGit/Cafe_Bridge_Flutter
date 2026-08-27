# CafeBridge Flutter Rules

- This repository is Android-only unless a task explicitly expands scope. Use
  WSL2 for development and the configured compatibility ADB server for devices.
- Treat `docs/TOPOLOGY.md` as the release authority. CT500 is runtime-only and
  CT600 is the protected `cafe-bridge-android-release` CI target only.
- Keep non-Android platform scaffolding inert. Preserve API contracts, role
  gates, and admin scope unless explicitly requested.
- OpenDesign project `cafebridge-flutter-android` edits
  `design/open-design/cafebridge-flutter-android/` directly and reads this
  repository as linked source. Track design artifacts in Git and prefer current
  Flutter code/contracts over stale artifact claims.
- Signing and production APK registration are protected CI/manual actions;
  never store signing material in the repository.
- Before committing, run feasible analyze, test, debug build, and diff checks.
