import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors_ext.dart';

/// Theme-reactive color resolver shared by every chat surface — the
/// full-screen [ChatScreen] and the slide-in `ActiveChatDrawer` both build
/// one per `build` via `ChatPalette.of(context)`.
///
/// Field names mirror the legacy `MtColors` tokens (so the original chat
/// screen migrated with a mechanical swap), but every value now comes from
/// the light/dark [AppColors] extension — this is what flips the whole
/// surface to the dark obsidian canvas (`#0D151C`) with the vibrant
/// `#F36512` orange accent.
class ChatPalette {
  final Color bg;
  final Color surface;
  final Color surfaceHi;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color line;
  final Color brand;
  final Color brandSoft;
  final Color brandSofter;
  final Color onBrand;

  const ChatPalette({
    required this.bg,
    required this.surface,
    required this.surfaceHi,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.line,
    required this.brand,
    required this.brandSoft,
    required this.brandSofter,
    required this.onBrand,
  });

  factory ChatPalette.of(BuildContext context) {
    final a = context.appColors;
    return ChatPalette(
      bg: a.canvas,
      surface: a.surface,
      surfaceHi: a.surfaceHi,
      ink: a.title,
      ink2: a.body,
      ink3: a.muted,
      line: a.cardBorder,
      brand: a.accent,
      brandSoft: a.accent.withValues(alpha: 0.28),
      brandSofter: a.accent.withValues(alpha: 0.12),
      onBrand: a.onAccent,
    );
  }
}
