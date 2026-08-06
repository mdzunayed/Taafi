import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/home_data_providers.dart';
import '../../../../core/api/service_catalog_providers.dart';
import '../../../../core/models/home_category.dart';
import '../../../../core/models/home_service_card.dart';
import '../../../../core/models/patient_home_data.dart';
import '../../../../core/models/service_catalog_item.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../navigation/patient_nav_provider.dart';
import '../../new_request/new_request_notifier.dart';
import 'care_card_primitives.dart';
import 'care_service_card.dart';
import 'category_selection.dart';
import 'patient_home_palette.dart';
import 'staggered_animated_card.dart';

/// The dedicated listing a specific category pill opens.
///
/// Home has two shapes now. Under "All" it is the full dashboard — promos,
/// ongoing care, the Care Services block, the CMS sections, the support card.
/// Under any other pill it collapses to *this*: nothing but a full-height list
/// of the services tagged with it, starting directly beneath the pinned rail.
/// [PatientHomeScreen] owns that switch; the rail above stays mounted in both,
/// so a pill is always one tap away from any other.
///
/// **Nothing between the pills and the cards.** The category masthead and the
/// Price / Rating / Urgent sub-filter row that used to sit here are gone: on a
/// phone they pushed the first card most of the way down the fold to restate a
/// label the selected pill was already showing. The pill *is* the header.
///
/// **No fetch on switch.** Every card, its pills, its urgency flag and its
/// rating already arrived with `/api/home-data`, so opening a category is a
/// pure client-side re-render — no spinner, no round trip, no empty window.
/// The equivalent server-side query
/// (`GET /api/services/by-category?categoryId=&sort=&urgentOnly=`) exists and
/// returns the same shape; it is what the CMS previews a pill's contents with,
/// and what any client without the aggregate payload should use.
class CategoryServicesView extends ConsumerWidget {
  /// The pill being shown. Never [HomeCategory.allSlug] — Home renders the
  /// dashboard for that instead of mounting this widget.
  final String categorySlug;

  /// Bottom padding for the floating nav pill, passed down to the scrollable
  /// so the last card clears it.
  final double bottomInset;

  const CategoryServicesView({
    super.key,
    required this.categorySlug,
    this.bottomInset = 24,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeAsync = ref.watch(patientHomeDataProvider);
    final catalogAsync = ref.watch(activeServicesProvider);
    final filters = ref.watch(categoryFiltersProvider);

    final home = homeAsync.valueOrNull ?? PatientHomeData.fallback;
    final category = home.categoryBySlug(categorySlug);

    // Same two-source rule as CareServicesSection: the CMS payload normally
    // supplies the cards, and the plain catalog is the fallback for a backend
    // that predates `/api/home-data`.
    final List<HomeServiceCard> cards;
    if (home.isLive) {
      cards = home.careServices.services;
    } else {
      cards = [
        for (final item
            in catalogAsync.valueOrNull ?? const <ServiceCatalogItem>[])
          HomeServiceCard.fromCatalog(item),
      ];
    }

    // Membership first, then whatever ordering [categoryFiltersProvider] holds.
    // Nothing on screen writes that state any more — the sub-filter chips are
    // gone — so in practice this is `CategoryFilters.none` and the list keeps
    // the catalog's curated order. The hook stays because the state is also the
    // client mirror of `sort=` / `urgentOnly=` on
    // `GET /api/services/by-category`, and a deep link or a future control
    // setting it must still reorder this list rather than be silently ignored.
    final inCategory = [
      for (final card in cards)
        if (card.matchesCategorySlug(categorySlug)) card,
    ];
    final visible = applyCategoryFilters(inCategory, filters);

    // On the fallback path the catalog IS the card source, so its first load
    // counts as loading too — otherwise the view would claim the category is
    // empty for the moment before `/api/services` lands.
    final loading = (homeAsync.isLoading && !homeAsync.hasValue) ||
        (!home.isLive && catalogAsync.isLoading && !catalogAsync.hasValue);

    // No Column, no pinned chrome: the list is the whole view, so it starts
    // immediately under the rail and every pixel below it scrolls.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      child: loading
          ? const _CategoryListSkeleton(key: ValueKey('loading'))
          : visible.isEmpty
              ? _CategoryEmptyState(
                  // Keyed so switching from a populated list to an empty one
                  // actually plays the transition.
                  key: const ValueKey('empty'),
                  categoryLabel: category?.nameEn ?? 'this category',
                )
              : CareServicesListView(
                  // Re-keyed per category: without this the switcher sees
                  // "a list, still a list" and cross-fades nothing.
                  key: ValueKey(categorySlug),
                  categorySlug: categorySlug,
                  services: visible,
                  bottomInset: bottomInset,
                  onTap: (card) => _book(ref, card),
                ),
    );
  }

  /// Opens the New Care Request flow, prefilled when the card links to a live
  /// catalog service. Mirrors `CareServicesSection._book` — the same tap does
  /// the same thing in both views.
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

/// Applies a [CategoryFilters] to an already category-matched list.
///
/// The on-screen chips that used to drive this are gone, so today it is only
/// ever handed [CategoryFilters.none] and is a pass-through. It stays because
/// it is the client half of `GET /api/services/by-category`'s `sort=` /
/// `urgentOnly=` contract: whatever sets that state — a deep link, the CMS
/// preview, a control this surface grows back — has to reorder the list the
/// way the server would, or the two views of one category disagree.
///
/// Pure and separate from the widget so it can be reasoned about (and tested)
/// on its own, and so the ordering matches
/// `GET /api/services/by-category`'s `SORTS` table exactly.
List<HomeServiceCard> applyCategoryFilters(
  List<HomeServiceCard> cards,
  CategoryFilters filters,
) {
  final out = [
    for (final card in cards)
      if (!filters.urgentOnly || card.isUrgentAvailable) card,
  ];

  switch (filters.sort) {
    case CategorySort.recommended:
      // The catalog's own order — an admin curates it, so leave it alone.
      break;
    case CategorySort.priceAsc:
      // Cards with no price at all ("Free", a curated card with a word tag)
      // sort last rather than to the top as a phantom ৳0.
      out.sort((a, b) => (a.price ?? double.infinity)
          .compareTo(b.price ?? double.infinity));
    case CategorySort.topRated:
      // Ties broken by review volume, then price: a lone 5★ should not outrank
      // a 4.9★ with 200 reviews, and an unrated service sorts last.
      out.sort((a, b) {
        final byRating = b.rating.compareTo(a.rating);
        if (byRating != 0) return byRating;
        final byCount = b.ratingCount.compareTo(a.ratingCount);
        if (byCount != 0) return byCount;
        return (a.price ?? double.infinity)
            .compareTo(b.price ?? double.infinity);
      });
  }
  return out;
}

/// The scannable, full-height list a category view is mostly made of.
///
/// A vertical list rather than the dashboard's carousel: the point of entering
/// a category is to compare everything in it, and a rail that shows two and a
/// half cards at a time is the wrong tool for that. On a wide viewport it
/// reflows into a 2- or 3-column grid, matching `LayoutEngine`'s breakpoints so
/// the two surfaces agree about what "wide" means.
class CareServicesListView extends StatelessWidget {
  final String categorySlug;
  final List<HomeServiceCard> services;
  final ValueChanged<HomeServiceCard> onTap;
  final double bottomInset;

  const CareServicesListView({
    super.key,
    required this.categorySlug,
    required this.services,
    required this.onTap,
    this.bottomInset = 24,
  });

  /// Above this width the single column leaves most of the window empty.
  /// Same value `LayoutEngine` uses.
  static const double _wideBreakpoint = 700;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final padding = EdgeInsets.fromLTRB(16, 12, 16, bottomInset);

    if (width >= _wideBreakpoint) {
      final columns = width >= 1000 ? 3 : 2;
      return GridView.builder(
        padding: padding,
        physics: const AlwaysScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1,
        ),
        itemCount: services.length,
        itemBuilder: (_, i) => StaggeredAnimatedCard(
          index: i,
          child: _GridCard(card: services[i], onTap: onTap),
        ),
      );
    }

    return ListView.separated(
      padding: padding,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: services.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => StaggeredAnimatedCard(
        index: i,
        child: CategoryServiceRow(card: services[i], onTap: onTap),
      ),
    );
  }
}

/// The dashboard's square card, reused for the wide-viewport grid so the two
/// layouts share one visual language.
class _GridCard extends StatelessWidget {
  final HomeServiceCard card;
  final ValueChanged<HomeServiceCard> onTap;

  const _GridCard({required this.card, required this.onTap});

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

/// One full-width row in the category listing: photo, title, description, then
/// a metadata line carrying the rating and the urgent flag, with the price and
/// Book Now on the right.
///
/// It is a near-sibling of `CareServicesSection`'s LIST row and deliberately
/// not the same widget: this one carries the rating and urgency the sub-filters
/// sort on, and a row that showed those on the dashboard would be claiming
/// information the dashboard doesn't let you act on.
class CategoryServiceRow extends StatelessWidget {
  final HomeServiceCard card;
  final ValueChanged<HomeServiceCard> onTap;

  const CategoryServiceRow({
    super.key,
    required this.card,
    required this.onTap,
  });

  /// A floor, not a fixed height — bilingual titles are two lines, and text
  /// scaling adds more. Pinning it put a RenderFlex stripe across a real card.
  static const double _minHeight = 116;
  static const double _thumb = 116;

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final badge = card.badgeText?.trim();
    final description = card.description?.trim();
    final price = card.priceLabel;
    final rating = card.ratingLabel;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _minHeight),
      child: Semantics(
        container: true,
        label: [
          card.titleEn,
          if (badge != null && badge.isNotEmpty) badge,
          if (rating != null) '$rating stars from ${card.ratingCount} reviews',
          if (card.isUrgentAvailable) 'urgent visits available',
          ?price,
        ].join(', '),
        child: PressableCard(
          onTap: () => onTap(card),
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
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
                              accent: ServiceCategoryTheme.accentFor(
                                context,
                                badge,
                              ),
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
                          if (description != null && description.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: MtTextStyles.bodySm
                                  .copyWith(color: hd.muted),
                            ),
                          ],
                          // The metadata line is omitted entirely when a
                          // service is unrated and non-urgent, so a row never
                          // reserves height for nothing.
                          if (rating != null || card.isUrgentAvailable) ...[
                            const SizedBox(height: 7),
                            Row(
                              children: [
                                if (rating != null) ...[
                                  Icon(Icons.star_rounded,
                                      size: 14, color: hd.accent),
                                  const SizedBox(width: 3),
                                  Text(
                                    rating,
                                    style: MtTextStyles.labelSm.copyWith(
                                      color: hd.title,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '(${card.ratingCount})',
                                    style: MtTextStyles.labelSm
                                        .copyWith(color: hd.muted),
                                  ),
                                ],
                                if (rating != null && card.isUrgentAvailable)
                                  const SizedBox(width: 10),
                                if (card.isUrgentAvailable)
                                  const _UrgentTag(),
                              ],
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

/// The "Urgent" capsule on a row. Uses the brand orange rather than a red
/// alert tint: it advertises availability, it is not a warning.
class _UrgentTag extends StatelessWidget {
  const _UrgentTag();

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: hd.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 12, color: hd.accent),
          const SizedBox(width: 3),
          Text(
            'Urgent',
            style: MtTextStyles.labelSm.copyWith(
              color: hd.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Nothing to show under this pill.
///
/// Always offers a way out. With the sub-filters gone an empty list has exactly
/// one cause — the category genuinely has no services — so there is one message
/// and one exit, back to the full catalog. An empty view with no exit is how a
/// filter rail becomes a trap.
class _CategoryEmptyState extends ConsumerWidget {
  final String categoryLabel;

  const _CategoryEmptyState({
    super.key,
    required this.categoryLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hd = HomeDark.of(context);
    final accent =
        ServiceCategoryTheme.accentFor(context, categoryLabel) ?? hd.violetBright;

    return ListView(
      // A ListView, not a Column: the empty state has to stay pull-to-refresh
      // -able, and a non-scrollable child gives RefreshIndicator nothing to
      // attach its gesture to.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
          decoration: BoxDecoration(
            color: hd.surface,
            borderRadius: BorderRadius.circular(kCareCardRadius),
            border: Border.all(color: hd.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  serviceIconFor(categoryLabel, null),
                  color: accent,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No $categoryLabel services yet',
                textAlign: TextAlign.center,
                style: MtTextStyles.labelLg.copyWith(color: hd.title),
              ),
              const SizedBox(height: 6),
              Text(
                'Check back soon, or browse everything Taafi offers.',
                textAlign: TextAlign.center,
                style: MtTextStyles.bodySm.copyWith(color: hd.muted),
              ),
              const SizedBox(height: 18),
              _EmptyStateAction(
                label: 'Reset to all services',
                icon: Icons.grid_view_rounded,
                accent: accent,
                filled: true,
                onTap: () => resetToAllCategories(ref),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyStateAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final bool filled;
  final VoidCallback onTap;

  const _EmptyStateAction({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : accent;
    return Material(
      color: filled ? accent : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: accent, width: filled ? 0 : 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 8),
              // Flexible, not bare: "Reset to all services" is the longest
              // string on this surface, and on a 320px phone at raised text
              // scale it is wider than the card it sits in. Ellipsis beats an
              // overflow stripe across the one control that gets a patient out
              // of an empty category.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MtTextStyles.labelMd
                      .copyWith(color: fg, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder rows while the first `/api/home-data` payload lands. Mirrors
/// [CategoryServiceRow]'s silhouette so the swap to real cards doesn't reflow.
class _CategoryListSkeleton extends StatelessWidget {
  const _CategoryListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 4,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, _) => Container(
        height: CategoryServiceRow._minHeight,
        decoration: BoxDecoration(
          color: hd.surface,
          borderRadius: BorderRadius.circular(kCareCardRadius),
          border: Border.all(color: hd.border),
        ),
      ),
    );
  }
}
