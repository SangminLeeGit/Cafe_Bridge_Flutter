# CafeBridge Flutter Android · OpenDesign Atlas

실제 Flutter 구현을 기준으로 만든 OpenDesign 전체 앱 디자인 프로젝트입니다.

- **OpenDesign project:** `CafeBridge Flutter Android`
- **Project id:** `cafebridge-flutter-android`
- **Entry:** `index.html`
- **Interactive flows:** `prototype/flows.html`
- **Route/state completion:** `screens/route-state-completion.html`
- **Viewport:** Android 412 × 915dp artboard
- **OpenDesign preview:** `http://127.0.0.1:7457/api/projects/cafebridge-flutter-android/raw/index.html`
- **Source 기준:** `lib/main.dart`, `lib/navigation`, `lib/screens`, `lib/widgets`, `lib/theme/app_theme.dart`

## 포함 범위

- Cover / Overview
- Design System
- Navigation Map
- Main Screens
- Detail Screens
- Settings & Admin
- Dialogs & Modals
- Bottom Sheets (실제 코드에 없음)
- Components
- States / Edge Cases
- Coverage Matrix

초기화·로그인·5개 하단 탭·권한 게이트·모든 주요 조회/상세/관리 화면·의미 있는 loading/empty/error/offline/cache/task/success/failure 상태·실제 `showDialog` 흐름을 포함합니다. `Drawer`와 실제 Bottom Sheet 호출은 소스에 없으며, 이름에 `Sheet`가 포함된 세 화면은 실제 구현대로 full-screen route로 표시했습니다. `_openNewItemScreen()`은 unused 경로이므로 조건부 명세로만 표시했습니다.

상세 source inventory, interaction map, coverage matrix는 OpenDesign project의 `docs/` 아래에 함께 보관합니다. `prototype/flows.html`은 로그인·5탭·상세 진입/뒤로가기·가격/메뉴판 확인 Dialog·동기화 진행·인력 Dialog·설정/서버 상태·권한 게이트를 클릭으로 검증하는 실행형 프로토타입입니다.
