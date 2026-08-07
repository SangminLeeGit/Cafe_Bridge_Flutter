# Android/Web Function Audit

기준 저장소:

- Backend: `/home/sangmin/cafe-bridge/cafe_bridge_collector/web/routers`
- Web: `/home/sangmin/cafe-bridge/frontend/lib/design-screens.ts` 및 `frontend/app`
- Android: 현재 저장소 `lib/`

## Mobile Coverage

| 영역 | Android 반영 | API 기준 | 비고 |
| --- | --- | --- | --- |
| 인증·세션 | 완료 | auth session/login/logout/change-password | secure storage, CSRF, keepalive, offline session |
| 홈·일 상세 | 완료 | dashboard, days/{date} | 새로고침, 캐시, 로딩·오류·빈 상태 |
| 매출 분석 | 완료 | monthly, compare, payments, items, abc, menu-engineering, hours, weekday, trends, forecast | 3단계 nested tab으로 재구성 |
| 상품 조회 | 완료 | products/registration | 검색, limit, refresh, 상세 |
| 가격 변경 | 완료 | browser-apply, task, history | preview 선행, 확인 dialog, task poll/resume |
| 동기화 | 완료 | sync, task, runs | 중복 방지, 진행·실패·재개 |
| 원가 | 완료 | costing dashboard/ingredients/recipes/calculate | 조회·계산 중심, 기준정보 저장은 웹 |
| 메뉴판 | 완료 | signage/menu GET/POST | 제한 편집, unknown field 보존, dirty 이탈 보호 |
| 메뉴 작업대 | 완료 | menu-workspace, apply/history endpoints | admin 전용 모바일 작업 흐름 |
| 터치키 | 조회 완료 | touchkey-tables | 원본 탐색·검색·분류·페이지, 실제 위치 반영은 웹 |
| 근무·급여 | 완료 | workforce dashboard/workplaces/calendar/shifts/presets/employees/payslips | viewer는 조회, operator만 변경 |
| 달력 일괄등록 | 완료 | shifts POST | 날짜별 순차 호출로 부분 성공·재시도 지원 |
| 관리자 모니터 | 조회 완료 | users/audit/deploy/daily-reports | 고위험 변경은 웹 전용 |
| APK 업데이트 | 완료 | app-update/check/download | HTTPS, size, SHA-256, build, signing 검증 |

## Intentional Web-Only Operations

- 사용자 생성·권한/활성 변경·비밀번호 초기화
- 배포 실행과 CI 작업 생성
- 일일보고서 정책 변경·연동 테스트·수동 실행·재생성·재전송
- 신규 상품 실제 등록/삭제 및 공식 CSV/XLSX import/export
- 터치키 위치 편집과 EasyPOS 실제 반영
- 원가 기준정보 저장 및 사이니지 카테고리 구조 변경

위 기능은 모바일에서 가짜 성공 상태를 만들지 않고 조회 또는 웹 이동 안내로 제한한다.

## Corrections In This Release

- Workforce의 workplace, shift, preset, employee 변경 액션을 operator 권한에서만 렌더링한다.
- 달력에서 빈 날짜를 포함해 다중 선택하고 실제 `POST /api/workforce/shifts`를 순차 호출한다. 실패한 날짜는 선택 상태를 유지한다.
- 주요 목록 응답에서 필수 배열이 누락되거나 항목 타입이 바뀌면 빈 화면으로 위장하지 않고 계약 오류를 표시한다.
- 웹 홈은 operator/admin에게만 operator 전용 원가 요약 API를 요청한다.
- signage API method metadata를 실제 `POST` 계약으로 정정한다.
- Android validation job에 Debug APK 및 Web compile을 추가하고, release signing 검증은 설치된 SDK build-tools를 안전하게 탐색한다.
