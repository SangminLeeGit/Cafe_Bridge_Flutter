# Copilot instructions

## Repository policy

- Android is the only supported target unless a task explicitly says otherwise. Generated iOS, Web, Linux, macOS, and Windows scaffolding is unsupported and inert.
- Work on WSL2 for development, OpenCode, OpenDesign, and Flutter/Gradle. Use the configured shared compatibility ADB server for device checks. CT500 is runtime/deployment only.
- Follow `docs/TOPOLOGY.md`. A localhost OpenDesign URL is local to WSL2; use the approved LAN proxy from other clients.
- Signed release APKs and production registration are CI/CD-only. Do not create an IPA, perform a local signed release, or add/read signing material or values.
- Ordinary pushes may validate and produce APK artifacts, but production APK registration requires an explicit protected promotion/manual action.

## Build, test, and lint

- Install dependencies: `flutter pub get`
- Lint/static analysis: `flutter analyze`
- Run the full test suite: `flutter test`
- Run a single test file: `flutter test test/menu_workspace_models_test.dart`
- Run a single named test: `flutter test test/menu_workspace_models_test.dart --plain-name "WorkspaceTaskHistoryEntry parses applied new-item task result"`
- Android debug build: `ANDROID_HOME=/home/sangmin/dev/sdk/android-sdk ANDROID_SDK_ROOT=/home/sangmin/dev/sdk/android-sdk flutter build apk --debug`

## High-level architecture

- `lib/main.dart` creates a single `AppState`, loads local state before `runApp`, and starts remote restoration after providing it with `ChangeNotifierProvider`. `AppRoot` shows `LoginScreen` until a restored or refreshed session becomes authenticated, then switches to `MainLayout`.
- `lib/state/app_state.dart` is the application boundary. It owns session-facing state and orchestration, while `ApiClient`, `ApiCacheStore`, and `ActiveTaskStore` own HTTP, JSON cache, and resumable-task persistence respectively.
- `lib/services/api.dart` contains pure URL/date policy plus the injectable `ApiClient`: timeout handling, GET/POST requests, JSON decoding, transport errors, and session-cookie extraction. `lib/services/cache_store.dart` persists cached JSON in `SharedPreferences`, scoped by `loginId@baseUrl`.
- Authenticated screens go through `AppState`; settings health checking also goes through `AppState.checkConnection`. UI code does not access `SharedPreferences` directly.
- `lib/screens/` is feature-oriented. Dashboard, analytics, sync, costing, menu workspace, signage, and workforce each manage their own screen-local loading/error/polling state and parse backend payloads into immutable models under `lib/models/`.
- `OperationsScreen` is the operational hub that routes into costing, menu workspace, signage, and sync. `lib/screens/workforce.dart` is only an export shim to `workforce_mobile.dart`.
- `MenuWorkspaceScreen` is the densest feature. It has a product-browser tab plus a workspace tab; the workspace tab loads the snapshot, validation state, apply runs, and task histories in parallel and refreshes through a shared `ValueNotifier`.
- App update and deploy-notice behavior is cross-cutting. `AppState` drives it, and UI surfaces exist in login, main layout, and settings.

## Key conventions

- Keep global/shared state in `AppState`; keep feature filters, tab controllers, timers, and request lifecycle flags inside the screen `State` object. This repo does not use a second global state layer.
- Respect role gating with `UserRole`, `canAccess`, `hasOperatorAccess`, and `hasAdminAccess`. Screens and actions are commonly hidden instead of shown-disabled.
- Parse backend JSON with the helpers in `lib/models/api_contracts.dart` (`asString`, `asInt`, `asBool`, `asMap`, `asListOfMaps`, etc.). Existing models are intentionally tolerant of mixed backend types and usually expose immutable fields plus `fromJson`.
- Preserve offline behavior when using `fetchMapParsed`: pass through `fromCache` and `cachedAt`, and show `CacheNotice` when stale cached data is being displayed.
- For async backend jobs (for example sync runs and menu workspace apply flows), the established pattern is: start the job with `appState.postJson(...)`, store the returned task id, then poll the task status endpoint from widget state with a `Timer` until completion.
- UI structure is intentionally consistent: loading spinner -> `EmptyState` on failure/empty data -> `RefreshIndicator` with `ListView`/`CustomScrollView` sections built from shared widgets such as `Panel`, `StatCard`, and `CacheNotice`.
- UI copy is mostly Korean, including operational labels and user-facing error messages. Match the existing language and tone when editing screens.
- Server/base-URL changes and auth resets intentionally clear local session/cache state. Do not introduce separate persisted feature caches unless they are meant to survive that reset behavior.
