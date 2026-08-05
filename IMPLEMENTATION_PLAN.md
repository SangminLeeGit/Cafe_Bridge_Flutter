# Cafe Bridge Android 백엔드 정합화 구현 현황

기준일: 2026-07-24

백엔드 `/home/sangmin/cafe-bridge`의 현재 FastAPI 계약을 읽기 전용으로 조사하고 Android 권장 범위를 구현했습니다.

## 완료 페이즈

| 페이즈 | 상태 | 결과 |
| --- | --- | --- |
| 계약·역할 기준선 | 완료 | unknown role fail-closed, route `AccessGate`, 5탭 내비게이션 |
| 캐시·데이터 보안 | 완료 | 민감 endpoint 저장 차단, transport 오류만 stale fallback, pruning |
| 인증·세션·API | 완료 | remember 정책, keepalive 역할 갱신, 204·timeout·ClientException 지원 |
| 비동기 작업 | 완료 | 공통 순차 poller, terminal status, 취소, active task 복원 |
| 분석 | 완료 | 결제수단 전체, forecast 일별 예측, KST, 날짜 검증, 고단가 표현 |
| Workforce | 완료 | 시프트·프리셋 CRUD, 급여 계산·미리보기, 안전한 employee PATCH |
| 상품·가격 | 완료 | viewer 공개 조회 API, preview 필수 가격 적용, admin workspace 분리 |
| 원가 | 완료 | 조회와 저장 없는 레시피 계산, admin 기준정보 변경 제외 |
| 사이니지·터치키 | 완료 | unknown field 보존, 제한 편집, dirty 이탈 보호, viewer 터치키 조회 |
| 관리자 | 완료 | 사용자·감사·배포·일일보고서 읽기 전용 모니터 |
| APK 업데이트 | 완료 | 취소, metadata 재조회, unknown-source 권한, native APK 검증 |
| UX·접근성 | 완료 | 한국어 locale, KST, 반응형 액션, 터치 영역, 기본 요약 펼침 |
| 테스트·문서 | 완료 | API·캐시·권한·업데이트·Workforce·분석·모니터 테스트 및 문서화 |

## 웹 유지 범위

- 사용자 생성, 권한·활성 변경, 비밀번호 초기화
- 배포 및 CI 실행
- 일일보고서 설정, 연동 테스트, 수동 실행, 재생성·재전송
- 신규상품 실제 등록·삭제와 공식 CSV/XLSX import/export
- 터치키 위치 편집과 EasyPOS 실제 반영
- 원가 재료·레시피 기준정보 저장
- 사이니지 카테고리·레이아웃 구조 변경

## 백엔드 제약 대응

| 제약 | Android 대응 |
| --- | --- |
| Employee PATCH가 unset 필드를 `null`로 변환 | 최신 상세 기반 전체 payload 전송 |
| bulk shift 중복 조건에 employee ID 누락 | bulk 미사용, 단건 생성 |
| `tax_rule.apply_unit` 미반영 | 모바일 설정에서 제외 |
| linked employee self-service API 없음 | 개인 직원 계정 기능으로 노출하지 않음 |
| async task 응답 형식·상태 불일치 | 공통 adapter와 terminal status 집합 사용 |
| 앱 강제 업데이트 필드 미제공 | 권장 업데이트로 처리하고 로컬 build 재검증 |

세부 완료 내역과 검증 결과는 `ANDROID_BACKEND_ALIGNMENT_COMPLETION_REPORT_2026-07-24.md`에 기록했습니다.

## design 브랜치 Android UI 통합 계획

기준일: 2026-08-05

### 1. 비교 기준과 발견사항

- 현재 작업 브랜치 기준 커밋은 `main`의 `4a1960a`이며, 로컬에는 없던 `design` 브랜치를 `origin/design`의 `a745913`으로 읽기 전용 fetch했습니다.
- 디자인 브랜치는 `docs/cafe-bridge-screen-map.md`, 공통 테마, 공통 전체 화면 shell, `main.dart`, 분석·업무·더보기 허브와 공통 위젯을 변경합니다.
- `design`과 기준 커밋 사이에는 12개 파일, 830줄 추가와 251줄 삭제가 있으며 API 서비스, 응답 모델, 권한 모델, 작업 poller는 변경하지 않습니다.
- 현재 작업 트리는 이미 인증·캐시·비동기 작업·상품 조회·가격 반영·일일보고서 기능을 추가한 미커밋 상태입니다. 이 변경을 덮어쓰거나 브랜치 병합으로 대체하지 않습니다.

### 2. 선별 적용 결정

| 디자인 의도 | Android/현재 계약에 맞춘 적용 |
| --- | --- |
| 5개 핵심 영역과 계층형 분석 | 기존 `IndexedStack`과 5개 하단 탭을 보존하고 제목을 `인사이트`·`업무`로 정리합니다. 분석 10개 기능은 개요·매출 흐름·메뉴 인사이트 3개 상위 탭과 내부 탭으로 재구성하며 endpoint와 모델은 유지합니다. |
| 업무 허브에서 조회·실행 분리 | 상품 조회는 `viewer`, 원가·가격 반영·메뉴판·동기화는 `operator`, 메뉴 작업대는 `admin` 정책을 유지합니다. 권한 없는 항목도 잠금 카드와 필요한 역할을 보여주되 라우팅과 API 호출은 차단합니다. |
| 더보기의 도구/관리 구조 | 터치키와 설정은 `viewer`, 일일보고서·메뉴 작업대·배포 관리는 `admin`으로 유지하고 운영 도구·계정 설정·관리자 운영 섹션으로 재배치합니다. 기존 guarded route와 Android 뒤로 가기 동작을 보존합니다. |
| 전역 토큰과 화면 shell | 기존 코드가 사용하는 `AppColors` 이름을 유지한 채 디자인의 색상·간격·반지름·상태 토큰을 확장합니다. `AppScreen`을 push된 운영 화면에 적용하고 Material 3 버튼·입력·탭·카드·SnackBar 규칙을 전역화합니다. |
| 상태 표현 | 초기화에는 공통 `LoadingState`를 사용하고, 기존 `EmptyState`의 재시도·빈 데이터 흐름을 보존하면서 아이콘·오류 강조를 확장합니다. 캐시·업데이트·패널·통계 카드도 토큰을 사용합니다. |
| 웹 전용 요소 배제 | 마우스 hover, 데스크톱 전용 sidebar/table 레이아웃은 복제하지 않습니다. Android safe area, 44dp 이상 터치 영역, 스크롤 가능한 계층형 탭, 반응형 카드 grid, 시스템 뒤로 가기를 사용합니다. |

### 3. 구현 순서

1. `lib/theme/app_theme.dart`에 디자인 토큰과 Material 3 상태·텍스트 스타일을 현재 컨벤션으로 통합합니다.
2. `lib/widgets/app_screen.dart`를 추가하고 전체 화면 shell 및 권한/네트워크/로딩 상태 컴포넌트를 공통화합니다.
3. `main.dart`, `operations.dart`, `more.dart`를 허브·잠금 상태·safe area·뒤로 가기 기준으로 조정합니다.
4. `analytics.dart`의 10개 분석 기능을 3개 상위 탭의 중첩 탭으로 재구성하고 각 기존 로딩·빈 상태·오류·재시도를 그대로 연결합니다.
5. `panel.dart`, `stat_card.dart`, `empty_state.dart`, `cache_notice.dart`, `app_update_banner.dart`의 하드코딩 색상과 조작 영역을 공통 토큰으로 교체합니다.
6. `docs/cafe-bridge-screen-map.md`에 실제 적용된 화면 맵과 권한·상태·백엔드 보존 범위를 기록합니다.
7. 위젯/기존 테스트를 보강해 탭 구조, 권한 잠금, shell 뒤로 가기와 공통 상태 표시를 검증합니다.

### 4. API 및 회귀 보호 기준

- API path, query/body key, JSON parser, 응답 모델, 캐시 정책은 변경하지 않습니다.
- `AccessGate`와 `AppNavigation.pushGuarded`를 통해 UI 잠금과 서버 권한 검증을 이중으로 유지합니다.
- 가격 변경·동기화·메뉴판의 진행 중/실패/재시도 상태와 active task 복원을 유지합니다.
- 테스트는 기존 기능의 login, dashboard, analytics model, cache, task poller, workforce, signage, sync 흐름을 함께 실행합니다.

### 5. 완료 검증 기준

- `flutter analyze`, `flutter test`, Debug APK build, signing 환경이 없을 때도 가능한 Release APK compile을 실행합니다.
- Android SDK/에뮬레이터 연결 여부를 확인하되 연결 장치가 없으면 실기기 검증을 가장하지 않고 정적·빌드·테스트 결과만 기록합니다.
- 변경 diff에서 미사용 import/리소스, debug 출력, 임시 파일, 중복 shell을 확인하고 기존 사용자 변경은 되돌리지 않습니다.
- 검증 완료 후 의도한 파일만 stage하여 명확한 커밋 메시지로 현재 원격 추적 브랜치에 push합니다.
