# Cafe Bridge Mobile

Cafe Bridge FastAPI backend의 Android 운영·분석 클라이언트입니다. Flutter 앱과 Android APK 배포 코드는 이 저장소에서 독립적으로 버전 관리합니다.

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
/home/sangmin/tools/flutter/bin/flutter pub get --enforce-lockfile
/home/sangmin/tools/flutter/bin/flutter analyze
/home/sangmin/tools/flutter/bin/flutter test
```

Android SDK가 기본 환경변수에 없으면 다음과 같이 지정합니다.

```bash
ANDROID_HOME=/opt/android-builder/android-sdk \
ANDROID_SDK_ROOT=/opt/android-builder/android-sdk \
/home/sangmin/tools/flutter/bin/flutter build apk --debug
```

Web 컴파일 경계도 유지되며 다음 명령으로 확인할 수 있습니다.

```bash
/home/sangmin/tools/flutter/bin/flutter build web --release
```

## Release Signing

Release APK에는 다음 환경변수가 모두 필요합니다.

```text
CAFE_BRIDGE_ANDROID_KEYSTORE_PATH
CAFE_BRIDGE_ANDROID_KEY_ALIAS
CAFE_BRIDGE_ANDROID_STORE_PASSWORD
CAFE_BRIDGE_ANDROID_KEY_PASSWORD
```

서명값이나 keystore를 저장소에 추가하지 않습니다. APK는 CI의 보호된 변수와 전용 Android runner를 통해 생성합니다.

## 보안

- 운영 빌드는 HTTPS만 허용합니다.
- 세션 쿠키는 로그인 유지 선택 시에만 secure storage에 저장합니다.
- 급여, 직원, 원가, 감사, 배포, 메뉴 작업 데이터는 디스크 캐시에서 제외합니다.
- 401/403과 서버 오류에는 stale cache를 사용하지 않습니다.
- Android 업데이트는 HTTPS, 크기, SHA-256, application ID, build number, signing identity를 검증합니다.

상세 구현 결과는 `ANDROID_BACKEND_ALIGNMENT_COMPLETION_REPORT_2026-07-24.md`를 참조하세요.
구조 분석과 실행 기준은 `REFACTORING_PLAN.md`를, 상세 구현 결과는
`ANDROID_BACKEND_ALIGNMENT_COMPLETION_REPORT_2026-07-24.md`를 참조하세요.
