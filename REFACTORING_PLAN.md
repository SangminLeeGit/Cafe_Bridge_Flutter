# Cafe Bridge Flutter 구조적 리팩토링 계획

기준일: 2026-08-05

## 1. 기준선 분석

현재 저장소는 기능 정합화 작업이 이미 진행된 상태이며, 기능별 모델·화면·공통 위젯과 15개 이상의 테스트 파일이 존재한다. 기준선 검증 결과는 다음과 같다.

- `lib/state/app_state.dart`가 인증, 세션 쿠키, CSRF, API 요청, 캐시, 오프라인 표시, keepalive, 앱 업데이트를 모두 담당한다.
- `lib/services/api.dart`가 URL 정책과 HTTP 전송을 정적 메서드로 함께 제공하며 요청마다 `http.Client`를 새로 생성한다.
- `SharedPreferences`가 `AppState`, 가격 적용 화면, 동기화 화면에서 직접 사용되어 로컬 저장소 책임이 분산되어 있다.
- `MaterialApp`에 명시적인 라우트 경계가 없고, 일부 pushed 화면(`DayDetailScreen`, 원가 상세, 사이니지 품목 편집)이 인증 만료 이후에도 Navigator stack에 남을 수 있다.
- `AppState`의 세션·서버 변경 중 이전 요청의 응답이 새 세션의 쿠키, 캐시, 오프라인 상태를 덮어쓸 수 있다.
- 401 처리 시 이전 사용자 캐시와 작업 복원 키가 남고, `/api/price/browser-apply`와 `/api/sync`가 캐시 정책에서 명시적으로 제외되지 않았다.
- remember-me 세션으로 재시작한 뒤 네트워크가 끊기면 로그인 화면으로 내려가므로 화면에 표시된 오프라인 안내와 실제 복원 동작이 일치하지 않는다.
- `dart:io`를 공용 API 파일에서 직접 import하여 Web 컴파일 경계를 약화한다.
- `analytics.dart`, `menu_workspace.dart`, `workforce_mobile.dart`가 여러 feature controller와 화면 상태를 한 파일에 co-locate하고 있으나, 그보다 우선해 고쳐야 할 요청 경합·저장소·생명주기 결함이 있다.
- `fl_chart`, `ApiService.defaultRange`, `AppState.load`, `fetchListParsed`, `openInstaller`는 저장소 내 사용처가 없다. `cupertino_icons`는 애플리케이션 위젯에서 직접 사용하지 않지만 Flutter localization delegate가 참조하는 아이콘 font 경계를 만족하기 위해 유지한다.
- 로그인·화면 데이터 로딩은 대부분 수동 boolean 상태로 구현되어 요청 세대 관리가 일관되지 않다. 동기화 복원은 예외가 호출자까지 전파될 수 있다.
- 기존 테스트는 모델·보안·캐시·poller 중심이며, 인증 경합, 오프라인 세션 복원, 전역 stack 정리, Web 빌드, 주요 화면 전이 검증이 부족하다.

기준선 명령:

```text
/home/sangmin/tools/flutter/bin/flutter pub get --enforce-lockfile
/home/sangmin/tools/flutter/bin/flutter analyze
/home/sangmin/tools/flutter/bin/flutter test
```

## 2. 실행 계획

### P1. 네트워크와 의존성 방향

- `ApiClient` 인스턴스를 도입하여 HTTP client를 주입·재사용·종료 가능하게 한다.
- `ApiService`는 순수 URL·날짜 정책과 정적 호환 진입점만 유지하고, 공용 전송 계층에서 `dart:io` 의존성을 제거한다.
- API 응답/오류 변환을 한 경계로 모아 map/list/204/transport 오류 처리를 일관되게 한다.
- `AppState`가 `ApiClient`, `SharedPreferences`, secure storage를 생성자에서 주입받을 수 있게 하여 화면의 직접 데이터 접근을 차단한다.

### P2. 세션, 캐시와 비동기 안전성

- 세션 epoch와 요청 순번을 도입해 서버 주소·로그인·로그아웃·401 이후 이전 응답의 상태 변경과 캐시 쓰기를 폐기한다.
- 쿠키 갱신은 요청 시작 순서를 기준으로 역전되지 않게 한다.
- 인증 무효화 시 기존 사용자 cache scope와 active task key를 함께 삭제한다.
- 가격 반영·동기화·관리자 작업 등 상태 변경/민감 endpoint는 디스크 캐시를 명시적으로 금지한다.
- remember-me의 마지막 사용자 식별자를 저장하여 재시작 시 transport 오류에 한해 캐시 기반 오프라인 세션을 복원한다. 401/403은 절대 오프라인 fallback하지 않는다.
- local load를 idempotent하게 만들고 `ChangeNotifier` dispose 이후 notify/timer/update retry가 실행되지 않도록 한다.
- 화면에 분산된 active task `SharedPreferences` 접근을 `AppState` 저장소 API로 통합한다.

### P3. 라우팅과 UI 책임

- 권한이 필요한 pushed route 생성을 `AppNavigation.pushGuarded`로 통합한다.
- 인증 상태가 guest로 전환되면 전역 Navigator stack을 root까지 정리한다.
- MainLayout navigation item을 불변으로 유지하고 `context.select`를 사용해 AppState의 unrelated update로 전체 탭 stack이 재빌드되지 않게 한다.
- 테마·색상·브랜드 asset을 `AppTheme`/`AppColors`로 모아 공통 위젯의 중복 스타일을 제거한다.
- 설정 화면의 build 중 controller mutation을 lifecycle 단계로 이동한다.
- 대형 화면은 기존 feature 경계를 유지하면서 네트워크/저장소 책임을 AppState 밖으로 밀어내고, 요청 재진입·dispose 안전성을 우선 보강한다. 목적 없는 파일 분할이나 새 패턴 도입은 하지 않는다.

### P4. 테스트와 검증

- API client, 세션 epoch/cache isolation, 401 cache purge, offline restore, active task storage, navigation guard를 테스트한다.
- 기존 모델·위젯 테스트를 유지하고 주요 로그인/권한/stack 흐름 smoke test를 보강한다.
- 사용하지 않는 dependency/API를 제거하고 정적 검색으로 debug 출력·임시 코드·주석 잔여물을 재점검한다.
- 의존성 설치, 코드 생성 필요 여부, format, analyze, test, Android debug APK, Web build를 반복 실행한다.
- 계획 항목별 구현 여부와 남은 제한사항을 최종 대조한다.

## 3. 완료 기준

- P1~P4의 각 bullet이 코드 또는 테스트로 확인된다.
- 기존 기능 계약과 권한 정책은 유지된다.
- `flutter analyze` 경고/오류가 없고 전체 테스트가 통과한다.
- Android debug APK와 Web build가 성공하거나, 플랫폼 도구 부재 등 저장소 밖의 원인만 구체적으로 기록된다.
- 미사용 dependency/API, debug 출력, 미해제 timer/controller/subscription이 남지 않는다.

## 4. 실제 구현 대조

| 계획 | 구현 확인 |
| --- | --- |
| P1 네트워크·DI | `ApiClient`, `ActiveTaskStore`, `AppState` 생성자 주입, 공용 API Web 경계, settings health check 통합 |
| P2 세션·캐시·비동기 | session epoch/request sequence, 쿠키 역전 방지, 401 scope 삭제, 민감 endpoint 정책, offline restore, task persistence, dispose-safe notifier |
| P3 라우팅·UI | `AppNavigation.pushGuarded`, 인증 만료 시 root pop, 불변 MainLayout navigation, `context.select`, `AppTheme`/`AppColors`, 화면별 request generation guard |
| P4 테스트·검증 | active task, stale response, 401 purge, offline restore, cache policy 회귀 테스트와 기존 모델/위젯 테스트 유지 |

대형 feature 파일은 이미 내부적으로 탭·상세 화면 경계를 갖고 있어 목적 없는 파일 이동은 하지 않았다. 대신 각 경계의 요청 세대와 수명주기를 보강하고, 네트워크·로컬 저장소 접근은 공통 경계로 이동했다.
