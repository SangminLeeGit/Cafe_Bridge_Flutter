# Cafe Bridge design source

Source: `design` branch after `origin/main` commit `8b446eee4ebd8815fbbaffe35066785329093b09` was fetched and merged. Tokens below are extracted from `lib/theme/app_theme.dart` and `docs/cafe-bridge-screen-map.md`; no new product colors were introduced.

```css
:root {
  --bg: #F8FAFC;
  --surface: #FFFFFF;
  --fg: #0F172A;
  --muted: #64748B;
  --border: #E2E8F0;
  --accent: #0D9488;
}
```

Supporting implementation colors: `#475569`, `#94A3B8`, `#F1F5F9`, `#0F766E`, `#16A34A`, `#D97706`, `#DC2626`, `#ECFEFF`, `#155E75`, `#FFF7ED`, `#FFF1F2`.

Typography follows Flutter Material 3's platform sans-serif defaults because the source does not declare a custom font. Use `-apple-system`, `BlinkMacSystemFont`, `Segoe UI`, then the platform sans fallback. Numeric and API-field annotations use a system monospace stack only for traceability.

The system is a cool, operational mobile console: pale slate canvas, white surfaces, teal reserved for selection and primary execution, compact cards with 14px radius, 16dp page padding, 12–16dp card spacing, and 44dp minimum touch targets.

Posture rules observed:

- The authenticated shell uses five bottom destinations: 홈, 분석, 업무, 인력, 더보기.
- Every data screen exposes loading, empty, error, and retry states; cached responses identify cache origin and time.
- Viewer access remains visible; operator/admin-only actions are locked with the required role.
- High-risk operations preserve 입력 → 검증 → 영향 요약 → 확인 → 작업 상태 → 결과/재시도.
- The app is touch-first; no web-only sidebar, hover, or drag pattern is part of this specification.
