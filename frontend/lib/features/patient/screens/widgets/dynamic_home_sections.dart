import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/home_section_providers.dart';
import '../../../../core/models/home_section.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../navigation/dynamic_route_dispatcher.dart';
import 'care_card_primitives.dart';
import 'care_service_card.dart';
import 'patient_home_palette.dart';
import 'staggered_animated_card.dart';

/// Server-driven section blocks rendered on the patient Home below the fixed
/// Banners + Care Services blocks.
///
/// Both horizontal templates (`HORIZONTAL_ROUND_AVATAR`,
/// `HORIZONTAL_PRODUCT_CARD`) render through [_DynamicCardRail], which builds
/// the very same [CareServiceCard] the Care Services section above uses — not
/// a lookalike. The grid and wide-banner templates keep their own layouts but
/// share the design tokens via [PressableCard], [CareCardImage] and
/// [CareCardCategoryBadge].
///
/// Every one of those primitives accepts the admin colour overrides carried on
/// `HomeSectionItem.cardStyles`, so a styled section still looks styled.
///
/// Sections whose template this app version doesn't know, or with no content,
/// are skipped — and while the list is loading or errored the whole block
/// collapses (like `_PromoCarousel`).
class DynamicHomeSections extends ConsumerWidget {
  const DynamicHomeSections({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sectionsAsync = ref.watch(activeHomeSectionsProvider);
    return sectionsAsync.maybeWhen(
      data: (sections) {
        // Hidden cards are already stripped server-side; re-filtering here
        // keeps a section from rendering as an empty block when the app is
        // talking to a backend that predates per-card visibility.
        final renderable = <HomeSection>[
          for (final s in sections)
            // CARE_SERVICES is reserved: it backs the Care Services block
            // above (which reads its title and `layoutType`), so rendering it
            // here as well would draw the block twice.
            if (!s.isCareServices &&
                s.isActive &&
                HomeSection.supportedTemplates.contains(s.uiTemplate))
              s.copyWith(
                contentData: [
                  for (final item in s.contentData)
                    if (item.isActive) item,
                ],
              ),
        ].where((s) => s.contentData.isNotEmpty).toList();
        if (renderable.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final section in renderable) _SectionBlock(section: section),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

final _dynamicMoneyFmt = NumberFormat('#,###', 'en_US');

/// Turns the freeform admin `priceTag` into the Care-Services price line.
/// Numeric content (e.g. "৳2400", "2400") → `৳ 2,400`, matching
/// [careServicePrice] so the two rails read identically; non-numeric text
/// (e.g. "Free") passes through verbatim; blank → null (line omitted).
String? dynamicPriceLine(String? tag) {
  final raw = tag?.trim();
  if (raw == null || raw.isEmpty) return null;
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  final n = int.tryParse(digits);
  if (n == null) return raw;
  return '৳ ${_dynamicMoneyFmt.format(n)}';
}

/// The card title, with its Bengali counterpart on a second line when the
/// admin supplied one.
///
/// There is no app-wide locale switch, so both scripts show at once — the same
/// treatment the section header already gives `titleBn`. Both title and
/// description slots on [CareServiceCard] allow exactly two lines, so the pair
/// fits without changing the card's silhouette.
///
/// Public so the CMS preview can compose its strings identically; a preview
/// that formats its own text drifts from the app the moment either side moves.
String dynamicCardTitle(HomeSectionItem item) =>
    _joinBilingual(item.title, item.titleBn);

/// The description line — the English subtitle over its Bengali counterpart.
/// Null until the admin sets an explicit badge, since on a legacy card the
/// subtitle is still the badge (see [HomeSectionItem.descriptionLine]).
String? dynamicCardDescription(HomeSectionItem item) {
  final en = item.descriptionLine;
  final bn = item.subtitleBn?.trim();
  if (en == null || en.isEmpty) return (bn == null || bn.isEmpty) ? null : bn;
  return _joinBilingual(en, bn);
}

String _joinBilingual(String en, String? bn) {
  final b = bn?.trim();
  return (b == null || b.isEmpty) ? en : '$en\n$b';
}

/// Header + template body + bottom gap for one section. The 24 px bottom gap
/// matches the spacing rhythm of the fixed blocks above.
class _SectionBlock extends ConsumerWidget {
  final HomeSection section;
  const _SectionBlock({required this.section});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hd = HomeDark.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Admin overrides fall back to the theme token when unset.
    final titleColor = section.styleTokens?.title(dark) ?? hd.body;
    final sectionBg = section.styleTokens?.background;
    // Structured target (service link / route / URL) configured by the admin
    // in the CMS — a SERVICE item opens the booking flow pre-selected.
    void onItemTap(HomeSectionItem item) => dispatchHomeItemTarget(ref, item);

    final Widget body;
    switch (section.uiTemplate) {
      // Both horizontal templates unify onto the Care-Services-style rail.
      case HomeSection.templateHorizontalRoundAvatar:
      case HomeSection.templateHorizontalProductCard:
        body = _DynamicCardRail(
          items: section.contentData,
          onItemTap: onItemTap,
        );
      case HomeSection.templateGrid2x2Tiles:
        body = _Grid2x2Tiles(
          items: section.contentData,
          onItemTap: onItemTap,
        );
      case HomeSection.templateSingleWideBanner:
        body = _SingleWideBanner(
          item: section.contentData.first,
          onItemTap: onItemTap,
        );
      default:
        return const SizedBox.shrink();
    }

    final block = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                section.titleEn.toUpperCase(),
                style: MtTextStyles.sectionLabel.copyWith(
                  color: titleColor,
                  letterSpacing: 1.0,
                ),
              ),
              if (section.titleBn != null && section.titleBn!.isNotEmpty)
                Text(
                  section.titleBn!,
                  style: MtTextStyles.sectionLabel.copyWith(
                    color: hd.muted,
                    fontFamily: 'Kalpurush',
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        body,
        const SizedBox(height: 24),
      ],
    );

    // An admin section background paints a full-width band behind the block.
    return sectionBg != null ? ColoredBox(color: sectionBg, child: block) : block;
  }
}

/// The horizontal rail — the same geometry and the same [CareServiceCard] the
/// Care Services section uses: on mobile a flush-edge rail (the 16px inset
/// lives inside the ListView so the first card rests on the section-header
/// line and cards clip flush to the screen edge mid-swipe), on wide layouts
/// (≥700px) the same fluid grid it switches to.
class _DynamicCardRail extends StatelessWidget {
  final List<HomeSectionItem> items;
  final ValueChanged<HomeSectionItem> onItemTap;

  const _DynamicCardRail({required this.items, required this.onItemTap});

  Widget _card(BuildContext context, HomeSectionItem item) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final styles = item.cardStyles;
    final accent = styles?.accent(dark);
    return CareServiceCard(
      title: dynamicCardTitle(item),
      // Once the admin sets an explicit badge, `subtitle` is freed to become a
      // real description line; on a legacy card it is still the badge and
      // `descriptionLine` stays null. See [HomeSectionItem.badgeLabel].
      description: dynamicCardDescription(item),
      categoryLabel: item.badgeLabel,
      priceLabel: dynamicPriceLine(item.priceTag),
      imageUrl: item.imageUrl,
      onTap: () => onItemTap(item),
      cardColor: styles?.cardBg(dark),
      glowColor: accent,
      badgeColor: styles?.tagBg,
      badgeTextColor: styles?.tagText,
      ctaColor: accent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 700) {
      final cols = width >= 1000 ? 3 : 2;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: careServiceGridAspectRatio(cols),
          ),
          itemCount: items.length,
          itemBuilder: (context, i) => StaggeredAnimatedCard(
            index: i,
            child: _card(context, items[i]),
          ),
        ),
      );
    }

    return SizedBox(
      height: kCareServiceCardRailHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) => SizedBox(
          width: kCareServiceCardWidth,
          child: StaggeredAnimatedCard(
            index: i,
            child: _card(context, items[i]),
          ),
        ),
      ),
    );
  }
}

// --- Grid + banner templates (layouts kept, tokens unified) ------------------

/// GRID_2X2_TILES — inset two-column grid of image tiles. Same geometry as
/// before, restyled onto [_PressableCard] (radius 24, violet glow, press
/// spring) with the subtitle promoted to the standard category capsule.
class _Grid2x2Tiles extends StatelessWidget {
  final List<HomeSectionItem> items;
  final ValueChanged<HomeSectionItem> onItemTap;

  const _Grid2x2Tiles({required this.items, required this.onItemTap});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.45,
        children: [
          for (final item in items)
            PressableCard(
              onTap: () => onItemTap(item),
              cardColor: item.cardStyles?.cardBg(dark),
              glowColor: item.cardStyles?.accent(dark),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CareCardImage(url: item.imageUrl, fallbackIcon: Icons.image_outlined),
                  if (item.badgeLabel != null)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: CareCardCategoryBadge(
                        label: item.badgeLabel!,
                        accent: ServiceCategoryTheme.accentFor(
                            context, item.badgeLabel),
                        background: item.cardStyles?.tagBg,
                        textColor: item.cardStyles?.tagText,
                      ),
                    ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black87],
                        ),
                      ),
                      child: Text(
                        dynamicCardTitle(item),
                        // Two lines so an admin-supplied Bengali title lands
                        // under the English one instead of being clipped.
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: MtTextStyles.labelLg
                            .copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// SINGLE_WIDE_BANNER — one inset full-width promotional image (first item
/// only). Same layout as before, restyled onto [_PressableCard] with the
/// subtitle promoted to the category capsule and an optional price line.
class _SingleWideBanner extends StatelessWidget {
  final HomeSectionItem item;
  final ValueChanged<HomeSectionItem> onItemTap;

  const _SingleWideBanner({required this.item, required this.onItemTap});

  @override
  Widget build(BuildContext context) {
    final priceLine = dynamicPriceLine(item.priceTag);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 140,
        child: PressableCard(
          onTap: () => onItemTap(item),
          cardColor: item.cardStyles?.cardBg(dark),
          glowColor: item.cardStyles?.accent(dark),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CareCardImage(url: item.imageUrl, fallbackIcon: Icons.image_outlined),
              if (item.badgeLabel != null)
                Positioned(
                  left: 8,
                  top: 8,
                  child: CareCardCategoryBadge(
                    label: item.badgeLabel!,
                    accent:
                        ServiceCategoryTheme.accentFor(context, item.badgeLabel),
                    background: item.cardStyles?.tagBg,
                    textColor: item.cardStyles?.tagText,
                  ),
                ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 20, 14, 12),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dynamicCardTitle(item),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: MtTextStyles.h3.copyWith(color: Colors.white),
                      ),
                      if (priceLine != null)
                        Text(
                          priceLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MtTextStyles.timer.copyWith(
                            color: Colors.white70,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
