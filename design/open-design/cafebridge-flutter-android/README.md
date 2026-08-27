# CafeBridge Flutter Android · OpenDesign Atlas

현재 Flutter Android source와 ADB 실행 확인을 기준으로 유지하는 단일 Design Prototype 프로젝트입니다.

- OpenDesign project id: `cafebridge-flutter-android`
- Working directory: `/home/sangmin/dev/workspaces/cafe-bridge-flutter/design/open-design/cafebridge-flutter-android`
- Linked product workspace: `/home/sangmin/dev/workspaces/cafe-bridge-flutter`
- Authority: current Flutter source and API contracts override artifacts when they differ.

## Existing artifacts
- `index.html` — canonical visual atlas: runtime basis, tokens, shell, main/detail/admin/dialog/state/coverage.
- `prototype/flows.html` — clickable login, role switch, five-tab navigation, guarded routes, dialogs, task feedback, installer permission branch.
- `screens/completion-frames.html` — Analytics/Workforce sub-tabs, complete form fields, payroll/password/update/session/installer-permission states.
- `screens/route-state-completion.html` — detail routes, error/task/admin/modal inventory.
- `docs/source-inventory.md`, `docs/interaction-map.md`, `docs/coverage-matrix.md` — source and runtime audit notes.

## Source contract
- Korean Material 3 light theme: teal `#0D9488`, dark teal `#0F766E`, ink `#0F172A`, background `#F8FAFC`.
- Role hierarchy: `viewer < operator < admin`.
- Five shell destinations: 홈, 분석, 업무, 인력, 더보기.
- Product price flow enters Product Lookup first; item detail opens the operator-gated Price Apply route.
- No actual Drawer/BottomSheet calls exist; classes named `Sheet` are full-screen routes.
- Android declares network/package-install capabilities. There is no standard runtime permission dialog, but APK installation can open the special “알 수 없는 앱 설치 허용” settings screen and return for retry.
- Android reference viewport is 412dp; ADB validation used a connected SM-G970N device with 1080×2280 physical pixels, a 720×1280 probe, and adjustResize keyboard behavior.

The same-purpose existing files were updated in place; no duplicate prototype entry files were created.
