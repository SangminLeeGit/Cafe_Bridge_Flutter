# Cafe Bridge 빌드 후 업데이트 배포 구현 보고서 (비스토어 전용)

> **Historical / superseded:** 이 문서는 2026-04-07 당시의 제안과 미구현 상태를 보존한 기록입니다. iOS/IPA, 수동 ADB 배포, 로컬 서명, 자동 production 등록에 관한 내용은 현재 정책이 아닙니다. Android-only WSL2/CT500 topology와 CI promotion 정책은 `docs/TOPOLOGY.md`가 authoritative합니다.

작성일: 2026-04-07
대상: cafe_bridge_flutter (모바일 앱), cafe_bridge_collector (백엔드)
전제: Play Store / App Store / TestFlight 사용 불가

## 1) 목적
- 현재 구조에서 "빌드 후 운영 배포"와 "운영 중 업데이트 전달"을 비스토어 방식으로 안정화한다.
- 앱/백엔드를 함께 운영하는 관점에서 버전 호환, 권장 업데이트, 무결성 검증, 롤백 체계를 제시한다.

## 2) 현재 상태 진단 (확인 기반)

### 앱 (Flutter)
- Android release가 debug 서명 상태다.
  - `android/app/build.gradle`에서 `signingConfigs.debug` 사용 중.
- 앱 버전은 `pubspec.yaml`의 `version: 1.0.0+1`만 관리한다.
- 업데이트 메타 조회/권장 업데이트 안내/인앱 다운로드 로직이 없다.
- 현재 운영 방식은 수동 빌드 후 `adb install`이다.

### 백엔드 (FastAPI)
- `/healthz`만 존재하며 업데이트 배포 메타 API는 없다.
- 앱 업데이트 정책(최소 지원 버전, 최신 버전, 배포 URL, 해시) 관리 체계가 없다.
- CORS/Origin 완화 TODO가 남아 있어 운영 보안 강화가 필요하다.

## 3) 목표 배포 아키텍처 (스토어 배제)

## 3.1 배포 채널
- Android: 사내 파일 서버 또는 오브젝트 스토리지(S3 호환/MinIO/Nginx)에서 APK 배포
- iOS: 사내 MDM 또는 Apple Enterprise Program 기반 In-House 배포(IPA + manifest.plist)

주의:
- iOS는 스토어 없이 일반 대중 배포가 불가하며, 조직/사내 단말 대상 Enterprise/MDM 체계가 필수다.

## 3.2 업데이트 전달 방식
- 앱 시작 시 백엔드 `/api/app-update/check` 조회
- 응답 정책에 따라:
  - 권장 업데이트: 배너/다이얼로그 노출
  - 선택 업데이트: 다운로드 버튼 제공
  - 최신: 정상 진입

## 3.3 아티팩트 무결성
- 백엔드가 버전별 `sha256` 제공
- 앱은 다운로드 후 해시 검증 성공 시에만 설치 단계 진행

## 4) 필수 구현 항목

## 4.1 앱 필수 구현
1. 정식 릴리즈 서명
- Android keystore 생성/보관
- `android/key.properties` + CI Secret 주입
- `android/app/build.gradle` release signingConfig를 정식 키로 교체

2. 버전/빌드 정책
- SemVer + buildNumber 규칙 확정 (예: `1.3.0+130`)
- CI에서 릴리즈마다 versionCode 자동 증가

3. 업데이트 체크 클라이언트
- 앱 시작 시 `/api/app-update/check` 호출
- 요청 예: `platform`, `channel`, `version`, `build`
- 정책 결과를 로컬 캐시(마지막 성공 정책) 저장

4. 권장 업데이트 UX
- 최신 버전 존재 시 배너/다이얼로그 노출
- 사용자 건너뛰기 허용 (다음 실행 시 재안내)
- 오프라인 시 마지막 정책을 참고해 안내 메시지 유지

5. 비스토어 설치 플로우
- Android:
  - APK 다운로드(백그라운드)
  - SHA-256 검증
  - 설치 인텐트 호출 (`REQUEST_INSTALL_PACKAGES` 정책 반영)
- iOS:
  - 직접 설치가 아닌 `itms-services://?action=download-manifest&url=...` 또는 MDM 트리거 URL 호출

6. 관측성
- 업데이트 체크 성공/실패
- 다운로드 실패/해시 불일치
- 업데이트 안내 노출/건너뛰기 이벤트 로깅

## 4.2 백엔드 필수 구현
1. 업데이트 메타 API
- `GET /api/app-update/check?platform=android&channel=prod&version=1.0.0&build=1`
- 예시 응답:
```json
{
  "latest_version": "1.1.0",
  "latest_build": 23,
  "download_url": "https://downloads.example.com/cafe-bridge/android/app-v1.1.0+23.apk",
  "sha256": "f2c6...",
  "file_size": 55781234,
  "release_notes": "세션 안정화 및 UX 개선",
  "published_at": "2026-04-07T12:00:00Z"
}
```

2. 정책 저장소
- DB 테이블 또는 버전관리 JSON/YAML
- 플랫폼별/채널별/prod-stage 구분
- 즉시 롤백 가능한 이전 정책 스냅샷 유지

3. 다운로드 아티팩트 보관
- 경로 규칙: `/cafe-bridge/{platform}/{channel}/{version}/...`
- immutable 파일명 + 장기 캐시 헤더
- 업로드 시 해시 자동 계산/저장

4. 보안 강화
- CORS/Origin TODO 해소
- 다운로드 URL에 짧은 만료 토큰(서명 URL) 적용
- 내부망 배포 시 네트워크 allowlist 적용

## 5) CI/CD 설계안 (비스토어)

## 5.1 앱 파이프라인
- 트리거: `release/*` 브랜치 또는 태그
- 단계:
  1) `flutter pub get`
  2) `flutter analyze`
  3) 테스트
  4) `flutter build apk --release` (Android)
  5) `flutter build ipa --release` (iOS Enterprise/Ad-Hoc 환경)
  6) 서명
  7) 해시 생성 (`sha256sum`)
  8) 배포 저장소 업로드
  9) 백엔드 업데이트 정책 반영 API 호출 또는 정책 파일 커밋

필수 비밀값:
- Android keystore, key alias/password
- iOS 서명 인증서/프로비저닝 프로파일
- 배포 저장소 접근 키

## 5.2 백엔드 파이프라인
- 단계:
  1) lint/test
  2) 이미지 빌드
  3) 배포
  4) `/healthz` 확인
  5) 업데이트 정책 API 가용성 확인

## 6) 운영 체크리스트

릴리즈 전
- [ ] Android 정식 서명 확인 (debug 키 금지)
- [ ] iOS Enterprise/MDM 인증서 유효성 확인
- [ ] 버전 증가 및 릴리즈 노트 확정
- [ ] APK/IPA 해시 생성 및 검증
- [ ] 업데이트 정책(latest/download_url/sha256) 등록
- [ ] 권장 업데이트 안내 시나리오 QA

릴리즈 직후
- [ ] 다운로드 성공률/실패율 모니터링
- [ ] 해시 불일치 이벤트 모니터링
- [ ] 업데이트 안내 노출률/업데이트 전환율 모니터링
- [ ] 필요 시 이전 정책으로 즉시 롤백

## 7) 단계별 실행 계획 (현 구조 기준)

Phase A (1~2일) - 배포 필수기반
- Android release 정식 서명 전환
- 버전/빌드 규칙 확정
- 아티팩트 업로드 저장소 구성

Phase B (2~3일) - 업데이트 정책 도입
- `/api/app-update/check` 구현
- 앱 시작 시 버전 체크 + 권장 업데이트 UI 구현

Phase C (2~3일) - 업데이트 UX + 무결성
- 권장 업데이트 안내 화면 구현
- 다운로드 후 SHA-256 검증 구현

Phase D (지속) - 운영 안정화
- 롤백 자동화
- 배포/업데이트 모니터링 대시보드

## 8) 우선순위 결론
1순위: 정식 서명 전환(debug 서명 제거)
2순위: 업데이트 메타 API + 다운로드 URL/해시 정책
3순위: 앱 권장 업데이트 UX + 무결성 검증
4순위: 비스토어 CI/CD 자동화 및 정책 롤백

핵심: 스토어 없이 운영 배포를 하려면 "서명 + 원격정책 + 안전다운로드 + 권장업데이트 + 롤백" 5요소가 필수다.
