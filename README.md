# Cafe Bridge Mobile

Cafe Bridge FastAPI backend의 Android 운영·분석 클라이언트입니다. Flutter 앱과 Android APK 배포 코드는 이 저장소에서 독립적으로 버전 관리합니다.

지원 대상은 Android뿐입니다. 개발·OpenCode/OpenDesign·Flutter/Gradle은 WSL2에서 수행하고, 실기기 검증은 VM900이 관리하는 shared ADB server를 사용합니다. CT500은 runtime/deployment와 별도의 protected Flutter GitLab runner를 호스팅하지만, 일반 개발·수동 빌드·ADB 호스트는 아닙니다. 최신 runner 관찰 및 release 가드 불일치는 `docs/TOPOLOGY.md`를 참조하세요.

## 주요 기능

- 세션 쿠키와 CSRF 기반 로그인
- 매출 대시보드, 일 상세, 10개 분석 화면
- viewer 상품 조회와 operator 가격 미리보기·반영
- 원가 조회와 저장 없는 레시피 계산
- 동기화 실행 및 재개 가능한 작업 상태 확인
- 근무지, 직원, 시프트, 프리셋, 급여 계산
- 제한된 사이니지 편집과 터치키 조회
- admin 사용자·감사·배포·일일보고서 읽기 전용 모니터
- 서명·패키지·빌드·SHA-256을 검증하는 Android APK 업데이트

## 권한

| 기능 | 최소 역할 |
| --- | --- |
| 대시보드, 분석, 상품 조회, Workforce, 터치키 조회 | `viewer` |
| 원가, 가격 변경, 사이니지, 동기화 | `operator` |
| 메뉴 작업대, 사용자·감사·배포·일일보고서 모니터 | `admin` |

사용자 변경, 배포 실행, 일일보고서 정책 변경, 신규상품 실제 등록·삭제, 터치키 실제 반영 등 고위험 관리 작업은 운영자 웹에서 수행합니다.

## 개발 환경

저장소는 `.flutter-version`과 `.flutter-revision`에 기록된 Flutter SDK를 기준으로 검증합니다.

```bash
/home/sangmin/dev/sdk/flutter-3.41.7/bin/flutter pub get --enforce-lockfile
/home/sangmin/dev/sdk/flutter-3.41.7/bin/flutter analyze
/home/sangmin/dev/sdk/flutter-3.41.7/bin/flutter test
```

Android SDK가 기본 환경변수에 없으면 다음과 같이 지정합니다.

```bash
ANDROID_HOME=/home/sangmin/dev/sdk/android-sdk \
ANDROID_SDK_ROOT=/home/sangmin/dev/sdk/android-sdk \
/home/sangmin/dev/sdk/flutter-3.41.7/bin/flutter build apk --debug
```

`ios/`, `web/`, `linux/`, `macos/`, `windows/`는 Flutter가 생성한 unsupported/inert scaffolding입니다. 명시적인 범위 변경이 없으면 빌드·검증·배포 대상으로 취급하지 않으며, 단순히 존재한다는 이유로 삭제하지 않습니다.

## Release Signing

Release APK에는 다음 환경변수가 모두 필요합니다.

```text
CAFE_BRIDGE_ANDROID_KEYSTORE_PATH
CAFE_BRIDGE_ANDROID_KEY_ALIAS
CAFE_BRIDGE_ANDROID_STORE_PASSWORD
CAFE_BRIDGE_ANDROID_KEY_PASSWORD
```

서명값이나 keystore를 저장소에 추가하거나 로컬에서 signed release를 만들지 않습니다. APK는 CI의 보호된 변수와 전용 Android runner를 통해 생성합니다. IPA와 비 Android release artifact는 생성하지 않습니다.

## CI/CD

`.gitlab-ci.yml`은 protected `master`, `release/*`, tag push의 보안 검사, Flutter/Android 검증 및 signed APK dry-run artifact 생성을
`cafe-bridge-android-release` tag runner에 배정하고, 성공한 artifact를 7일간 보관하도록 설정합니다. 2026-10-23
21:42 KST GitLab API 확인에서는 protected·online Runner 13이 CT500에 등록된 것으로 나타났습니다. 다만
`.gitlab/ci/android-release.sh`에는 runner 설명에 `ct600`을 요구하는 가드가 남아 있어 현재 등록 설명과 충돌합니다.
따라서 runner 등록만으로 release job의 성공을 보장할 수 없습니다. ordinary push는 production APK를 등록하지 않으며,
Cafe Bridge APK release/deploy API 등록은 protected API/trigger 또는 protected web pipeline의 manual action으로만 수행합니다.

## 보안

- 운영 빌드는 HTTPS만 허용합니다.
- 세션 쿠키는 로그인 유지 선택 시에만 secure storage에 저장합니다.
- 급여, 직원, 원가, 감사, 배포, 메뉴 작업 데이터는 디스크 캐시에서 제외합니다.
- 401/403과 서버 오류에는 stale cache를 사용하지 않습니다.
- Android 업데이트는 HTTPS, 크기, SHA-256, application ID, build number, signing identity를 검증합니다.

과거 구조 분석과 검증 증거는 `REFACTORING_PLAN.md`와
`ANDROID_BACKEND_ALIGNMENT_COMPLETION_REPORT_2026-07-24.md`에 보존되어 있습니다.
현재 실행 기준은 `docs/TOPOLOGY.md`를 따릅니다.
