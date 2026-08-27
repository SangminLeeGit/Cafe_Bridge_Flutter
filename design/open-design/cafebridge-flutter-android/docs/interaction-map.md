# CafeBridge Flutter Android · interaction map (2026-08-23)

- AppRoot loading/session restore → LoginScreen.
- Login: credentials + remember-me; empty validation; setup-block notice; HTTP/transport error copy; success → five-tab MainLayout.
- Main shell: bottom NavigationBar → 홈 / 분석 / 업무 / 인력 / 더보기. Offline and recommended-update banners are global shell states.
- Update banner → download progress/cancel → native installer; if package-install permission is missing, open Cafe Bridge’s unknown-app-sources settings → return → retry.
- 홈 / 분석 date row → Day Detail; previous/next business day controls.
- 업무 → 상품 조회 → 상품 상세 → operator-gated 가격 변경 confirmation.
- 업무 → operator-gated 원가 → dashboard → ingredient detail/recipe detail/calculator.
- 업무 → operator-gated 메뉴판 → full-screen item edit → dirty back discard dialog or save → apply confirmation.
- 업무 → operator-gated 동기화; target date → task polling → pending/running/result/history.
- 업무 → admin-gated 메뉴 작업대 → 메뉴 선택/작업 목록 → validation/history → registration detail/status update/quick-price routes.
- More → Touchkey, Settings, and admin-gated deployment/user/audit/daily-report routes.
- Settings → Service Health; viewer sees read-only controls, admin can save health settings; password success ends the session.
- Workforce tabs → calendar/shifts/payroll/employees; operator dialogs and payroll preview; viewer remains read-only.
- Settings logout or password-success session transition → LoginScreen.
- Permission gate → role explanation → back.

## Modal truth
There are no actual Drawer or BottomSheet interactions in source. Workforce forms, confirmations, date pickers, PopupMenu actions, SnackBar, and the native unknown-app-sources settings handoff are the modal/feedback surfaces represented by the prototype.
