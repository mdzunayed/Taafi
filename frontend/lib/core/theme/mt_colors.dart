import 'package:flutter/material.dart';

class MtColors {
  // Brand color palette - Care Orange (default)
  static const Color brand = Color(0xFFEA580C);
  static const Color brandSoft = Color(0xFFFCE3D2);
  static const Color brandSofter = Color(0xFFFEF6ED);
  static const Color brandInk = Color(0xFF5A230A);
  static const Color brand600 = Color(0xFFC2410C);
  static const Color brand700 = Color(0xFF9A3412);

  // Active brand identity (violet primary + reserved orange accent).
  // These drive the light/dark ThemeData in mt_theme.dart. The legacy Care
  // Orange tokens above are retained for screens not yet migrated to the
  // theme-aware AppColors extension (see the follow-up sweep).
  static const Color violet = Color(0xFF673AB7); // brand primary (light)
  static const Color violetBright = Color(0xFF7C4DFF); // brand primary (dark)
  static const Color violet600 = Color(0xFF5E35B1);
  static const Color violet700 = Color(0xFF512DA8);
  static const Color accentLight = Color(0xFFE05300); // orange-rust on white
  static const Color accentDark = Color(0xFFF36512); // vibrant sunset orange

  // Neutral/Surface colors
  static const Color ink = Color(0xFF0F172A);
  static const Color ink2 = Color(0xFF475569);
  static const Color ink3 = Color(0xFF94A3B8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surface2 = Color(0xFFF8FAFC);
  static const Color bg = Color(0xFFF1F5F9);
  static const Color line = Color(0xFFE2E8F0);

  // Status colors
  static const Color pending = Color(0xFFEA580C);
  static const Color pendingBg = Color(0xFFFCE3D2);
  static const Color completed = Color(0xFF059669);
  static const Color completedBg = Color(0xFFDCF3E7);
  static const Color rejected = Color(0xFFDC2626);
  static const Color rejectedBg = Color(0xFFFEE2E2);

  // Additional brand palettes (for theme switching)
  static const Map<String, BrandPalette> palettes = {
    'teal': BrandPalette(
      base: Color(0xFF0B8F87),
      dark: Color(0xFF2DD4BF),
      soft: Color(0xFFE6F5F3),
      softer: Color(0xFFF4FAF9),
      ink: Color(0xFF083B37),
      v600: Color(0xFF087A72),
      v700: Color(0xFF065C56),
      name: 'Clinical Teal',
    ),
    'sapphire': BrandPalette(
      base: Color(0xFF1D4ED8),
      dark: Color(0xFF60A5FA),
      soft: Color(0xFFE5EDFB),
      softer: Color(0xFFF4F7FE),
      ink: Color(0xFF0F2461),
      v600: Color(0xFF1940BA),
      v700: Color(0xFF112E85),
      name: 'Sapphire',
    ),
    'violet': BrandPalette(
      base: Color(0xFF7C3AED),
      dark: Color(0xFFA78BFA),
      soft: Color(0xFFEEE6FB),
      softer: Color(0xFFF8F4FE),
      ink: Color(0xFF2E1065),
      v600: Color(0xFF6B2BD1),
      v700: Color(0xFF52189E),
      name: 'Violet',
    ),
    'emerald': BrandPalette(
      base: Color(0xFF059669),
      dark: Color(0xFF34D399),
      soft: Color(0xFFDCF3E7),
      softer: Color(0xFFF1FAF5),
      ink: Color(0xFF033A28),
      v600: Color(0xFF047857),
      v700: Color(0xFF065F46),
      name: 'Emerald',
    ),
    'rose': BrandPalette(
      base: Color(0xFFDC2626),
      dark: Color(0xFFF87171),
      soft: Color(0xFFFBE1E1),
      softer: Color(0xFFFDF5F5),
      ink: Color(0xFF5C0F0F),
      v600: Color(0xFFB71C1C),
      v700: Color(0xFF8E1414),
      name: 'Rose',
    ),
    'orange': BrandPalette(
      base: Color(0xFFEA580C),
      dark: Color(0xFFFB923C),
      soft: Color(0xFFFCE3D2),
      softer: Color(0xFFFEF6ED),
      ink: Color(0xFF5A230A),
      v600: Color(0xFFC2410C),
      v700: Color(0xFF9A3412),
      name: 'Orange',
    ),
  };
}

class BrandPalette {
  final Color base;
  final Color dark;
  final Color soft;
  final Color softer;
  final Color ink;
  final Color v600;
  final Color v700;
  final String name;

  const BrandPalette({
    required this.base,
    required this.dark,
    required this.soft,
    required this.softer,
    required this.ink,
    required this.v600,
    required this.v700,
    required this.name,
  });
}
