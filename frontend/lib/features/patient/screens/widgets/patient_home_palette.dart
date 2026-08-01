import 'package:flutter/material.dart';

/// Theme-resolved palette for the patient Home surface, its shared fluid nav
/// bar/tray, the booking flow, and the notification tray.
///
/// This used to be a **static, dark-only** token set (`HomeDark.canvas`, …).
/// It is now a resolver: [HomeDark.of] returns the light or dark instance for
/// the ambient [Brightness], so the whole patient dashboard flips with the app
/// theme. The token *names* are unchanged, so call sites only need a local
/// `final hd = HomeDark.of(context);` and then `hd.canvas`, `hd.violet`, etc.
///
/// The violet gradient tones stay vivid in both themes (promo/hero cards paint
/// white text directly on them), while neutral chrome (canvas/surface/title/
/// body/muted/border) swaps to a light equivalent under the light theme.
@immutable
class HomeDark {
  /// Deep near-black canvas (dark) / fresh studio slate (light).
  final Color canvas;

  /// Card surface + a slightly raised variant for nested chrome.
  final Color surface;
  final Color surfaceHi;

  /// Core violet accent + its glossy top / neon / deep-gradient siblings.
  final Color violet;
  final Color violet2;
  final Color violetBright;
  final Color violetDeep;

  /// Brand-orange accent (active category chip, high-priority actions) +
  /// its translucent glow. Mirrors `AppColors.accent` / `accentGlow`.
  final Color accent;
  final Color accentGlow;

  /// Indigo (live "ON THE WAY" capsule) + emerald-teal (quick-add "+").
  final Color indigo;
  final Color teal;

  /// Hairline border + a translucent violet glow.
  final Color border;
  final Color glow;

  /// Typography: crisp titles, readable body, dim muted captions.
  final Color title;
  final Color body;
  final Color muted;

  /// Status tints for the ongoing-care pill.
  final Color positive;
  final Color positiveBg;
  final Color danger;
  final Color dangerBg;

  const HomeDark._({
    required this.canvas,
    required this.surface,
    required this.surfaceHi,
    required this.violet,
    required this.violet2,
    required this.violetBright,
    required this.violetDeep,
    required this.accent,
    required this.accentGlow,
    required this.indigo,
    required this.teal,
    required this.border,
    required this.glow,
    required this.title,
    required this.body,
    required this.muted,
    required this.positive,
    required this.positiveBg,
    required this.danger,
    required this.dangerBg,
  });

  /// The original midnight/violet dark palette.
  static const HomeDark _dark = HomeDark._(
    canvas: Color(0xFF0D151C),
    surface: Color(0xFF161C28),
    surfaceHi: Color(0xFF1E2536),
    violet: Color(0xFF7C3AED),
    violet2: Color(0xFF8B5CF6),
    violetBright: Color(0xFFA78BFA),
    violetDeep: Color(0xFF4C1D95),
    accent: Color(0xFFF36512),
    accentGlow: Color(0x47F36512), // orange @ ~28%
    indigo: Color(0xFF6366F1),
    teal: Color(0xFF2DD4BF),
    border: Color(0xFF283040),
    glow: Color(0x477C3AED), // violet @ ~28%
    title: Color(0xFFF4F5FA),
    body: Color(0xFFAAB2C5),
    muted: Color(0xFF6B7488),
    positive: Color(0xFF34D399),
    positiveBg: Color(0xFF10291F),
    danger: Color(0xFFF87171),
    dangerBg: Color(0xFF2A1416),
  );

  /// Light-theme equivalent — clean slate canvas + white surfaces, with the
  /// violet family kept vivid so gradient cards still pop.
  static const HomeDark _light = HomeDark._(
    canvas: Color(0xFFF8FAFC),
    surface: Color(0xFFFFFFFF),
    surfaceHi: Color(0xFFF1F5F9),
    violet: Color(0xFF673AB7),
    violet2: Color(0xFF7C4DFF),
    violetBright: Color(0xFF7C3AED),
    violetDeep: Color(0xFF512DA8),
    accent: Color(0xFFE05300),
    accentGlow: Color(0x29E05300), // orange @ ~16%
    indigo: Color(0xFF4F46E5),
    teal: Color(0xFF0D9488),
    border: Color(0xFFE2E8F0),
    glow: Color(0x29673AB7), // violet @ ~16%
    title: Color(0xFF0F172A),
    body: Color(0xFF475569),
    muted: Color(0xFF94A3B8),
    positive: Color(0xFF059669),
    positiveBg: Color(0xFFDCF3E7),
    danger: Color(0xFFDC2626),
    dangerBg: Color(0xFFFEE2E2),
  );

  /// Resolve the palette for the ambient theme brightness.
  static HomeDark of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;
}
