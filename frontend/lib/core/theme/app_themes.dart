import 'package:flutter/material.dart';
import 'mt_colors.dart';
import 'mt_theme.dart';

/// Public, named entry point for the app's two themes.
///
/// This is a thin façade over [MtTheme] (the single source of truth) so
/// screens and `main.dart` can reference `AppThemes.lightTheme` /
/// `AppThemes.darkTheme` directly. Both carry the violet brand primary and the
/// [AppColors] extension; the reserved orange accent lives on that extension.
class AppThemes {
  const AppThemes._();

  static ThemeData get lightTheme => MtTheme.light(primaryColor: MtColors.violet);

  static ThemeData get darkTheme =>
      MtTheme.dark(primaryColor: MtColors.violetBright);
}
