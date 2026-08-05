import 'package:flutter/material.dart';

abstract final class AppColors {
  static const primary = Color(0xFF0D9488);
  static const primaryDark = Color(0xFF0F766E);
  static const ink = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF475569);
  static const muted = Color(0xFF64748B);
  static const subtle = Color(0xFF94A3B8);
  static const border = Color(0xFFE2E8F0);
  static const surface = Colors.white;
  static const surfaceSubtle = Color(0xFFF1F5F9);
  static const background = Color(0xFFF8FAFC);
  static const success = Color(0xFF16A34A);
  static const successSoft = Color.fromRGBO(22, 163, 74, 0.09);
  static const warning = Color(0xFFD97706);
  static const warningSoft = Color(0xFFFFF7ED);
  static const warningForeground = Color(0xFF9A3412);
  static const warningStrong = Color(0xFF7C2D12);
  static const warningBorder = Color(0xFFFED7AA);
  static const warningAction = Color(0xFFEA580C);
  static const danger = Color(0xFFDC2626);
  static const dangerSoft = Color(0xFFFFF1F2);
  static const info = Color(0xFF155E75);
  static const offlineBackground = Color(0xFFECFEFF);
  static const offlineForeground = Color(0xFF155E75);
  static const infoSoft = Color(0xFFECFEFF);
}

const cafeBridgeLogoAsset = 'assets/branding/cafe_bridge_logo.png';

abstract final class AppSpacing {
  static const page = 16.0;
  static const section = 20.0;
  static const card = 16.0;
  static const control = 12.0;
  static const compact = 8.0;
}

abstract final class AppRadii {
  static const card = 14.0;
  static const control = 12.0;
  static const pill = 999.0;
}

abstract final class AppTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.ink,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.card)),
          side: BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: const BorderSide(color: AppColors.danger, width: 2),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.subtle),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
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
        backgroundColor: AppColors.surface,
        elevation: 0,
        indicatorColor: AppColors.primary.withValues(alpha: 0.1),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? AppColors.primaryDark : AppColors.muted,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          );
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceSubtle,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        labelStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
      ),
      textTheme: ThemeData.light().textTheme.copyWith(
            headlineSmall: const TextStyle(
              color: AppColors.ink,
              fontSize: 24,
              height: 1.2,
              fontWeight: FontWeight.w800,
            ),
            titleLarge: const TextStyle(
              color: AppColors.ink,
              fontSize: 20,
              height: 1.25,
              fontWeight: FontWeight.w800,
            ),
            titleMedium: const TextStyle(
              color: AppColors.ink,
              fontSize: 16,
              height: 1.3,
              fontWeight: FontWeight.w700,
            ),
            bodyLarge: const TextStyle(
              color: AppColors.ink,
              fontSize: 15,
              height: 1.45,
            ),
            bodyMedium: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.45,
            ),
            bodySmall: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
    );
  }
}
