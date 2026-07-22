# Cafe Bridge Flutter 모바일 앱 — 기능 순차 구현 계획서

> 작성일: 2026-04-05  
> 기준: FastAPI 백엔드 (`cafe_bridge_collector/web/app.py`) 전체 엔드포인트 기준
> 환경: 주 접속 단말 = 모바일 (Android/iOS), Flutter 3.x / Provider

---

## 현재 구현 상태 (기준선)

| 화면 | 상태 | 매핑 엔드포인트 |
|------|------|----------------|
| 로그인 | ✅ 완료 | `/api/auth/login`, `/api/auth/session` |
| 대시보드 | ✅ 완료 | `/api/dashboard`, `/api/sidebar` |
| 분석 허브 (7탭) | ✅ 완료 | `/api/monthly`, `/api/items`, `/api/hours`, `/api/weekday`, `/api/payments`, `/api/compare`, `/api/trends` |
| 동기화 | ✅ 완료 | `/api/sync`, `/api/sync/runs`, `/api/sync/{taskId}` |
| 설정 | ✅ 완료 | `/api/auth/logout`, `/api/auth/change-password`, `/healthz` |

**미구현 백엔드 기능 그룹 (아래 구현 계획 대상):**

- 심화 분석 (메뉴엔지니어링 / 예측 / ABC)  
- 원가 관리 (Costing)  
- 메뉴 워크스페이스 (Menu Workspace)  
- 인력·근태 관리 (Workforce)  
- 상품 등록 조회 (Product Registration)  
- 관리자 기능 (사용자 관리 / 감사 로그)

---

## 구현 원칙

1. **모바일 UX 우선** — 긴 폼 대신 카드/모달/바텀시트 활용; 테이블형 데이터는 수평 스크롤
2. **역할 접근제어 유지** — `AppState.canAccess()` / `UserRole` 체계 그대로 적용
3. **기존 패턴 재사용** — `fetchMapParsed` / `CacheNotice` / `EmptyState` / `Panel` / `StatCard`
4. **단계별 독립성** — 각 Phase는 이전 Phase에 코드 의존성 없이 병렬 착수 가능한 단위로 분리
5. **캐시 보안** — 민감 데이터(원가, 급여)는 `SharedPreferences` 디스크 캐시 비활성화

---

## Phase 1 — 심화 분석 탭 확장 (분석 허브 내 추가 탭)

> **우선순위: 최고** — 기존 `AnalyticsScreen` 탭바 확장이므로 신규 화면 불필요. 순수 UI 추가.

### 추가 탭 3개

| 탭 이름 | 엔드포인트 | 역할 |
|---------|-----------|------|
| 메뉴 엔지니어링 | `GET /api/menu-engineering?from=&to=` | viewer |
| 수요 예측 | `GET /api/forecast?from=&to=` | viewer |
| ABC 분석 | `GET /api/abc?from=&to=` | viewer |

### 작업 목록

1. `lib/models/analytics_models.dart` — `MenuEngineeringData`, `ForecastData`, `AbcData` 모델 추가
2. `lib/screens/analytics.dart` — `DefaultTabController.length` 7 → 10, 탭 3개 추가
3. 각 탭 위젯:
   - **메뉴 엔지니어링**: 4분면 구분 리스트 (Star/Puzzle/Plowhorse/Dog) + 요약 카운트 카드
   - **수요 예측**: 품목별 예측 매출액 리스트, 트렌드 배지
   - **ABC 분석**: A/B/C 등급별 아코디언 리스트 + 파레토 요약 카드

### 예상 공수: 3~4일

---

## Phase 2 — 원가 관리 화면 (신규 하단 네비게이션 탭)

> **우선순위: 높음** — 점주 의사결정에 직결되는 핵심 기능. viewer 이상 접근 가능.

### 신규 네비게이션 항목

```
아이콘: Icons.calculate_outlined / Icons.calculate
라벨: 원가
title: 원가 관리
minimumRole: viewer
```

### 하위 화면 구조 (탭 또는 드릴다운)

```
원가 관리 (CostingScreen)
├── 대시보드 탭       GET /api/costing/dashboard?limit=
├── 재료 관리 탭      GET/POST/PATCH /api/costing/ingredients
│   └── 재료 상세     GET /api/costing/ingredients/{id}/prices
│                     POST /api/costing/ingredients/{id}/prices
└── 레시피 탭         GET/POST/PATCH/DELETE /api/costing/recipes
    └── 레시피 계산   POST /api/costing/calculate
```

### 작업 목록

1. `lib/models/costing_models.dart` — `CostingDashboard`, `Ingredient`, `IngredientPrice`, `Recipe`, `RecipeCalculateResult` 모델
2. `lib/screens/costing.dart` — 3탭 `DefaultTabController`
3. 재료 탭: 리스트 + 우측 상단 FAB로 신규 추가 (모달 바텀시트), 스와이프로 편집
4. 레시피 탭: 카드형 리스트, "계산하기" 버튼 → 결과 모달
5. `main.dart` — `_buildNavigationItems`에 `CostingScreen` 항목 추가
6. **보안**: 레시피 원가 데이터는 캐시 저장 제외 (`cacheKey: null`)

### 예상 공수: 5~7일

---

## Phase 3 — 메뉴 워크스페이스 화면 (신규 하단 네비게이션 탭)

> **우선순위: 높음** — 상품 정보 관리 및 가격 변경의 핵심. admin 기능 포함.

### 신규 네비게이션 항목

```
아이콘: Icons.menu_book_outlined / Icons.menu_book
라벨: 메뉴
title: 메뉴 워크스페이스
minimumRole: viewer (조회), operator (가격변경), admin (신규등록)
```

### 하위 화면 구조

```
메뉴 워크스페이스 (MenuWorkspaceScreen)
├── 메뉴 목록         GET /api/menu-workspace
│   ├── 검색/필터
│   ├── 항목 상세
│   │   └── 편집     PATCH /api/menu-workspace/entries/{entry_id}      [operator]
│   ├── 상태 일괄변경  POST /api/menu-workspace/bulk-status             [operator]
│   └── 신규 항목     POST /api/menu-workspace/new-item                 [admin]
├── 가격 변경         POST /api/menu-workspace/price-change             [operator]
│   └── 적용 실행     POST /api/menu-workspace/price-apply             [operator]
│   └── 실행 이력     GET /api/menu-workspace/price-apply-runs
├── 상품 등록 조회    GET /api/products/registration                    [viewer]
│   └── 상품 상세     GET /api/products/registration/{code}
└── 매장 프로필       GET/PATCH /api/menu-workspace/store-profile        [admin]
```

### 작업 목록

1. `lib/models/menu_workspace_models.dart` — `MenuEntry`, `StoreProfile`, `PriceApplyRun`, `ProductRegistrationRow` 모델
2. `lib/screens/menu_workspace.dart` — 탭 기반 메인 화면
3. 메뉴 목록: `ListView.separated` + 검색바 + 카테고리 필터 칩
4. 상품등록 탭: 검색으로 조회, 간략 카드 표시
5. 가격 변경: 변경 대상 리스트 확인 → 실행 확인 다이얼로그 → 진행 상태 폴링
6. **역할 게이팅**: 편집/삭제/신규 버튼은 `appState.canAccess()` 조건부 렌더링

### 예상 공수: 7~10일

---

## Phase 4 — 인력·근태 관리 화면 (신규 하단 네비게이션 탭)

> **우선순위: 중간** — 구조가 가장 복잡함. 모바일 UX 설계에 공을 들여야 함.

### 신규 네비게이션 항목

```
아이콘: Icons.people_outline / Icons.people
라벨: 인력
title: 인력 관리
minimumRole: operator
```

### 하위 화면 구조

```
인력 관리 (WorkforceScreen)
├── 근무 캘린더       GET /api/workforce/calendar?year=&month=
│   └── 날짜 탭      POST /api/workforce/shifts (시프트 등록)
├── 직원 목록         GET /api/workforce/employees
│   ├── 직원 추가     POST /api/workforce/employees
│   ├── 직원 수정     PATCH /api/workforce/employees/{id}
│   └── 급여 미리보기  POST /api/workforce/employees/{id}/pay-preview
├── 근무지 관리        GET/POST/PATCH/DELETE /api/workforce/workplaces
├── 시프트 프리셋      GET/POST/PATCH/DELETE /api/workforce/presets
├── 급여 명세         GET /api/workforce/payslips?year=&month=
│   └── 급여 계산     POST /api/workforce/payslips/calculate
└── 대시보드 요약     GET /api/workforce/dashboard
```

### 작업 목록

1. `lib/models/workforce_models.dart` — `Employee`, `Shift`, `Workplace`, `ShiftPreset`, `Payslip`, `WorkforceDashboard` 모델
2. `lib/screens/workforce.dart` — BottomNavigationBar 내부 탭 또는 Drawer 방식
3. 캘린더: `table_calendar` 패키지 도입 또는 커스텀 월간 그리드
4. 급여 계산: 기간 선택 → 미리보기 시트 → 확정 저장
5. **보안**: 급여 관련 모든 응답은 인메모리만 유지, SharedPreferences 캐시 금지
6. `pubspec.yaml` — `table_calendar` 패키지 추가

### 예상 공수: 10~14일

---

## Phase 5 — 관리자 기능 (설정 화면 확장)

> **우선순위: 낮음** — admin 전용. 기존 SettingsScreen에 섹션 추가.

### 추가 섹션 (SettingsScreen 내 조건부 렌더)

| 섹션 | 엔드포인트 | 역할 |
|------|-----------|------|
| 사용자 목록 및 역할 편집 | `GET /api/auth/users`, `POST`, `PATCH` | admin |
| 감사 로그 | `GET /api/auth/audit-logs` | admin |

### 작업 목록

1. `lib/screens/settings.dart` — `appState.isAdmin` 조건부 "관리자" 섹션 삽입
2. 사용자 관리: 리스트 + 역할 드롭다운 인라인 편집 + 비밀번호 초기화
3. 감사 로그: 타임스탬프·액션·사용자 컬럼의 스크롤 리스트 (페이지네이션)

### 예상 공수: 3~4일

---

## 전체 로드맵 요약

```
Phase 1  심화 분석 탭 확장        ████░░░░░░░░   3~4일    viewer
Phase 2  원가 관리 화면            ████████░░░░   5~7일    viewer+
Phase 3  메뉴 워크스페이스          ████████████   7~10일   viewer / operator / admin
Phase 4  인력·근태 관리             ████████████   10~14일  operator+
Phase 5  관리자 설정 확장           ████░░░░░░░░   3~4일    admin
```

**총 예상 공수: 28~39일 (1인 기준)**

---

## 공통 사전 작업 (Phase 1 착수 전 완료 권장)

| 항목 | 내용 |
|------|------|
| Sync 상태값 정합 | Flutter sync UI의 `done/error` → 백엔드 `succeeded/failed` 로 수정 (현재 불일치) |
| 캐시 보안 분리 | 민감 API 응답을 캐시에서 제외하는 `noCacheRoutes` 목록 `api.dart`에 추가 |
| 역할 enum 추가 | `UserRole.isAdmin` getter를 `app_state.dart`에 추가 (Phase 3, 5 필요) |
| 네비게이션 오버플로우 | 하단 탭이 5개 초과 시 NavigationDrawer 또는 NavigationRail로 전환 설계 필요 |
