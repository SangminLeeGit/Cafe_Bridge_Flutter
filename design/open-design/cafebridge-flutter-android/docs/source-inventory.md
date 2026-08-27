# CafeBridge Flutter Android · source inventory (2026-08-23)

## Runtime basis
- Android-only Flutter app, Korean `Material 3` light theme.
- ADB observed device: Samsung SM-G970N, 1080×2280 physical, 480dpi; app content bounds 2020px.
- `windowSoftInputMode=adjustResize`; login keyboard state scrolls the focused field into view.
- Manifest review: INTERNET and REQUEST_INSTALL_PACKAGES are declared; no standard runtime permission dialog exists. Native APK installation can open `ACTION_MANAGE_UNKNOWN_APP_SOURCES` for Cafe Bridge, then return for retry.
- Launch observation: AppRoot loading/session restore → LoginScreen when unauthenticated. Login showed the Cafe Bridge cup mark, update banner, credentials, remember-me, validation message, and Android IME.

## Shell
- AppRoot: initializing/session restore → LoginScreen → MainLayout.
- MainLayout IndexedStack: `홈`, `인사이트/분석`, `업무`, `인력`, `더보기`.
- Shared: AppBar logo/title/English role pill, offline banner, recommended update banner, SafeArea, NavigationBar, AccessGate.

## Main and detail screens
- Dashboard + Day Detail.
- Analytics: `개요(월간/비교/트렌드)`, `매출 흐름(품목/시간대/요일/결제)`, `메뉴 인사이트(메뉴 작업대/예측/ABC)`.
- Operations: 상품 조회/상세, 원가/재료/레시피/임시 계산, 가격 반영, 메뉴판, 동기화, 메뉴 작업대.
- More-routed Touchkey: `POS 맵`, `데이터 탐색기`.
- Workforce: 대시보드/캘린더/근무/급여/직원.
- More: 앱 설정, 외부 서버 상태, 배포 관리, 계정 관리, 감사 로그, 일일보고서.

## States and interaction inventory
- Loading, empty, network error, generic error, retry, DB unavailable, offline/cache, permission/read-only, expanded/collapsed.
- Price/signage/sync/task: preview, confirmation, dirty/saved/applying, pending/running/succeeded/failed/partial_failed/timeout, active-task restore and retry.
- Update/install: download progress, cancel, installer opened, unknown-app-sources permission required, return/retry, failure.
- Forms/dialogs: workplace add/edit/delete, calendar bulk shift, shift/preset add/edit/delete, employee add/edit/detail/delete/disable, payroll preview, password change, price/signage confirmation, logout, date/month/range pickers, PopupMenu, SnackBar.
- No actual Drawer/endDrawer or `showModalBottomSheet`/`showBottomSheet` call exists. Classes named `Sheet` are full-screen routes.

## Role contract
- `viewer < operator < admin`; unknown grants nothing.
- Viewer: dashboard/analytics/day detail/product/touchkey/settings and read-only Workforce.
- Operator: costing/signage/sync/price and Workforce writes.
- Admin: menu workspace, deployment monitor, user list, audit log, daily report monitor.

## Prototype artifact map
- `index.html`: canonical visual atlas, tokens, shell, main/detail/settings/dialog/state/coverage.
- `prototype/flows.html`: clickable login, role switch, five tabs, detail routes, dialogs, installer permission branch, task feedback.
- `screens/completion-frames.html`: Analytics sub-tabs, Workforce sub-tabs/forms/payroll/password/update/session/installer-permission states.
- `screens/route-state-completion.html`: detailed route/error/task/admin/modal inventory.
