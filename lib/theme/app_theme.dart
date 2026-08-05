import 'package:flutter/material.dart';

/// Cafe Bridge의 모바일 운영 콘솔 토큰.
///
/// 기존 Flutter 화면에서 사용하던 teal/slate 역할을 보존하고,
/// 화면별 하드코딩을 줄이기 위한 단일 참조점이다.
abstract final class CafeBridgeColors {
  static const background = Color(0xFFF8FAFC);
  static const surface = Colors.white;
  static const surfaceSubtle = Color(0xFFF1F5F9);
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF475569);
  static const textMuted = Color(0xFF64748B);
  static const textFaint = Color(0xFF94A3B8);
  static const border = Color(0xFFE2E8F0);
  static const accent = Color(0xFF0D9488);
  static const accentStrong = Color(0xFF0F766E);
  static const accentSoft = Color.fromRGBO(13, 148, 136, 0.10);
  static const success = Color(0xFF16A34A);
  static const successSoft = Color.fromRGBO(22, 163, 74, 0.09);
  static const warning = Color(0xFFD97706);
  static const warningSoft = Color(0xFFFFF7ED);
  static const danger = Color(0xFFDC2626);
  static const dangerSoft = Color(0xFFFFF1F2);
  static const info = Color(0xFF155E75);
  static const infoSoft = Color(0xFFECFEFF);
}

abstract final class CafeBridgeSpacing {
  static const page = 16.0;
  static const section = 20.0;
  static const card = 16.0;
  static const control = 12.0;
  static const compact = 8.0;
}

abstract final class CafeBridgeRadii {
  static const card = 14.0;
  static const control = 12.0;
  static const pill = 999.0;
}

abstract final class CafeBridgeTheme {
  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: CafeBridgeColors.accent,
      brightness: Brightness.light,
    ).copyWith(
      surface: CafeBridgeColors.surface,
      onSurface: CafeBridgeColors.textPrimary,
      primary: CafeBridgeColors.accent,
      onPrimary: Colors.white,
      error: CafeBridgeColors.danger,
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: CafeBridgeColors.background,
      visualDensity: VisualDensity.standard,
      appBarTheme: const AppBarTheme(
        backgroundColor: CafeBridgeColors.surface,
        foregroundColor: CafeBridgeColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: CafeBridgeColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: CafeBridgeColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CafeBridgeRadii.card),
          side: const BorderSide(color: CafeBridgeColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CafeBridgeColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CafeBridgeRadii.control),
          borderSide: const BorderSide(color: CafeBridgeColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CafeBridgeRadii.control),
          borderSide: const BorderSide(color: CafeBridgeColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CafeBridgeRadii.control),
          borderSide:
              const BorderSide(color: CafeBridgeColors.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CafeBridgeRadii.control),
          borderSide: const BorderSide(color: CafeBridgeColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CafeBridgeRadii.control),
          borderSide:
              const BorderSide(color: CafeBridgeColors.danger, width: 2),
        ),
        labelStyle: const TextStyle(color: CafeBridgeColors.textSecondary),
        hintStyle: const TextStyle(color: CafeBridgeColors.textFaint),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CafeBridgeRadii.control),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          side: const BorderSide(color: CafeBridgeColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CafeBridgeRadii.control),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: CafeBridgeColors.surface,
        elevation: 0,
        indicatorColor: CafeBridgeColors.accentSoft,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected
                ? CafeBridgeColors.accentStrong
                : CafeBridgeColors.textMuted,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          );
        }),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: CafeBridgeColors.surfaceSubtle,
        side: const BorderSide(color: CafeBridgeColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CafeBridgeRadii.pill),
        ),
        labelStyle: const TextStyle(
          color: CafeBridgeColors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: CafeBridgeColors.border,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: CafeBridgeColors.textPrimary,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CafeBridgeRadii.control),
        ),
      ),
      textTheme: base.textTheme.copyWith(
        headlineSmall: const TextStyle(
          color: CafeBridgeColors.textPrimary,
          fontSize: 24,
          height: 1.2,
          fontWeight: FontWeight.w800,
        ),
        titleLarge: const TextStyle(
          color: CafeBridgeColors.textPrimary,
          fontSize: 20,
          height: 1.25,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: const TextStyle(
          color: CafeBridgeColors.textPrimary,
          fontSize: 16,
          height: 1.3,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: const TextStyle(
          color: CafeBridgeColors.textPrimary,
          fontSize: 15,
          height: 1.45,
        ),
        bodyMedium: const TextStyle(
          color: CafeBridgeColors.textSecondary,
          fontSize: 14,
          height: 1.45,
        ),
        bodySmall: const TextStyle(
          color: CafeBridgeColors.textMuted,
          fontSize: 12,
          height: 1.4,
        ),
      ),
    );
  }
}
