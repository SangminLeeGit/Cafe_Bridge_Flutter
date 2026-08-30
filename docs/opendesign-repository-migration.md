# OpenDesign Repository Migration

## 조사 기준

- 운영 project ID는 `cafebridge-flutter-android`이며 새 프로젝트를 만들지 않는다.
- `opendesign-ade.service`는 `127.0.0.1:7457`에서 실행되고 active data는 `/home/sangmin/dev/tools/open-design-v0.16.1/data`에 둔다.
- OpenCode MCP는 `OD_DAEMON_URL=http://127.0.0.1:7457`로 같은 daemon을 사용한다.
- 운영 metadata의 `baseDir`과 `resolvedDir`은 `/home/sangmin/dev/workspaces/cafe-bridge-flutter/design/open-design/cafebridge-flutter-android`이다.
- `repositoryRoot`와 `linkedDirs`는 `/home/sangmin/dev/workspaces/cafe-bridge-flutter`이다.
- repo의 OpenDesign 작업물 10개는 Git에 추적된다. Active managed project root에는 작업물 복사본 없이 `.file-versions`만 남아 있으므로 기존 버전 이력은 daemon runtime state로 보존한다.
- 이전 managed-data backup과 비활성 OpenDesign checkout의 `data/projects/cafebridge-flutter-android`에는 작업물 중복본이 남아 있다. 두 경로는 현재 service와 MCP metadata에서 참조하지 않는다.

## 이관 계획

1. Project ID, metadata, 상태, 대화 연결, file-version 이력을 변경 전 기준으로 확인한다.
2. 운영 프로젝트의 `linkedDirs`를 현재 Flutter repo로 재확정하고, `baseDir`/`resolvedDir`이 repo 내부 디자인 경로를 유지하는지 확인한다.
3. MCP를 통해 동일 프로젝트의 기존 파일을 직접 저장해 실제 쓰기 대상이 Git workspace인지 검증한다.
4. Active DB, run 상태와 `.file-versions`는 유지하고, 참조되지 않는 외부 작업물 중복본과 이관 backup만 제거한다.
5. Local/LAN preview, daemon API, MCP file 목록과 Git 추적 상태를 확인한다.
6. Flutter dependency, analyze, test, Android debug APK build와 `git diff --check`를 실행한 뒤 문서 변경을 commit하고 `origin/master`에 push한다.

## 관리 원칙

- 디자인 파일의 단일 관리 위치는 `design/open-design/cafebridge-flutter-android/`이다.
- Flutter 구현 및 API contract가 artifact와 다르면 현재 repo source를 우선한다.
- OpenDesign DB, conversation, run status와 `.file-versions`는 Git 산출물이 아닌 daemon runtime state로 유지한다.
- `.opencode`, `.file-versions`, `.transcript.jsonl`은 디자인 작업물 경로에서 Git 추적하지 않는다.

## 실행 및 검증 결과

- 2026-08-31에 동일 project ID `cafebridge-flutter-android`의 전체 metadata를 repo 내부 경로로 확정했다.
- Daemon 재시작 후에도 conversation `26ce8dc6-2862-422c-9c22-c19058144e43`, 4개 message, 기존 run 상태와 `index.html` version `fb20dcc6-5a01-400e-bff0-fb5789b8fa00`이 유지됐다.
- 재시작된 daemon에 연결된 MCP로 기존 `README.md`를 저장한 뒤 Git diff가 없음을 확인했다.
- Disk, local preview, LAN preview의 `index.html` SHA-256은 모두 `419dd4d335582a04b493a4380ac4f9229c377b4bec8dbd5c370e6ce5874c43f7`로 일치했다.
- Active managed root에는 `.file-versions`만 유지하고, 비활성 checkout의 project copy와 migration backup의 중복본은 제거했다.
- `flutter pub get --enforce-lockfile`, `flutter analyze`, 77개 test, JDK 21 기반 Android debug APK build가 통과했다.
