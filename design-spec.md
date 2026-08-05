# Cafe Bridge mobile design specification

## Traceability

- Repository: `cafe-bridge-flutter`
- Working branch: `design`
- Reference branch: `origin/main`
- Fetched reference: `8b446eee4ebd8815fbbaffe35066785329093b09`
- Server base URL declared by the client: `https://pos.cafe-bridge.org`
- Design source: `lib/main.dart`, `lib/screens/`, `lib/state/app_state.dart`, `lib/services/api.dart`, `lib/models/`, `docs/cafe-bridge-screen-map.md`

The artifact only documents screens and interactions present in the current Flutter client. Numerical values are intentionally represented by their response fields when the server response is not available; no sample business data is fabricated.

## Screen map

| Screen | Source | Entry / exit | Data and state |
| --- | --- | --- | --- |
| 로그인 | `lib/screens/login.dart` | AppRoot when unauthenticated → MainLayout after `/api/auth/login` | 아이디, 비밀번호, 로그인 상태 유지; submit/loading; 401/403/423/429/504/network errors; setup/offline/update banners |
| 홈 | `lib/screens/dashboard.dart` | MainLayout 첫 탭 → `/api/dashboard`; recent day → `DayDetailScreen` | `latestMetrics`, `weekThis`, `recentDays`, `topItems`, `paymentMix`, `recentRuns`, growth/decline items; cache/offline/error/empty |
| 인사이트 | `lib/screens/analytics.dart` | MainLayout 둘째 탭 | 개요: 월간·비교·트렌드 / 매출 흐름: 품목·시간대·요일·결제 / 메뉴 인사이트: 메뉴 작업대·예측·ABC |
| 업무 | `lib/screens/operations.dart` | MainLayout 셋째 탭 | 상품 조회, 원가, 가격 반영, 메뉴판, 동기화, 메뉴 작업대; viewer/operator/admin lock states |
| 인력 | `lib/screens/workforce_mobile.dart` | MainLayout 넷째 탭 | 대시보드·근무 캘린더·근무·급여·직원; forms, preview, save/delete and error states |
| 더보기 | `lib/screens/more.dart` | MainLayout 다섯째 탭 | 상품 조회, 터치키, 앱 설정, 메뉴 작업대, 배포 관리, 일일보고서; admin lock states |
| 상품 조회/상세 | `lib/screens/product_lookup.dart` | 업무/더보기 → search → detail; price change requires operator | `/api/products/registration`, `.../{code}`; search, limit, refresh, no result, retry, detail fields |
| 동기화 | `lib/screens/sync.dart` | 업무 → operator | `/api/sync/runs`, `/api/sync`, `/api/sync/{taskId}`; selected date, task poll, resumed task, timeout, failed/succeeded |
| 앱 설정 | `lib/screens/settings.dart` | 더보기 → viewer | server URL, connection check, app update, cache, password/session; admin sub-screens remain gated |

## API surface represented in the files

`/api/auth/session`, `/api/auth/login`, `/api/auth/logout`, `/api/auth/change-password`, `/healthz`, `/api/dashboard`, `/api/days/{date}`, `/api/monthly`, `/api/compare`, `/api/trends`, `/api/items`, `/api/hours`, `/api/weekday`, `/api/payments`, `/api/menu-engineering`, `/api/forecast`, `/api/abc`, `/api/products/registration`, `/api/costing/*`, `/api/price/browser-apply*`, `/api/signage/menu`, `/api/sync*`, `/api/menu-workspace*`, `/api/workforce/*`, `/api/menu-engineering/touchkey-tables`, `/api/admin/daily-reports/*`, `/api/auth/users`, `/api/auth/audit-logs`, `/api/deploy*`, `/api/app-update/*`.

## Files intentionally excluded

- `lib/screens/menu_workspace.dart.bak`: obsolete backup already removed by the latest `main` merge.
- Prototype-only screens, future flows, invented metrics, and static demo payloads: none added.
- No temporary export, test, or generated design files are included in this design deliverable.
