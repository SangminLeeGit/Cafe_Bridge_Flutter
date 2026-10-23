# CafeBridge Flutter Rules

- This repository is Android-only unless a task explicitly expands scope. Use
  WSL2 for development and the configured compatibility ADB server for devices.
- Treat `docs/TOPOLOGY.md` as the topology and release authority. Current GitLab
  state records protected Flutter Runner 13 on CT500 alongside the application
  runtime; CT500 is not a general development/manual-build or device host. Do
  not assume CT600 is a currently available Flutter runner.
- Keep non-Android platform scaffolding inert. Preserve API contracts, role
  gates, and admin scope unless explicitly requested.
- OpenDesign project `cafebridge-flutter-android` edits
  `design/open-design/cafebridge-flutter-android/` directly and reads this
  repository as linked source. Track design artifacts in Git and prefer current
  Flutter code/contracts over stale artifact claims.
- Signing and production APK registration are protected CI/manual actions;
  never store signing material in the repository.
- Before committing, run feasible analyze, test, debug build, and diff checks.
