# CafeBridge Backend–Flutter Parity Report (2026-11-03)

## Scope and evidence

- Backend source of truth: `/home/sangmin/dev/workspaces/cafe-bridge-dev`
  (`cafe_bridge_collector/web/routers/*.py`, `web/services/*.py`, `frontend/app/*`).
- Android client: `/home/sangmin/dev/workspaces/cafe-bridge-flutter` (`lib/`, `test/`).
- Comparison covered every backend router in scope: analytics, sync, service health,
  admin deploy/app-update, costing, browser price apply, menu workspace, editor,
  signage, touchkey, workforce, auth/users, daily reports, and runtime settings.
- Intentional web-only boundaries were preserved: user CRUD, runtime settings
  apply/rollback, daily-report settings/tests/regeneration, and high-risk menu
  registration/deletion execution remain web/admin operations.

## Implemented parity fixes

### Previously uncommitted work included in this release

| Area | Backend contract | Flutter implementation |
| --- | --- | --- |
| Owner briefing / dashboard | `/api/daily-report` structured `owner_report` (`daily_reports.py`) | `lib/screens/dashboard.dart`, `lib/models/dashboard_model.dart` |
| Costing revisions and price history | `costing.py` ingredient/recipe CRUD with revisions, effective prices, calculate | `lib/screens/costing.dart`, `lib/models/costing_models.dart` |
| Costing capability gate | `/api/editor/context` `apply_price` decision | `lib/models/editor_context.dart`, `lib/screens/price_apply.dart` |
| Editor product catalog | `/api/editor/products` cursor/generation/query-key contract | `lib/screens/editor_product_catalog.dart`, `lib/models/editor_product_catalog.dart` |
| Signage drafts and write receipts | `/api/editor/signage/draft`, `/api/editor/write-receipts/{id}` | `lib/screens/signage.dart` |
| Touchkey layout editor | `/api/editor/touchkey/layouts/{id}` optimistic revision contract | `lib/screens/touchkey_layout_editor.dart`, `lib/models/touchkey_layout.dart` |
| Daily report monitor | read-only runs/settings/audits endpoints | `lib/screens/daily_report_monitor.dart` |

### New in this change set

| Area | Backend evidence | Flutter change |
| --- | --- | --- |
| Payroll runs | `workforce.py:400-497`, `workforce_settlement.py` (`draft→reviewed→confirmed`, issues, ack, explain) | New `lib/screens/payroll_runs.dart`, `lib/models/payroll_models.dart`; list/create/detail/review/confirm/explain in the 급여 tab |
| Shift confirmation | `workforce.py:389-398`, `confirm_shifts` | `ShiftRecord.confirmedAt`; period and per-shift confirm/unconfirm in `lib/screens/workforce_mobile.dart`; confirmed count |
| Workplace pay/tax rules | `workforce_repository.py:221-333` | Full `pay_rule`/`tax_rule` editor in the workplace dialog |
| Employee monthly salary | `workforce.py:181-198`, `workforce_validation.py` | Monthly salary + `prorated_hours`/`fixed_period` mode in the employee form |
| Bulk shift creation | `workforce.py:339-347`, `bulk_create_shifts` | Single `/api/workforce/shifts/bulk` call with `skip_existing`, created/skipped reporting |
| Signage publication | `editor.py:262-360`, `signage_editor_store.py:122-280` | Publish capability gate, confirmation, publication status state machine, lookup/reconcile for ambiguous outcomes |
| Admin runtime status | `/api/admin/runtime-status`, `runtime_status.py` | Read-only runtime/deployment drift monitor in `lib/screens/settings.dart` |
| Admin APK CI jobs | `/api/ci/flutter-apk/jobs[/{id}]`, `flutter_apk_ci.py` | Read-only job list/detail monitor |
| Compare periods | `/api/compare` (`a_*`, `b_*`) | Independent A/B range pickers, auto previous-range reset |
| Sync warnings/freshness | `/api/sync/runs` (`warnings`, `today`, `error`) | Warning details, business-date context, failed-load vs empty distinction |
| Product lookup counts | `product_registration_store.py:234-293` | Total/filtered/displayed counts, snapshot completeness, generation, freshness, truncation action |
| List truncation disclosure | analytics/day-detail response sizes | Explicit “상위 N개 / 전체 N개” subtitles |
| Menu workspace draft deletion | `DELETE /api/menu-workspace/entries/{id}` | Draft delete action in entry detail |
| Password handling | `auth/store.py` validates exact password string | Removed client-side trimming; added 503 login message |

## Verification

See the final session report for command results and release evidence.
