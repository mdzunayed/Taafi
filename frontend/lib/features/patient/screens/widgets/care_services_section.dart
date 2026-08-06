import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/home_data_providers.dart';
import '../../../../core/api/service_catalog_providers.dart';
import '../../../../core/models/home_category.dart';
import '../../../../core/models/home_section.dart';
import '../../../../core/models/home_service_card.dart';
import '../../../../core/models/patient_home_data.dart';
import '../../../../core/models/service_catalog_item.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/widgets/mt_skeleton.dart';
import '../../navigation/patient_nav_provider.dart';
import '../../new_request/new_request_notifier.dart';
import 'care_card_primitives.dart';
import 'care_service_card.dart';
import 'care_services_empty_state.dart';
import 'category_filter_bar.dart';
import 'patient_home_palette.dart';
import 'staggered_animated_card.dart';

/// The Care Services block: header, then the admin's chosen layout, filtered
/// live by the active pill from [CategoryFilterBar].
///
/// **Layout engine.** `layoutType` comes from the CMS and picks one of three
/// arrangements of the same [CareServiceCard]:
///
///   * `CAROUSEL`   — the flush-edge swipeable rail Home has always had.
///   * `GRID_2_COL` — two per row, tiles the same 260px tall as the rail.
///   * `LIST`       — full-width horizontal rows ([_CareServiceListRow]).
///
/// **Card source.** Both branches produce [HomeServiceCard], so the layouts
/// never have to know where a card came from:
///
///   * `/api/home-data` normally supplies them, already projected from either
///     the live catalog or a curated `CARE_SERVICES` section.
///   * If that endpoint is unreachable — an older backend, a cold start
///     offline — the block falls back to `/api/services` and the compiled
///     chip rail, which is exactly what this screen rendered before the CMS
///     existed.
///
/// Filtering is pure and local: tapping a pill re-runs the `where` below and
/// nothing else. No fetch, no reload.
class CareServicesSection extends ConsumerWidget {
  const CareServicesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeAsync = ref.watch(patientHomeDataProvider);
    final catalogAsync = ref.watch(activeServicesProvider);
    final selected = ref.watch(selectedCategorySlugProvider);

    // Still waiting on the first payload — one skeleton for both sources.
    if (homeAsync.isLoading && !homeAsync.hasValue) {
      return const _CareServicesSkeleton();
    }
    final home = homeAsync.valueOrNull ?? PatientHomeData.fallback;
    final block = home.careServices;

    // The catalog is the fallback source AND the booking-prefill lookup, so it
    // is watched either way. Only the fallback path can surface its error:
    // when home-data is live the cards are already on screen and a catalog
    // failure just means a tap opens the booking form unfilled.
    final List<HomeServiceCard> cards;
    if (home.isLive) {
      cards = block.services;
    } else {
      if (catalogAsync.isLoading && !catalogAsync.hasValue) {
        return const _CareServicesSkeleton();
      }
      if (catalogAsync.hasError && !catalogAsync.hasValue) {
        return _Inset(
          child: _CatalogError(onRetry: () => refreshServiceCatalog(ref)),
        );
      }
      cards = [
        for (final item in catalogAsync.valueOrNull ?? const <ServiceCatalogItem>[])
          HomeServiceCard.fromCatalog(item),
      ];
    }

    // An admin can hide the whole block from the CMS.
    if (!block.isActive) return const SizedBox.shrink();

    final filtered = [
      for (final card in cards)
        if (card.matchesCategorySlug(selected)) card,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Inset(
          child: _SectionHeader(en: block.titleEn, bn: block.titleBn),
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          _Inset(
            child: CareServicesEmptyState(
              // Names the pill in the copy, so "No Nursing services yet" reads
              // as the admin wrote it rather than as a slug.
              category: _labelFor(home, selected),
              onShowAll: selected == HomeCategory.allSlug
                  ? null
                  : () => resetToAllCategories(ref),
            ),
          )
        else
          LayoutEngine(
            layoutType: block.layoutType,
            cards: filtered,
            onTap: (card) => _book(ref, card),
          ),
      ],
    );
  }

  /// The display name of the active pill, for the empty-state copy. Falls back
  /// to the "All" label so the copy is never a raw slug.
  static String _labelFor(PatientHomeData home, String slug) {
    if (slug == HomeCategory.allSlug) return HomeCategory.all.nameEn;
    for (final c in home.railCategories) {
      if (c.slug == slug) return c.nameEn;
    }
    return HomeCategory.all.nameEn;
  }

  /// Opens the New Care Request flow, prefilled when the card links to a live
  /// catalog service.
  ///
  /// There is no service detail screen — both the card body and the Book Now
  /// button land here. A curated card whose linked service has since been
  /// deleted (or a catalog that hasn't loaded) still opens the flow, just
  /// empty, which is a better outcome than an inert tap.
  static void _book(WidgetRef ref, HomeServiceCard card) {
    final id = card.serviceId;
    if (id != null && id.isNotEmpty) {
      for (final item in ref.read(activeServicesProvider).valueOrNull ??
          const <ServiceCatalogItem>[]) {
        if (item.id == id) {
          ref
              .read(newRequestProvider.notifier)
              .applyServicePrefill(item, fromLink: true);
          break;
        }
      }
    }
    ref.goToNewRequest();
  }
}

/// Picks and builds the arrangement. Split out from [CareServicesSection] so
/// the CMS preview can render the exact same widget for a layout the admin is
/// only considering, without a repository or a filter behind it.
class LayoutEngine extends StatelessWidget {
  final HomeLayoutType layoutType;
  final List<HomeServiceCard> cards;
  final ValueChanged<HomeServiceCard> onTap;

  const LayoutEngine({
    super.key,
    required this.layoutType,
    required this.cards,
    required this.onTap,
  });

  /// Above this viewport width a carousel would leave most of the window
  /// empty, so it reflows into a grid. Matches the breakpoint the rail already
  /// used before the layout was configurable.
  static const double wideBreakpoint = 700;

  @override
  Widget build(BuildContext context) {
    switch (layoutType) {
      case HomeLayoutType.list:
        return _ListLayout(cards: cards, onTap: onTap);
      case HomeLayoutType.grid2Col:
        return _GridLayout(cards: cards, onTap: onTap, columns: 2);
      case HomeLayoutType.carousel:
        // On web/desktop the swipeable rail becomes a fluid grid rather than a
        // 240px strip against a 1400px window. The admin picked "carousel" for
        // the phone; this is the same layout, reflowed.
        final width = MediaQuery.sizeOf(context).width;
        if (width >= wideBreakpoint) {
          return _GridLayout(
            cards: cards,
            onTap: onTap,
            columns: width >= 1000 ? 3 : 2,
          );
        }
        return _CarouselLayout(cards: cards, onTap: onTap);
    }
  }
}

/// CAROUSEL — flush-edge horizontal rail. The 16px inset lives *inside* the
/// ListView, so at rest the first card aligns with the section header while
/// mid-swipe the cards clip flush against the screen edge.
class _CarouselLayout extends StatelessWidget {
  final List<HomeServiceCard> cards;
  final ValueChanged<HomeServiceCard> onTap;

  const _CarouselLayout({required this.cards, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kCareServiceCardRailHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: cards.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => SizedBox(
          width: kCareServiceCardWidth,
          child: StaggeredAnimatedCard(
            index: i,
            child: _Card(card: cards[i], onTap: onTap),
          ),
        ),
      ),
    );
  }
}

/// GRID_2_COL — non-scrolling grid inside the page's own ListView, so it
/// shrink-wraps and the page keeps ownership of scrolling.
class _GridLayout extends StatelessWidget {
  final List<HomeServiceCard> cards;
  final ValueChanged<HomeServiceCard> onTap;
  final int columns;

  const _GridLayout({
    required this.cards,
    required this.onTap,
    required this.columns,
  });

  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    // The aspect ratio is derived from the measured tile width rather than
    // taken from a constant, so tiles land on the rail's 260px height at every
    // viewport — a fixed ratio squashes them on a narrow phone, where two
    // columns are ~158px wide instead of the 278px the 600px-capped column
    // assumes.
    return _Inset(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tile =
              (constraints.maxWidth - _gap * (columns - 1)) / columns;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: _gap,
              crossAxisSpacing: _gap,
              childAspectRatio: tile / kCareServiceCardRailHeight,
            ),
            itemCount: cards.length,
            itemBuilder: (_, i) => StaggeredAnimatedCard(
              index: i,
              child: _Card(card: cards[i], onTap: onTap),
            ),
          );
        },
      ),
    );
  }
}

/// LIST — full-width stacked rows.
class _ListLayout extends StatelessWidget {
  final List<HomeServiceCard> cards;
  final ValueChanged<HomeServiceCard> onTap;

  const _ListLayout({required this.cards, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _Inset(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            StaggeredAnimatedCard(
              index: i,
              child: _CareServiceListRow(card: cards[i], onTap: onTap),
            ),
          ],
        ],
      ),
    );
  }
}

/// Adapts a [HomeServiceCard] onto the shared [CareServiceCard] used by the
/// carousel and grid layouts.
class _Card extends StatelessWidget {
  final HomeServiceCard card;
  final ValueChanged<HomeServiceCard> onTap;

  const _Card({required this.card, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return CareServiceCard(
      title: card.title,
      description: card.description,
      categoryLabel: card.badgeText,
      priceLabel: card.priceLabel,
      imageUrl: card.imageUrl,
      onTap: () => onTap(card),
    );
  }
}

/// One full-width row in the LIST layout: square photo on the left, text
/// column, price + Book Now on the right.
///
/// A row rather than a wide [CareServiceCard]: the card's scrim-over-photo
/// composition needs height to breathe, and stretched to full width at rail
/// height it reads as a banner, not a list item. The tokens are shared
/// ([PressableCard], [CareCardImage], [CareCardCategoryBadge],
/// [CareServiceBookButton]) so it still belongs to the same family.
class _CareServiceListRow extends StatelessWidget {
  final HomeServiceCard card;
  final ValueChanged<HomeServiceCard> onTap;

  const _CareServiceListRow({required this.card, required this.onTap});

  /// Floor, not a fixed height. The row grows with its content instead, which
  /// it has to: a bilingual title is two lines, and with a description and the
  /// price row beneath it that content is taller than any single number picked
  /// in advance — more so once accessibility text scaling is applied. Pinning
  /// the height put a RenderFlex overflow stripe across a real card.
  static const double _minHeight = 108;
  static const double _thumb = 108;

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final badge = card.badgeText?.trim();
    final description = card.description?.trim();
    final price = card.priceLabel;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _minHeight),
      child: Semantics(
        container: true,
        label: [card.titleEn, if (badge != null && badge.isNotEmpty) badge, ?price]
            .join(', '),
        child: PressableCard(
          onTap: () => onTap(card),
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            // Lets the photo column fill whatever height the text column ends
            // up needing, so the image still runs edge to edge on a tall row.
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: _thumb,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CareCardImage(
                          url: card.imageUrl,
                          fallbackIcon: serviceIconFor(badge, card.titleEn),
                        ),
                        if (badge != null && badge.isNotEmpty)
                          Positioned(
                            left: 6,
                            top: 6,
                            child: CareCardCategoryBadge(
                              label: badge,
                              accent:
                                  ServiceCategoryTheme.accentFor(context, badge),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            card.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: MtTextStyles.labelLg.copyWith(
                              color: hd.title,
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                            ),
                          ),
                          if (description != null &&
                              description.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: MtTextStyles.bodySm
                                  .copyWith(color: hd.muted),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (price != null)
                                Expanded(
                                  child: Text(
                                    price,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: MtTextStyles.timer.copyWith(
                                      color: hd.title,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                )
                              else
                                const Spacer(),
                              const SizedBox(width: 8),
                              CareServiceBookButton(
                                onTap: () => onTap(card),
                                compact: true,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Section header, matching the one the rest of Home uses: uppercase English
/// on the left, the Bengali title on the right.
class _SectionHeader extends StatelessWidget {
  final String en;
  final String? bn;
  const _SectionHeader({required this.en, this.bn});

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final bengali = bn?.trim();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          en.toUpperCase(),
          style: MtTextStyles.sectionLabel
              .copyWith(color: hd.body, letterSpacing: 1.0),
        ),
        if (bengali != null && bengali.isNotEmpty)
          Text(
            bengali,
            style: MtTextStyles.sectionLabel
                .copyWith(color: hd.muted, fontFamily: 'Kalpurush'),
          ),
      ],
    );
  }
}

/// The standard 16px horizontal page inset. The home `ListView` is zero-padded
/// so rails can bleed to the screen edges; every non-rail block re-applies it.
class _Inset extends StatelessWidget {
  final Widget child;
  const _Inset({required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: child,
      );
}

/// Shown only on the fallback path, where `/api/services` is the sole source
/// of cards and its failure means there is genuinely nothing to draw.
class _CatalogError extends StatelessWidget {
  final VoidCallback onRetry;
  const _CatalogError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: hd.surface,
        borderRadius: BorderRadius.circular(kCareCardRadius),
        border: Border.all(color: hd.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, color: hd.muted, size: 28),
          const SizedBox(height: 12),
          Text(
            "Couldn't load services",
            style: MtTextStyles.labelLg.copyWith(color: hd.title),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: hd.violetBright),
            child: Text(
              'Retry',
              style: MtTextStyles.labelMd.copyWith(color: hd.violetBright),
            ),
          ),
        ],
      ),
    );
  }
}

/// Header + rail placeholder while the first payload loads. Mirrors the real
/// card's silhouette — a full-bleed image block with the text stack anchored
/// to the bottom — so the switch to loaded data doesn't reflow the row.
class _CareServicesSkeleton extends StatelessWidget {
  const _CareServicesSkeleton();

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Inset(child: _SectionHeader(en: 'Care services', bn: 'সেবা')),
        const SizedBox(height: 12),
        SizedBox(
          height: kCareServiceCardRailHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 4,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, _) => Container(
              width: kCareServiceCardWidth,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: hd.violet.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(kCareCardRadius),
                border: Border.all(color: hd.border),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MtSkeleton.line(width: 120),
                    const SizedBox(height: 8),
                    MtSkeleton.line(width: 90, height: 10),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        MtSkeleton.line(width: 60, height: 12),
                        const Spacer(),
                        MtSkeleton.box(width: 90, height: 36, radius: 999),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
