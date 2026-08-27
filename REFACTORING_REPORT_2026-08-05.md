# Cafe Bridge Flutter 구조적 리팩토링 최종 보고서

> **Historical validation record:** Web smoke/build, 로컬 origin, Xcode, remote-ADB 제한은 2026-08-05 당시 결과이며 현재 mandatory target 또는 topology가 아닙니다. 현재 Android-only WSL2 validation 기준은 `docs/TOPOLOGY.md`를 따릅니다.

## 1. 핵심 문제

- `AppState`에 인증, HTTP, 캐시, 오프라인, 업데이트, keepalive가 집중되어 있었다.
- 정적 HTTP 계층이 요청마다 client를 생성했고 `dart:io`가 공용 API 파일에 결합되어 있었다.
- 화면이 `SharedPreferences`를 직접 사용하고 active task 저장 키가 화면별로 중복되었다.
- 세션·서버 변경 뒤 이전 요청의 응답이 쿠키, 상태, cache scope를 덮을 수 있었다.
- 401 이후 이전 사용자 cache와 작업 복원 키가 남을 수 있었다.
- remember-me 세션의 재시작 오프라인 복원이 실제 화면 흐름과 일치하지 않았다.
- 일부 pushed 화면의 권한 경계가 route 생성 위치마다 달랐고 인증 만료 시 nested stack이 남을 수 있었다.
- 분석·작업대·인력 등 화면의 새로고침 요청 세대와 controller 생명주기 처리가 일관되지 않았다.
- 공통 테마·색상·레이아웃과 사용하지 않는 dependency/API가 섞여 있었다.

## 2. 계획

상세 실행 기준은 `REFACTORING_PLAN.md`에 기록했다. 계획은 네트워크/DI, 세션·캐시·비동기 안전성, 라우팅·UI 책임, 테스트·검증의 P1~P4로 구성했다.

## 3. 구현 결과

- `ApiClient`를 도입해 HTTP client 재사용, 주입, 종료, JSON/204/transport 오류 처리를 한 경계로 통합했다.
- `AppState`에 API client, preferences, secure storage 주입 지점을 추가했다.
- `ActiveTaskStore`를 추가하고 동기화·가격 적용 화면의 직접 `SharedPreferences` 접근을 제거했다.
- session epoch, 요청 순번, 쿠키 갱신 순서 검사를 추가해 stale response를 폐기했다.
- 401, logout, 서버 주소 변경, 사용자 변경 시 cache scope와 active task를 정리한다.
- `/api/price/browser-apply`, `/api/sync`와 기존 민감 endpoint의 디스크 cache를 차단했다.
- remember-me 사용자 식별자를 복원하고 transport 오류일 때만 offline session을 유지한다.
- `AppNavigation.pushGuarded`와 전역 navigator stack 정리를 추가했다.
- MainLayout navigation item을 불변으로 만들고 `context.select`로 불필요한 rebuild를 줄였다.
- `AppTheme`, `AppColors`, 공통 shell/state 위젯을 사용하도록 정리했다.
- `AsyncRequestGuard`를 주요 async 화면과 분석/인력/원가/상품/작업대 흐름에 적용했다.
- task polling에서 취소된 이전 작업의 늦은 응답이 화면을 덮지 않도록 했다.
- `fl_chart`, 미사용 API(`defaultRange`, `load`, `fetchListParsed`, `openInstaller`)를 제거했다. Flutter localization delegate의 font 경계를 위해 `cupertino_icons`는 유지했다.
- stale response, cookie 순서, 401 cache purge, offline restore, active task scope를 `test/refactoring_regression_test.dart`에 추가했다.

## 4. 삭제·통합

- 화면별 `SharedPreferences` task key 구현을 `ActiveTaskStore`로 통합했다.
- 정적 API 전송 구현을 `ApiClient`로 통합했다.
- 반복된 권한 route wrapper를 `AppNavigation`으로 통합했다.
- 미사용 `fl_chart` dependency 및 미사용 helper/API를 삭제했다.
- 기존 기능 화면 파일은 목적 없는 대규모 파일 이동을 피하고, 내부 async 책임과 공통 경계만 정리했다.

## 5. 검증

```text
/home/sangmin/tools/flutter/bin/flutter clean
/home/sangmin/tools/flutter/bin/flutter pub get --enforce-lockfile
/home/sangmin/tools/flutter/bin/dart format --output=none --set-exit-if-changed lib test
/home/sangmin/tools/flutter/bin/flutter analyze
/home/sangmin/tools/flutter/bin/flutter test
/home/sangmin/tools/flutter/bin/flutter build web --release
ANDROID_HOME=/opt/android-builder/android-sdk ANDROID_SDK_ROOT=/opt/android-builder/android-sdk /home/sangmin/tools/flutter/bin/flutter build apk --debug
git diff --check
```

결과:

- dependency 설치: 통과
- format check: 통과
- `flutter analyze`: `No issues found!`
- 전체 테스트: 통과
- Web release build: 성공
- Android debug APK: 성공
- diff whitespace check: 통과
- Web smoke: 앱 로드 및 auth/update 요청 도달 확인

## 6. 계획 대비 미구현

계획서의 구현 가능한 항목 중 미구현 항목은 없다.

## 7. 제한사항

- Linux 실행 환경에는 Xcode가 없어 iOS/macOS native build는 실행할 수 없었다. 저장소의 실제 배포 검증 대상인 Android와 Web은 빌드했다.
- 로컬 Web origin에 대한 운영 백엔드 CORS 허용이 없어 로그인 성공까지의 live backend flow는 확인할 수 없었다. 앱 자체는 요청 생성과 오류 경로까지 실행했다.
- 원격 ADB MCP에는 Android 기기가 보였지만 로컬 ADB server와 연결되지 않아 물리 기기 설치·탭 자동화는 실행할 수 없었다.
