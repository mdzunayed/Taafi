import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/home_data_providers.dart';
import '../../../../core/models/home_category.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/widgets/mt_skeleton.dart';
import 'category_selection.dart';
import 'patient_home_palette.dart';

// The selection state moved to `category_selection.dart` so the dedicated
// category view can read it without importing this widget. It is re-exported
// here because every existing call site reaches `selectedCategorySlugProvider`
// through this import.
export 'category_selection.dart';

/// Height of the rail. Fits the two-line pill a category with a Bengali name
/// renders; single-line pills centre inside the same box, so a mixed rail
/// still has one baseline.
const double kCategoryRailHeight = 46;

/// Horizontal, edge-to-edge rail of selectable category pills, fed live from
/// `/api/home-data`.
///
/// The "All" pill at index 0 is implicit — it is prepended here rather than
/// stored, because a pill an admin can delete is one that can strand a patient
/// in a filtered view with no way back to the full catalog.
///
/// Tapping calls [selectCategory], which writes [selectedCategorySlugProvider]
/// and resets [categoryFiltersProvider]. Home then swaps between the full
/// dashboard ("All") and the dedicated `CategoryServicesView`. Nothing here
/// triggers a fetch, so switching categories never reloads the screen.
///
/// The rail is rendered **inside the sticky header** on Home rather than in the
/// scroll body: it is the only way back out of a category view, so it must not
/// be something the patient can scroll away from.
class CategoryFilterBar extends ConsumerWidget {
  /// Rail height. Defaults to [kCategoryRailHeight]; Home overrides it with a
  /// text-scale-adjusted value so the rail and the slot its sticky header
  /// reserved for it stay the same size. A caller that lays the rail out
  /// inside a box of its own must pass the same number it reserved — the two
  /// drifting apart is what overflows the header.
  final double height;

  const CategoryFilterBar({super.key, this.height = kCategoryRailHeight});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(patientHomeDataProvider);
    final selected = ref.watch(selectedCategorySlugProvider);

    return SizedBox(
      height: height,
      child: async.when(
        loading: () => const _CategoryRailSkeleton(),
        // The repository degrades rather than erroring, so this branch is
        // effectively unreachable — but if it ever fires, the rail collapses
        // instead of putting a retry card above the fold.
        error: (_, _) => const SizedBox.shrink(),
        data: (data) {
          final categories = [HomeCategory.all, ...data.railCategories];
          // A pill that was selected and has since been hidden or deleted in
          // the CMS would otherwise leave the rail with nothing highlighted
          // and the cards filtered to empty. Fall back to "All".
          final active = categories.any((c) => c.slug == selected)
              ? selected
              : HomeCategory.allSlug;

          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final category = categories[i];
              return CategoryPill(
                category: category,
                active: category.slug == active,
                onTap: () => selectCategory(ref, category.slug),
              );
            },
          );
        },
      ),
    );
  }
}

/// One pill. Active is a filled brand-orange capsule with a glow; inactive is
/// a hairline-bordered surface capsule — the same two states the hardcoded
/// rail had, so the surface doesn't visibly change on upgrade.
///
/// Public so the admin CMS previews the real pill rather than a lookalike; a
/// preview that paints its own chip drifts from the app the moment either side
/// moves. See `admin/widgets/home_pill_preview.dart`.
class CategoryPill extends StatelessWidget {
  final HomeCategory category;
  final bool active;
  final VoidCallback onTap;

  const CategoryPill({
    super.key,
    required this.category,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final nameBn = category.nameBn?.trim();
    final hasBn = nameBn != null && nameBn.isNotEmpty;
    final fg = active ? Colors.white : hd.body;

    return Semantics(
      button: true,
      selected: active,
      // Both scripts, so a screen reader announces what the pill says in
      // either language even though the capsule only has room for one line
      // when the admin left the Bengali name blank.
      label: hasBn ? '${category.nameEn}, $nameBn' : category.nameEn,
      child: Material(
        color: active ? hd.accent : hd.surface,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: active ? hd.accent : hd.border),
              boxShadow:
                  active ? [BoxShadow(color: hd.accentGlow, blurRadius: 12)] : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (category.iconUrl != null) ...[
                  _PillIcon(url: category.iconUrl!, tint: fg),
                  const SizedBox(width: 7),
                ],
                Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.nameEn,
                      style: MtTextStyles.labelMd.copyWith(
                        color: fg,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                        height: 1.1,
                      ),
                    ),
                    if (hasBn)
                      Text(
                        nameBn,
                        style: MtTextStyles.labelSm.copyWith(
                          color: active
                              ? Colors.white.withValues(alpha: 0.85)
                              : hd.muted,
                          fontFamily: 'Kalpurush',
                          fontSize: 10,
                          height: 1.2,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The optional admin-supplied pill glyph. Sized to the label, and it
/// disappears rather than degrading to a broken-image box — an icon is
/// decoration here, the label carries the meaning.
class _PillIcon extends StatelessWidget {
  final String url;
  final Color tint;
  const _PillIcon({required this.url, required this.tint});

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      width: 16,
      height: 16,
      fit: BoxFit.contain,
      // A monochrome glyph picks up the pill's foreground so it stays legible
      // on both the filled and the outlined state; a full-colour icon is
      // unaffected in practice because the blend only lifts alpha.
      color: tint,
      colorBlendMode: BlendMode.srcIn,
      placeholder: (_, _) => const SizedBox(width: 16, height: 16),
      errorWidget: (_, _, _) => const SizedBox.shrink(),
    );
  }
}

/// Placeholder pills shown while the first payload loads. Mirrors the real
/// rail's silhouette so the switch to live categories doesn't reflow the row.
class _CategoryRailSkeleton extends StatelessWidget {
  const _CategoryRailSkeleton();

  static const _widths = [58.0, 92.0, 128.0, 84.0];

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _widths.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, i) => Center(
        child: MtSkeleton.box(width: _widths[i], height: 38, radius: 999),
      ),
    );
  }
}
