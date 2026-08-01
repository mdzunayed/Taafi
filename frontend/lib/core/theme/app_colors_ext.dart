import 'package:flutter/material.dart';

/// Semantic, theme-reactive color tokens that Material's [ColorScheme] does not
/// natively model.
///
/// Material gives us `primary`, `surface`, `onSurface`, etc. — but the app has
/// a richer vocabulary: a *canvas* that sits behind cards, a *raised* surface
/// for nested chrome, distinct title/body/muted typography colors, a reserved
/// high-contrast *accent* (orange) used only for active nav + high-priority
/// badges, a translucent *glow*, tuned status tints, and the promo-card
/// gradient stops. Modeling these as a [ThemeExtension] means every widget can
/// read `context.appColors.<token>` and get the correct light/dark value with
/// zero per-screen branching — and because [lerp] is implemented, a theme flip
/// animates smoothly instead of snapping.
///
/// The two canonical instances live in [AppColors.lightTokens] /
/// [AppColors.darkTokens] and are attached to the two [ThemeData]s in
/// `mt_theme.dart` via `extensions: [...]`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  /// Deep canvas that sits behind the whole scroll body / scaffold.
  final Color canvas;

  /// Primary card + panel surface.
  final Color surface;

  /// A slightly raised surface for nested chrome (avatars, inner chips, header
  /// bands) so layered elements separate from the base [surface].
  final Color surfaceHi;

  /// Hairline border for cards / chips / outlined containers.
  final Color cardBorder;

  /// Crisp high-contrast title / heading text.
  final Color title;

  /// Readable secondary body / subtitle text.
  final Color body;

  /// Dim muted captions / tertiary text.
  final Color muted;

  /// Core brand accent (violet). Mirrors `ColorScheme.primary` but is exposed
  /// here for the many call sites that read a raw brand color off the palette.
  final Color brand;

  /// Reserved vibrant orange, used **only** for active navigation states and
  /// high-priority badges — never as a general fill.
  final Color accent;

  /// Foreground painted on top of [accent] (glyphs, labels).
  final Color onAccent;

  /// Translucent brand glow for neon outlines / avatar rings / active shadows.
  final Color glow;

  /// Positive / success tint + its soft background.
  final Color positive;
  final Color positiveBg;

  /// Danger / error tint + its soft background.
  final Color danger;
  final Color dangerBg;

  /// Informational / scheduled tint (blue) + its soft background. Used by
  /// status chips ("Scheduled", "En route") on the provider dashboards.
  final Color info;
  final Color infoBg;

  /// Warning / attention tint (amber) + its soft background. Used by
  /// verification badges and "awaiting" status chips.
  final Color warning;
  final Color warningBg;

  /// Two-stop gradient used to complement the canvas behind promo-card chrome
  /// and hero surfaces. (Per-banner gradients from the API stay data-driven;
  /// this is the neutral fallback / chrome tone.)
  final List<Color> promoGradient;

  const AppColors({
    required this.canvas,
    required this.surface,
    required this.surfaceHi,
    required this.cardBorder,
    required this.title,
    required this.body,
    required this.muted,
    required this.brand,
    required this.accent,
    required this.onAccent,
    required this.glow,
    required this.positive,
    required this.positiveBg,
    required this.danger,
    required this.dangerBg,
    required this.info,
    required this.infoBg,
    required this.warning,
    required this.warningBg,
    required this.promoGradient,
  });

  /// Light theme tokens — fresh studio slate canvas, pristine white surfaces,
  /// violet brand, orange-rust accent tuned for contrast on white.
  static const AppColors lightTokens = AppColors(
    canvas: Color(0xFFF8FAFC),
    surface: Color(0xFFFFFFFF),
    surfaceHi: Color(0xFFF1F5F9),
    cardBorder: Color(0xFFE2E8F0),
    title: Color(0xFF0F172A),
    body: Color(0xFF475569),
    muted: Color(0xFF94A3B8),
    brand: Color(0xFF673AB7),
    accent: Color(0xFFE05300),
    onAccent: Color(0xFFFFFFFF),
    glow: Color(0x29673AB7), // violet @ ~16%
    positive: Color(0xFF059669),
    positiveBg: Color(0xFFDCF3E7),
    danger: Color(0xFFDC2626),
    dangerBg: Color(0xFFFEE2E2),
    info: Color(0xFF2563EB),
    infoBg: Color(0xFFDBEAFE),
    warning: Color(0xFFB45309),
    warningBg: Color(0xFFFEF3C7),
    promoGradient: [Color(0xFF7C4DFF), Color(0xFF673AB7)],
  );

  /// Dark theme tokens — midnight-charcoal canvas, obsidian slate surfaces,
  /// royal-indigo brand, vibrant sunset-orange accent, lavender-grey body.
  static const AppColors darkTokens = AppColors(
    canvas: Color(0xFF0D151C),
    surface: Color(0xFF161F26),
    surfaceHi: Color(0xFF1E2536),
    cardBorder: Color(0xFF283040),
    title: Color(0xFFFFFFFF),
    body: Color(0xFF94A3B8),
    muted: Color(0xFF6B7488),
    brand: Color(0xFF7C4DFF),
    accent: Color(0xFFF36512),
    onAccent: Color(0xFFFFFFFF),
    glow: Color(0x477C4DFF), // royal indigo @ ~28%
    positive: Color(0xFF34D399),
    positiveBg: Color(0xFF10291F),
    danger: Color(0xFFF87171),
    dangerBg: Color(0xFF2A1416),
    info: Color(0xFF60A5FA),
    infoBg: Color(0xFF13233F),
    warning: Color(0xFFFBBF24),
    warningBg: Color(0xFF2A2110),
    promoGradient: [Color(0xFF8B5CF6), Color(0xFF4C1D95)],
  );

  @override
  AppColors copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceHi,
    Color? cardBorder,
    Color? title,
    Color? body,
    Color? muted,
    Color? brand,
    Color? accent,
    Color? onAccent,
    Color? glow,
    Color? positive,
    Color? positiveBg,
    Color? danger,
    Color? dangerBg,
    Color? info,
    Color? infoBg,
    Color? warning,
    Color? warningBg,
    List<Color>? promoGradient,
  }) {
    return AppColors(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceHi: surfaceHi ?? this.surfaceHi,
      cardBorder: cardBorder ?? this.cardBorder,
      title: title ?? this.title,
      body: body ?? this.body,
      muted: muted ?? this.muted,
      brand: brand ?? this.brand,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      glow: glow ?? this.glow,
      positive: positive ?? this.positive,
      positiveBg: positiveBg ?? this.positiveBg,
      danger: danger ?? this.danger,
      dangerBg: dangerBg ?? this.dangerBg,
      info: info ?? this.info,
      infoBg: infoBg ?? this.infoBg,
      warning: warning ?? this.warning,
      warningBg: warningBg ?? this.warningBg,
      promoGradient: promoGradient ?? this.promoGradient,
    );
  }

  @override
  AppColors lerp(covariant ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHi: Color.lerp(surfaceHi, other.surfaceHi, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      title: Color.lerp(title, other.title, t)!,
      body: Color.lerp(body, other.body, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
      positive: Color.lerp(positive, other.positive, t)!,
      positiveBg: Color.lerp(positiveBg, other.positiveBg, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerBg: Color.lerp(dangerBg, other.dangerBg, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoBg: Color.lerp(infoBg, other.infoBg, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningBg: Color.lerp(warningBg, other.warningBg, t)!,
      promoGradient: [
        for (var i = 0; i < promoGradient.length; i++)
          Color.lerp(
            promoGradient[i],
            other.promoGradient[i.clamp(0, other.promoGradient.length - 1)],
            t,
          )!,
      ],
    );
  }
}

/// Terse accessor so widgets can write `context.appColors.canvas` instead of
/// `Theme.of(context).extension<AppColors>()!.canvas`. Non-null by contract:
/// both app themes always attach the extension.
extension AppColorsX on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}
