import 'package:flutter/material.dart';

/// Colour tokens from the Extracter design canvas (light theme).
abstract final class AppColors {
  static const ground = Color(0xFFF6F6F3);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFFBFBF9);
  static const chip = Color(0xFFEFEFEA);
  static const track = Color(0xFFE6E6E0);
  static const border = Color(0xFFDEDED8);
  static const borderStrong = Color(0xFFCFCFC8);
  static const divider = Color(0xFFF0F0EB);
  static const ink = Color(0xFF1A1A18);
  static const inkSecondary = Color(0xFF55554F);
  static const inkMuted = Color(0xFF6B6B64);
  static const inkDisabled = Color(0xFFA8A8A0);
  static const accent = Color(0xFF0F6E66);
  static const accentSoft = Color(0xFFE3F1EF);
  static const warning = Color(0xFF8A5200);
  static const warningSoft = Color(0xFFFBF0DC);
  static const error = Color(0xFFB42318);
  static const errorSoft = Color(0xFFFDECEA);
  static const errorBorder = Color(0xFFF3C7C2);
}

abstract final class AppTheme {
  static const double radius = 12;

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      primary: AppColors.accent,
      onPrimary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      error: AppColors.error,
    ).copyWith(surfaceContainerLowest: AppColors.ground, outline: AppColors.border, outlineVariant: AppColors.divider);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    const buttonSize = Size(44, 44);
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.ground,
      dividerColor: AppColors.divider,
      textTheme: Typography.blackMountainView.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.ground,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          shape: shape,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          shape: shape,
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.border),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: buttonSize, shape: shape, foregroundColor: AppColors.inkSecondary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.borderStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.borderStrong),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.accentSoft,
        selectedIconTheme: IconThemeData(color: AppColors.accent),
        unselectedIconTheme: IconThemeData(color: AppColors.inkSecondary),
        selectedLabelTextStyle: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600, fontSize: 12),
        unselectedLabelTextStyle: TextStyle(color: AppColors.inkSecondary, fontSize: 12),
        labelType: NavigationRailLabelType.all,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.accentSoft,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) =>
              IconThemeData(color: states.contains(WidgetState.selected) ? AppColors.accent : AppColors.inkSecondary),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.track,
        linearMinHeight: 6,
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
