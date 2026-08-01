import 'package:flutter/material.dart';
import 'app_colors_ext.dart';
import 'mt_colors.dart';
import 'mt_text_styles.dart';

/// Builds the two canonical [ThemeData]s for the app. The public entry point is
/// [AppThemes] (see `app_themes.dart`); these factories remain the single
/// source of truth and still accept an optional [primaryColor] so a future
/// brand-palette switcher can re-theme without a rebuild of this file.
///
/// Both themes attach an [AppColors] extension carrying the semantic tokens
/// (canvas / surface / title / accent / …) that `ColorScheme` doesn't model —
/// read them via `context.appColors`.
class MtTheme {
  static ThemeData light({Color? primaryColor}) {
    const tokens = AppColors.lightTokens;
    final brandColor = primaryColor ?? tokens.brand;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: tokens.canvas,
      primaryColor: brandColor,
      extensions: const [tokens],
      colorScheme: ColorScheme.light(
        primary: brandColor,
        secondary: MtColors.violet600,
        tertiary: MtColors.violet700,
        surface: tokens.surface,
        error: tokens.danger,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onTertiary: Colors.white,
        onSurface: tokens.title,
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.surface,
        foregroundColor: tokens.title,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: MtTextStyles.h2.copyWith(color: tokens.title),
      ),
      buttonTheme: ButtonThemeData(
        buttonColor: brandColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brandColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: MtTextStyles.labelLg.copyWith(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.title,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: MtTextStyles.labelLg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: BorderSide(color: tokens.cardBorder),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brandColor,
          textStyle: MtTextStyles.labelLg,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.surfaceHi,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: tokens.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: tokens.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: brandColor, width: 2),
        ),
        hintStyle: MtTextStyles.bodyMd.copyWith(color: tokens.muted),
        labelStyle: MtTextStyles.bodyMd.copyWith(color: tokens.body),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: tokens.surface,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: MtTextStyles.labelMd.copyWith(color: tokens.body),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: tokens.cardBorder),
        ),
      ),
      cardTheme: CardThemeData(
        color: tokens.surface,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.02),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: tokens.cardBorder),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: tokens.cardBorder,
        thickness: 1,
        space: 16,
      ),
      textTheme: _textTheme(
        title: tokens.title,
        body: tokens.body,
        muted: tokens.muted,
      ),
    );
  }

  static ThemeData dark({Color? primaryColor}) {
    const tokens = AppColors.darkTokens;
    final brandColor = primaryColor ?? tokens.brand;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: tokens.canvas,
      primaryColor: brandColor,
      extensions: const [tokens],
      colorScheme: ColorScheme.dark(
        primary: brandColor,
        secondary: MtColors.violetBright,
        tertiary: MtColors.violet600,
        surface: tokens.surface,
        error: tokens.danger,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onTertiary: Colors.white,
        onSurface: tokens.title,
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.surface,
        foregroundColor: tokens.title,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: MtTextStyles.h2.copyWith(color: tokens.title),
      ),
      buttonTheme: ButtonThemeData(
        buttonColor: brandColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brandColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: MtTextStyles.labelLg.copyWith(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.title,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: MtTextStyles.labelLg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: BorderSide(color: tokens.cardBorder),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: MtColors.violetBright,
          textStyle: MtTextStyles.labelLg,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.surfaceHi,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: tokens.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: tokens.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: brandColor, width: 2),
        ),
        hintStyle: MtTextStyles.bodyMd.copyWith(color: tokens.muted),
        labelStyle: MtTextStyles.bodyMd.copyWith(color: tokens.body),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: tokens.surfaceHi,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: MtTextStyles.labelMd.copyWith(color: tokens.body),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: tokens.cardBorder),
        ),
      ),
      cardTheme: CardThemeData(
        color: tokens.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: tokens.cardBorder),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: tokens.cardBorder,
        thickness: 1,
        space: 16,
      ),
      textTheme: _textTheme(
        title: tokens.title,
        body: tokens.body,
        muted: tokens.muted,
      ),
    );
  }

  /// Shared text-theme mapping so the light + dark themes stay structurally
  /// identical and only differ by the three passed-in ink colors.
  static TextTheme _textTheme({
    required Color title,
    required Color body,
    required Color muted,
  }) {
    return TextTheme(
      displayLarge: MtTextStyles.displayLg.copyWith(color: title),
      headlineLarge: MtTextStyles.h1.copyWith(color: title),
      headlineMedium: MtTextStyles.h2.copyWith(color: title),
      headlineSmall: MtTextStyles.h3.copyWith(color: title),
      titleLarge: MtTextStyles.sectionLabel.copyWith(color: muted),
      bodyLarge: MtTextStyles.bodyLg.copyWith(color: body),
      bodyMedium: MtTextStyles.bodyMd.copyWith(color: body),
      bodySmall: MtTextStyles.bodySm.copyWith(color: muted),
      labelLarge: MtTextStyles.labelLg.copyWith(color: title),
      labelMedium: MtTextStyles.labelMd.copyWith(color: body),
      labelSmall: MtTextStyles.labelSm.copyWith(color: muted),
    );
  }
}
