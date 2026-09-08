# Cafe Bridge Flutter Refactoring Implementation Plan

## Scope and Invariants

This plan is based on the active `master` checkout, the current Flutter
implementation, and `docs/TOPOLOGY.md`. Android remains the only supported
target. API paths, payload contracts, role gates, cache exclusions, and visible
user workflows must remain compatible. The work intentionally avoids a blanket
Clean Architecture rewrite, repository/interface layers without a concrete
consumer, and one-widget-per-file fragmentation.

The audit covered 30,550 lines across `lib/` and `test/`: 21,269 presentation
lines, a 1,267-line `AppState`, 3,419-line Menu Workspace, 2,917-line Workforce
screen, 2,136-line Analytics screen, 1,931-line Settings screen, and 77 tests.
Shared primitives (`AccessGate`, `AppScreen`, `EmptyState`, `Panel`, `StatCard`,
`ResponsiveWrapGrid`, `AsyncRequestGuard`, `ApiClient`, and `TaskPoller`) are
sound foundations and will be retained.

## Findings and Priority

| Priority | Area | Finding | User or operational impact |
| --- | --- | --- | --- |
| P0 | Menu Workspace | `_WorkspaceInfoStrip` puts `Expanded` under `Wrap`. | A loaded menu-workspace path can throw a parent-data layout exception. |
| P0 | Cost calculator | Stateful calculator rows have no stable identity. | Removing a non-final row can display a different ingredient from the value submitted to the API. |
| P0 | Touchkey | The app-bar refresh returns an in-memory payload, drops the selected class, and can retain an invalid explorer grid selection. | Refresh is not a network refresh and can make the explorer dropdown invalid. |
| P0 | App shell | All five `IndexedStack` children mount on login. | Hidden Dashboard, Analytics, and Workforce tabs start network work before the user visits them. |
| P0 | Cache policy | Service-health configuration and Touchkey payloads are written to disk despite zero cache TTL. | Endpoint configuration and POS exploration data can persist when no caching is intended. |
| P1 | Service health | Refresh/check replaces edited settings; uncontrolled form fields can show values different from save payloads. Requests can race. | Admin can unknowingly save an old endpoint or interval. |
| P1 | Session state | Auth/cache transitions can mutate after an awaited cookie or cache persistence operation without revalidating the request context. | Logout, server change, and stale requests can race with persisted state. |
| P1 | Product identity | Product code, name, category, price parsing, and numeric-code normalization are duplicated in Product Lookup, Menu Workspace, and Price Apply. | Equivalent product actions can send differently formatted product codes. |
| P1 | Task state | `TaskPoller` normalizes status but `BrowserPriceApplyTask` does not. | Uppercase terminal statuses can leave a persisted active price task behind. |
| P1 | Workforce previews | Shift and pay-preview dialogs retain results after inputs change; the employee preview uses a disposed-prone `StatefulBuilder`. | A stale financial preview can be shown or a dialog can receive an async state update after closing. |
| P2 | Large screens | Menu Workspace, Workforce, Analytics, and Settings combine page shell, transport calls, local state, parsing, dialogs, and rendering. | Changes are difficult to test and review; overlapping loads are handled inconsistently. |
| P2 | Navigation and design system | Guarded navigation and raw `MaterialPageRoute` coexist; hundreds of direct color literals duplicate `AppColors`. | Inconsistent role-route behavior and visual token drift. |
| P2 | Test coverage | The suite is predominantly model/unit coverage, with no authenticated navigation, 360/412dp, semantics, or device integration coverage. | High-risk widget and lifecycle regressions are under-tested. |
| P2 | CI/release | `.gitlab-ci.yml` contradicts topology policy: a protected `master` push registers production, while `DRY_RUN=true` does not build a signed artifact. | A routine source push can publish production and intended dry-run evidence is unavailable. |

## Implementation Sequence

### Phase 1: Correctness, Lifecycle, and Performance

1. Replace the invalid `Wrap`/`Expanded` combination with a responsive Flex
   layout in Menu Workspace. Preserve existing text, trailing action, and
   compact behavior.
2. Give each temporary cost-calculator row an immutable key, invalidate a
   completed calculation on every input change, and only render a result that
   belongs to the current input revision.
3. Track the Touchkey selected class separately from its payload. Let explicit
   refresh bypass only the screen-local cache, retain that selection, and repair
   the active explorer table whenever refreshed table keys change.
4. Lazily create each root destination on first selection while preserving its
   state after it has been visited. This keeps the current `IndexedStack`
   navigation and back behavior without speculative startup requests.
5. Expand the central cache exclusion policy for the service-health and
   Touchkey endpoints, including pruning of any persisted legacy entries.
6. Normalize product identity in one pure model helper and use it in every
   product-code entry point, including Price Apply.
7. Normalize `BrowserPriceApplyTask.status` at model construction so task UI,
   active-task cleanup, and `TaskPoller` agree.

### Phase 2: Stateful Administrative Flows

1. Rebuild Service Health cards around controlled draft values keyed by target.
   A health check updates target health only; it cannot discard unsaved admin
   settings. Use request generation guards and disable conflicting operations.
2. Make every AppState mutation that follows cookie or cache persistence verify
   the captured request context. Serialize secure-cookie writes so a late
   response cannot recreate a logged-out persisted cookie.
3. Move the employee pay preview out of the closure-owned `StatefulBuilder`
   into its own stateful dialog with mounted/request-generation checks and a
   busy state. Invalidate all payroll and calculator previews when their inputs
   change.

### Phase 3: Boundaries and Duplication Reduction

1. Split Menu Workspace along its existing visible boundaries: product browser
   and detail/quick-price flow, workspace/history flow, and entry editing.
   Share only pure product and task helpers; do not introduce a generic
   workspace repository.
2. Split Workforce into its five existing tabs and form components. Keep the
   existing Provider/AppState API boundary initially; extract a feature gateway
   only when repeated transport and parsing calls can be shared without hiding
   the backend contract.
3. Split Analytics by its three visible sections and Settings by account/server,
   deploy/update monitor, and admin users/audit. Preserve public routes and role
   gates.
4. Remove only identical wrappers, then migrate high-touch screens from direct
   color literals to `AppColors`, `AppSpacing`, and `AppRadii`. Avoid a large,
   behaviorless component framework.
5. Route new guarded navigation through `AppNavigation`; migrate existing raw
   routes opportunistically when their feature files are changed.

### Phase 4: Verification and Release Safety

1. Add focused regression tests for the P0/P1 invariants above, including
   small Android-width layouts and lazy destination mounting.
2. Align GitLab workflow rules with `docs/TOPOLOGY.md`: protected pushes build
   signed artifacts without registration; explicit protected API/trigger or
   manual web promotion registers production; `DRY_RUN=true` builds a signed
   artifact without registration.
3. Run formatting, analyzer, all tests, and the Android debug build locally.
   Then use the managed shared ADB server only with an approved compatible QA
   device for a non-destructive smoke check.
4. Commit only intended paths. Do not push until the release-policy test and
   CI rule review prove that a normal protected push cannot register production.
   Signed release, production registration, and post-deploy verification remain
   CI/protected-runner actions under `docs/TOPOLOGY.md`.

## Acceptance Criteria

- No direct data persistence occurs for sensitive/no-cache endpoints.
- Async UI requests are latest-result-wins and never call state updates after
  disposal.
- User edits cannot be overwritten by a health check or submitted from a stale
  widget value.
- Product codes and task terminal statuses are normalized once at their model
  boundary.
- Root destinations create no network-driven state before the first visit.
- Existing UI strings, role gates, API payloads, and high-risk confirmation
  sequence remain unchanged.
- `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`,
  `flutter test`, Android debug build, CI-policy checks, and available smoke
  checks pass before promotion.
