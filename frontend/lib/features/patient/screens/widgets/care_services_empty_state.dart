import 'package:flutter/material.dart';

import '../../../../core/models/service_category.dart';
import '../../../../core/theme/mt_text_styles.dart';
import 'care_card_primitives.dart';
import 'patient_home_palette.dart';

/// Shown under CARE SERVICES when the selected category has nothing to render.
///
/// Deliberately *not* the shared [MtEmptyState]: that widget paints from the
/// legacy static `MtColors` palette, which is not theme-aware, so it renders a
/// near-white card in the middle of the dark Home canvas. This one resolves
/// [HomeDark] like every other widget on this surface, tints itself with the
/// category's own accent, and — unlike the old branch — offers a way back out
/// of the filter.
class CareServicesEmptyState extends StatelessWidget {
  /// The active chip, so the copy can name it.
  final String category;

  /// Resets the filter to [kServiceCategoryAll]. Null hides the action, which
  /// is what the 'All' chip itself wants (there is nowhere to reset to).
  final VoidCallback? onShowAll;

  const CareServicesEmptyState({
    super.key,
    required this.category,
    this.onShowAll,
  });

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final isAll = category == kServiceCategoryAll;
    final accent =
        ServiceCategoryTheme.accentFor(context, category) ?? hd.violetBright;

    final title =
        isAll ? 'No services available yet' : 'No $category services yet';
    final subtitle = isAll
        ? 'Check back soon — new services are added regularly.'
        : 'Try another category, or check back soon.';

    return Semantics(
      container: true,
      label: '$title. $subtitle',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        decoration: BoxDecoration(
          color: hd.surface,
          // Matches the cards this stands in for.
          borderRadius: BorderRadius.circular(kCareCardRadius),
          border: Border.all(color: hd.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Glyph(
              icon: serviceIconFor(isAll ? '' : category, ''),
              accent: accent,
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: MtTextStyles.labelLg.copyWith(color: hd.title),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: MtTextStyles.bodySm.copyWith(color: hd.muted),
            ),
            if (!isAll && onShowAll != null) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: onShowAll,
                style: TextButton.styleFrom(foregroundColor: accent),
                child: Text(
                  'Show all services',
                  style: MtTextStyles.labelMd.copyWith(color: accent),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The tinted glyph tile, with a soft accent bloom behind it. Scales and fades
/// in once so switching to an empty category feels like a state change rather
/// than a blank frame.
class _Glyph extends StatelessWidget {
  final IconData icon;
  final Color accent;

  const _Glyph({required this.icon, required this.accent});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      // Keyed by accent so a category switch replays the entrance.
      key: ValueKey(accent),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.90 + 0.10 * t, child: child),
      ),
      child: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.22),
              blurRadius: 36,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Icon(icon, color: accent, size: 26),
      ),
    );
  }
}
