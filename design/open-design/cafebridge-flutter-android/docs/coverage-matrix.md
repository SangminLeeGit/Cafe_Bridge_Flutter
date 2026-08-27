# Source-to-design coverage matrix (2026-08-23)

| Flutter source | Existing artifact | Covered contract |
|---|---|---|
| `main.dart`, `login.dart`, `app_navigation.dart`, `access_gate.dart` | `index.html`, `prototype/flows.html`, dialogs | init, session restore, login, IME, validation/error/setup block, role gate, five-tab shell |
| `android/MainActivity.kt`, `app_update_service_io.dart` | `index.html`, `prototype/flows.html`, `completion-frames.html` | download progress/cancel, installer opened, unknown-app-sources settings, return/retry/failure |
| `dashboard.dart`, `day_detail.dart` | `index.html`, `route-state-completion.html` | expanded sections, recent days, detail route, loading/network/DB/empty/error/cache |
| `analytics.dart` | `index.html`, `completion-frames.html`, `route-state-completion.html` | 3 groups / 10 views, month/range picker, loading/empty/error/cache |
| `operations.dart`, `product_lookup.dart` | `index.html`, `prototype/flows.html`, `route-state-completion.html` | 6 entries, product lookup entry for price flow, viewer/operator/admin locks, search/detail/missing-code/retry |
| `costing.dart` | `index.html`, `route-state-completion.html` | dashboard, ingredient detail/history, recipe detail, calculator validation/result/empty/error |
| `price_apply.dart` | `index.html`, `prototype/flows.html`, `route-state-completion.html` | preview signature, confirmation, task pending/running/result/failure/timeout/history |
| `signage.dart` | `index.html`, `prototype/flows.html`, `route-state-completion.html` | dirty draft, full-screen item edit fields, invalid price, discard/apply confirmation, applying/result |
| `sync.dart`, `touchkey.dart` | same | target date, task restore/polling/partial/timeout, POS map/explorer/partial source |
| `workforce_mobile.dart`, `workforce_shift_forms.dart` | `index.html`, `completion-frames.html`, `route-state-completion.html` | 5 tabs, calendar, filters, CRUD forms, extra pay/deduction, leave/holiday, memo, payroll preview |
| `menu_workspace.dart` | `index.html`, `route-state-completion.html` | menu/task tabs, validation/history metrics, filters, registration detail, status update route, quick-price route, unused new-menu note |
| `more.dart`, `settings.dart`, `service_health.dart` | `index.html`, `prototype/flows.html`, route state | More origin for Touchkey, viewer-gated settings, health target checks/settings, deploy notice/panel/metrics/history, user/audit read-only routes, password/session transition |
| `daily_report_monitor.dart` | `index.html`, `route-state-completion.html` | run/audit tabs, selected detail, active polling, error/empty/read-only |
| Shared widgets/theme | `index.html` components/states | tokens, AppScreen, panels, cards, input/buttons, Loading/Empty/Network/Permission, SafeArea notes |

## Intentional non-coverage
- No new product route, Drawer, BottomSheet, mobile account mutation, deployment execution, policy editing, or normal new-menu entry was invented.
- `_NewMenuAddScreen` remains conditional/code-only because `_openNewItemScreen()` is unused.
- Native system installer settings are represented as a permission state; the prototype does not fake an Android settings screen as an in-app route.
- Account and audit search inputs are intentionally absent because the Flutter screens expose refresh/read-only lists, not search controls.
