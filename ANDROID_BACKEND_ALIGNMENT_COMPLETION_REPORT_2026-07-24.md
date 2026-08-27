# Cafe Bridge Android 백엔드 정합화 완료보고서

> **Historical validation record:** 아래 원격 ADB 및 당시 서명 환경 제한은 2026-07-24 실행 결과일 뿐 현재 topology가 아닙니다. 현재 WSL2 shared-ADB, Android-only, CI-only signed release 정책은 `docs/TOPOLOGY.md`가 우선합니다.

작성일: 2026-07-24

## 작업 원칙

- 백엔드 저장소 `/home/sangmin/cafe-bridge`는 전 과정 읽기 전용으로 유지했습니다.
- Flutter/Android 저장소의 기존 미커밋 변경을 보존했습니다.
- 모바일 권장 범위를 적용하고 고위험 관리 기능은 웹에 유지했습니다.
- 운영 자격증명, 서명 비밀, `.env` 값은 읽거나 기록하지 않았습니다.

## 구현 결과

### 데이터·인증

- 급여, 직원, 원가, 사용자, 감사, 배포, 일일보고서, 메뉴 작업, 사이니지 응답의 디스크 캐시를 차단했습니다.
- parser 성공 후에만 캐시를 기록하고 최대 100개·7일 기준으로 정리합니다.
- stale cache는 timeout, DNS, socket 등 transport 오류에서만 사용합니다.
- 401/403과 HTTP 서버 오류는 캐시로 가리지 않습니다.
- 로그인 유지가 꺼져 있으면 세션 쿠키를 secure storage에 저장하지 않습니다.
- keepalive에서 세션 만료나 역할 변경이 발생하면 UI가 즉시 갱신됩니다.
- 앱 UI를 먼저 시작하고 업데이트 확인은 비동기로, 세션 복원은 로딩 화면에서 수행합니다.

### 권한·화면

- 하단 내비게이션을 홈, 분석, 운영, 인력, 더보기 5개로 정리했습니다.
- viewer에게 Workforce, 상품 조회, 터치키 조회를 제공합니다.
- operator에게 원가, 가격 변경, 사이니지, 동기화를 제공합니다.
- admin 메뉴 작업대와 관리자 모니터는 `AccessGate`로 보호합니다.
- 상품 조회는 viewer endpoint `/api/products/registration`을 사용합니다.
- 사용자와 배포 기능은 읽기 전용으로 전환했습니다.

### 분석·운영

- 외상, 교환권, 직원카드, 전자화폐를 포함한 전체 결제수단을 반영했습니다.
- forecast는 `forecast_days[].predicted_total`을 사용합니다.
- 메뉴 엔지니어링의 부정확한 수익성 표현을 평균 판매가·고단가로 수정했습니다.
- 시간대 영수건수, 역순 날짜 검증, 쉼표 숫자 파싱, KST 영업일을 반영했습니다.
- 원가 화면에 저장 없는 임시 레시피 계산을 추가했습니다.
- 동기화는 overdue·partial_failed·HTTP 200 error payload를 표시합니다.

### 가격·EasyPOS 작업

- 실제 가격 반영 전에 `execute=false` 미리보기를 반드시 수행합니다.
- 미리보기 후 입력값이 변경되면 실제 반영 버튼이 다시 잠깁니다.
- 실제 반영 전에 상품과 목표 가격을 다시 확인합니다.
- sync와 가격 작업 ID를 사용자·서버 scope로 저장해 화면 재진입 후 polling을 복원합니다.
- 공통 poller는 요청을 순차 실행하고 성공·실패 terminal status와 취소·timeout을 처리합니다.

### Workforce

- 시프트 생성·수정·삭제와 급여 미리보기를 구현했습니다.
- 프리셋 생성·수정·삭제·즐겨찾기와 프리셋 기반 시프트 생성을 구현했습니다.
- 기간·근무지·직원별 급여 계산을 구현했습니다.
- 시작·종료·휴게시간·금액·날짜·직원·근무지 validation을 적용했습니다.
- 백엔드 bulk 중복 판정 제약 때문에 단건 생성 방식을 사용합니다.
- Employee PATCH는 unset 필드가 null이 되는 백엔드 동작을 피하도록 전체 payload를 전송합니다.

### 사이니지·관리자

- 사이니지 unknown JSON field를 round-trip 보존합니다.
- 가격 validation, dirty 화면 이탈 확인, backup 응답 안전 파싱을 적용했습니다.
- 모바일에서는 공지·상품명·가격·note 편집만 제공하고 구조 변경을 숨겼습니다.
- 일일보고서 설정 요약, 최근 실행, 실행 상세, 본문, 감사 로그 모니터를 추가했습니다.
- 일일보고서 mutation은 구현하지 않았습니다.

### Android 업데이트

- 다운로드 취소와 오래된 APK 정리를 추가했습니다.
- 404, 409, 파일 크기 변경, SHA-256 변경에서 update metadata를 한 번 다시 조회합니다.
- Android O 이상에서 알 수 없는 앱 설치 권한을 확인하고 앱별 설정 화면을 엽니다.
- 설정 복귀 시 설치를 한 번 자동 재시도합니다.
- package name, build number, 설치된 앱보다 높은 버전, signing identity 검증을 유지했습니다.
- 서버의 `update_available`과 별개로 최신 build가 현재 build보다 높은지 로컬에서 재검사합니다.

## 테스트

추가·확장된 테스트 범위:

- API URL, 204, transport/HTTP 오류 분류
- 민감 캐시 차단, scope, pruning
- remember-me와 cookie 갱신
- 역할 fail-closed와 `AccessGate`
- 공통 task polling, 취소, timeout, terminal status
- 전체 결제수단, forecast, 시간대, 날짜 범위
- sync overdue·partial failure·KST
- Workforce form·payload·employee PATCH
- 사이니지 가격 validation
- 일일보고서 parser·좁은 화면·polling
- APK URL·redirect·크기·해시·설치 상태·취소

## 검증 결과

| 검증 | 결과 |
| --- | --- |
| `flutter analyze` | 통과, issue 0 |
| `flutter test` | 통과 |
| `git diff --check` | 통과 |
| Gradle `compileDebugKotlin` | 통과 |
| Android debug APK | 통과 |
| Android release APK | 서명 환경변수 미설정으로 빌드 시작 단계에서 차단 |
| ADB 실기기 | 원격 ADB 서버 연결 거부로 수행 불가 |

Release 빌드 실패는 코드 컴파일 오류가 아니라 저장소가 요구하는 네 개의 보호된 서명 환경변수가 현재 셸에 없기 때문입니다. Debug APK는 `build/app/outputs/flutter-apk/app-debug.apk`에 생성됐습니다.

## 잔여 운영 확인

- 보호된 CI 변수로 release APK 생성
- 승인된 Android 실기기에서 로그인·역할별 내비게이션 확인
- unknown-source 권한 거부·허용·복귀 설치 흐름 확인
- staging에서 가격 preview와 실제 반영 확인
- staging에서 동기화·Workforce mutation 확인

소스 구현과 자동 검증은 완료했으며, 위 항목은 서명 비밀·연결 기기·승인된 mutation 환경이 필요한 운영 검수입니다.
