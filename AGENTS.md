# Repository Guidance

- This repository is Android-only unless a task explicitly expands platform scope.
- Perform development, OpenCode/OpenChamber/OpenDesign work, Flutter commands, and native ADB on VM900. CT500 is runtime/deployment only; CT600 is the protected `android-release` CI target only.
- Use `docs/TOPOLOGY.md` as the authoritative environment and release policy.
- Keep generated `ios/`, `web/`, `linux/`, `macos/`, and `windows/` scaffolding inert; do not validate, release, or extend it by default.
- Build signed release APKs only in CI/CD with protected variables. Never add signing material or signing values to the repository.
- Production APK registration requires an explicit protected promotion/manual action. Ordinary pushes may validate and build artifacts but must not register a production release.
- Preserve product API contracts, role gates, and admin feature scope unless explicitly requested.
- Before committing, run feasible Android-focused analyze, test, debug build, syntax, and diff checks. Do not push unless explicitly requested.
