import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/home_section_providers.dart';
import '../../../core/api/patient_home_repository.dart';
import '../../../core/api/promo_banner_providers.dart';
import '../../../core/api/service_catalog_providers.dart';
import '../../../core/config/support_config.dart';
import '../../../core/models/promo_banner.dart';
import '../../../core/models/service_catalog_item.dart';
import '../../../core/models/service_category.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/frosted_surface.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/mt_skeleton.dart';
import '../../auth/auth_provider.dart';
import '../../notifications/widgets/notification_bell.dart';
import '../navigation/banner_action_dispatcher.dart';
import '../navigation/patient_nav_provider.dart';
import '../new_request/new_request_notifier.dart';
import 'booking_tracking_screen.dart';
import 'widgets/care_card_primitives.dart';
import 'widgets/care_service_card.dart';
import 'widgets/care_services_empty_state.dart';
import 'widgets/dynamic_home_sections.dart';
import 'widgets/ongoing_care_card.dart';
import 'widgets/patient_home_palette.dart';
import 'widgets/staggered_animated_card.dart';

/// Currently-selected category chip, one of [kPatientCategoryChips]. Defaults
/// to `'All'` (show everything). Watched by both the chip rail (to highlight
/// the active pill) and the services grid (to filter its items).
final selectedCategoryProvider =
    StateProvider<String>((ref) => kServiceCategoryAll);

/// Tab 0 of the patient shell — the dashboard. Renders the greeting +
/// alert bell header, "Your care timeline" card (or the orange hero
/// promo when no active request exists), the care-services catalog
/// grid, the recent providers list, and the quick-help support card.
///
/// This widget is body-only: the surrounding [Scaffold], the
/// [BottomNavigationBar], and the cross-tab navigation provider all
/// live in [PatientMainNavigationWrapper]. Keeping that separation
/// means this surface stays focused on the dashboard content alone
/// and is independently render-testable.
class PatientHomeScreen extends ConsumerWidget {
  const PatientHomeScreen({super.key});

  Future<void> _onRefresh(WidgetRef ref) async {
    await Future.wait([
      ref.read(patientHomeFeedProvider.notifier).refresh(),
      // Must go through the repository — `ref.refresh(activeServicesProvider)`
      // only re-subscribes to the existing repository and replays its cached
      // error without issuing a request. See [refreshServiceCatalog].
      refreshServiceCatalog(ref),
      ref.read(homeSectionRepositoryProvider).refresh(),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeRequest = ref.watch(patientActiveRequestProvider);
    final feedAsync = ref.watch(patientHomeFeedProvider);
    final hd = HomeDark.of(context);

    // Height of the frosted header's content row (below the status bar). The
    // brand lockup is a two-line stack, so it needs a touch more room than
    // the old single-line greeting.
    const double headerContent = 60;
    final double topInset = MediaQuery.of(context).padding.top;

    // The scroll content flows full-bleed to the top edge and the glass
    // header is layered above it (a `Stack`), so the list visibly blurs
    // through the frosted bar as it scrolls beneath the system status bar.
    return Stack(
      children: [
        // Theme canvas painted behind everything so the Home surface fills
        // the viewport (midnight in dark, slate in light).
        Positioned.fill(child: ColoredBox(color: hd.canvas)),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: RefreshIndicator(
              color: hd.violetBright,
              backgroundColor: hd.surfaceHi,
              onRefresh: () => _onRefresh(ref),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                // Top pad clears the frosted header; bottom keeps the last
                // card above the floating nav pill. Horizontal padding is 0
                // so full-bleed rails (chips, providers) can run edge-to-edge;
                // each block re-applies its own 16 px inset.
                padding: EdgeInsets.fromLTRB(
                  0,
                  topInset + headerContent + 12,
                  0,
                  24,
                ),
                children: [
                  const _CategoryChipsRail(),
                  const SizedBox(height: 16),
                  const _Inset(child: _PromoCarousel()),
                  const SizedBox(height: 24),
                  // Ongoing-care block only appears while loading or when the
                  // patient actually has an active request — no hero fallback.
                  if (feedAsync.isLoading && activeRequest == null)
                    const _Inset(child: _ActiveRequestSkeleton())
                  else if (activeRequest != null)
                    _Inset(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SectionHeader(
                            en: 'Ongoing care',
                            trailing: _SectionAction(
                              label: 'Track',
                              onTap: () => ref.goToActivities(
                                sub: PatientActivitiesTab.tracking,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          OngoingCareCard(
                            request: activeRequest,
                            onTrackDetails: () => openBookingTracking(
                              context,
                              activeRequest,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (feedAsync.isLoading || activeRequest != null)
                    const SizedBox(height: 24),
                  const _Inset(
                    child: _SectionHeader(en: 'Care services', bn: 'সেবা'),
                  ),
                  const SizedBox(height: 12),
                  const _ServicesGrid(),
                  const SizedBox(height: 24),
                  // Admin-managed server-driven sections (carries its own
                  // insets/gaps; collapses to zero height when none exist).
                  const DynamicHomeSections(),
                  const _Inset(child: _QuickHelpCard()),
                ],
              ),
            ),
          ),
        ),
        _GlassTopBar(
          topInset: topInset,
          height: headerContent,
          child: const _HeaderRow(),
        ),
      ],
    );
  }
}

/// Applies the standard 16 px horizontal page inset to a child. Used so the
/// home `ListView` itself can be zero-padded (letting the chip + provider
/// rails bleed to the screen edges) while regular blocks stay aligned.
class _Inset extends StatelessWidget {
  final Widget child;
  const _Inset({required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: child,
    );
  }
}

/// Translucent frosted-glass top control deck. Pins to the top edge and
/// blurs whatever scrolls beneath it (`sigmaX/Y: 10`), with a soft cream
/// tint + hairline bottom border so the slate greeting text stays legible.
class _GlassTopBar extends StatelessWidget {
  final double topInset;
  final double height;
  final Widget child;

  const _GlassTopBar({
    required this.topInset,
    required this.height,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: FrostedSurface(
        blur: 10,
        child: Container(
          padding: EdgeInsets.fromLTRB(16, topInset, 8, 0),
          height: topInset + height,
          decoration: BoxDecoration(
            // On web (no backdrop blur) the fill carries the frosting, so it
            // sits more opaque; native keeps the translucent blur look.
            color: hd.canvas.withValues(
              alpha: FrostedSurface.blurSupported ? 0.72 : 0.92,
            ),
            border: Border(
              bottom: BorderSide(color: hd.border),
            ),
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}

/// Home top bar: brand lockup on the left (logo tile + "Taafi" wordmark
/// + "HOME CARE • DHAKA" caption), and the notification bell + circular
/// profile avatar on the right. Tapping the avatar deep-links to the Account
/// screen via `ref.goToAccount()` — the exact same view switch the retired
/// bottom-nav "Account" tab performed.
class _HeaderRow extends ConsumerWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hd = HomeDark.of(context);
    final user = ref.watch(currentUserProvider);

    return Row(
      children: [
        // Brand logo — local asset, degrading to a violet icon tile if the
        // asset ever fails to load.
        Image.asset(
          'assets/logo/temp-logo.png',
          height: 32,
          width: 32,
          errorBuilder: (_, _, _) => Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [hd.violet2, hd.violetDeep],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.medical_services_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Taa',
                      style: MtTextStyles.h2.copyWith(color: hd.title),
                    ),
                    TextSpan(
                      text: 'fi',
                      style:
                          MtTextStyles.h2.copyWith(color: hd.violetBright),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'HOME CARE • DHAKA',
                style: MtTextStyles.labelSm.copyWith(
                  color: hd.muted,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const NotificationBell(),
        const SizedBox(width: 10),
        _ProfileAvatarButton(name: user?.name),
      ],
    );
  }
}

/// Circular profile avatar in the header. Shows the signed-in user's initials
/// (or a fallback person glyph) and, on tap, switches the shell to the Account
/// destination — same lifecycle as the old bottom-nav Account tab.
class _ProfileAvatarButton extends ConsumerWidget {
  static const double _size = 38;
  final String? name;
  const _ProfileAvatarButton({required this.name});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hd = HomeDark.of(context);
    final resolved = name?.trim() ?? '';
    return Semantics(
      button: true,
      label: 'Account',
      child: GestureDetector(
        onTap: ref.goToAccount,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: hd.violet, width: 2),
            boxShadow: [
              BoxShadow(color: hd.glow, blurRadius: 10),
            ],
          ),
          padding: const EdgeInsets.all(2),
          child: resolved.isEmpty
              ? Container(
                  width: _size,
                  height: _size,
                  decoration: BoxDecoration(
                    color: hd.surfaceHi,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person_rounded,
                    color: hd.violetBright,
                    size: 22,
                  ),
                )
              : InitialsAvatar(
                  name: resolved,
                  size: _size,
                  backgroundColor: hd.surfaceHi,
                  textColor: hd.violetBright,
                ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String en;
  final String? bn;

  /// Optional right-aligned action (e.g. "Track ›", "View all ›"). Takes
  /// precedence over [bn] on the trailing edge when both are supplied.
  final Widget? trailing;

  const _SectionHeader({required this.en, this.bn, this.trailing});

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          en.toUpperCase(),
          style: MtTextStyles.sectionLabel.copyWith(
            color: hd.body,
            letterSpacing: 1.0,
          ),
        ),
        if (trailing != null)
          trailing!
        else if (bn != null)
          Text(
            bn!,
            style: MtTextStyles.sectionLabel.copyWith(
              color: hd.muted,
              fontFamily: 'Kalpurush',
            ),
          ),
      ],
    );
  }
}

/// Compact brand-orange text action with a trailing chevron, used on the
/// right edge of a [_SectionHeader] ("Track ›", "View all ›").
class _SectionAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SectionAction({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: MtTextStyles.labelMd.copyWith(
                color: hd.violetBright,
                fontWeight: FontWeight.w700,
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: hd.violetBright),
          ],
        ),
      ),
    );
  }
}

/// Horizontal, edge-to-edge rail of selectable category chips. Reads and
/// writes [selectedCategoryProvider]; the active chip is filled brand-orange,
/// the rest are hairline-bordered pills. Filtering happens in [_ServicesGrid].
class _CategoryChipsRail extends ConsumerWidget {
  const _CategoryChipsRail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedCategoryProvider);
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: kPatientCategoryChips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final label = kPatientCategoryChips[i];
          final active = label == selected;
          return _CategoryChip(
            label: label,
            active: active,
            onTap: () =>
                ref.read(selectedCategoryProvider.notifier).state = label,
          );
        },
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return Material(
      color: active ? hd.accent : hd.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? hd.accent : hd.border,
            ),
            boxShadow: active
                ? [BoxShadow(color: hd.accentGlow, blurRadius: 12)]
                : null,
          ),
          child: Text(
            label,
            style: MtTextStyles.labelMd.copyWith(
              color: active ? Colors.white : hd.body,
              fontWeight: active ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Swipeable promo carousel — a `PageView` of vivid gradient slides fed live
/// from the admin-managed [activeBannersProvider], with a page-dot indicator
/// and a gentle auto-advance. The dot count, auto-advance modulo, and item
/// count all track the live banner list. Each slide's CTA routes into the New
/// Request flow (kept in-shell — no new route needed). Hidden entirely while
/// loading fails or no active banners exist.
class _PromoCarousel extends ConsumerStatefulWidget {
  const _PromoCarousel();

  @override
  ConsumerState<_PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends ConsumerState<_PromoCarousel> {
  static const double _cardHeight = 176;
  final PageController _controller = PageController();
  Timer? _timer;
  int _page = 0;
  // Latest banner count, refreshed each build so the auto-advance timer and
  // dot track stay in sync with the live list.
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_controller.hasClients || _count <= 1) return;
      final next = (_page + 1) % _count;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bannersAsync = ref.watch(activeBannersProvider);
    return bannersAsync.maybeWhen(
      data: (banners) {
        if (banners.isEmpty) {
          _count = 0;
          return const SizedBox.shrink();
        }
        _count = banners.length;
        final active = _page.clamp(0, banners.length - 1);
        return Column(
          children: [
            SizedBox(
              height: _cardHeight,
              child: PageView.builder(
                controller: _controller,
                itemCount: banners.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _PromoSlideCard(
                  banner: banners[i],
                  onTap: () => handleBannerTap(context, ref, banners[i]),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _PromoDots(count: banners.length, active: active),
          ],
        );
      },
      loading: () => const SizedBox(
        height: _cardHeight,
        child: _PromoSkeleton(),
      ),
      // Error / not-yet-loaded — keep the promo strip out of the way.
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// A soft placeholder shown while the first banner list loads.
class _PromoSkeleton extends StatelessWidget {
  const _PromoSkeleton();

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hd.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hd.border),
      ),
    );
  }
}

/// A single gradient promo slide rendered from a [PromoBanner]. The gradient
/// stops, tag, title, and CTA label all come from the banner; when it carries
/// an [PromoBanner.imageUrl] the photo sits as a faint overlay behind the copy.
class _PromoSlideCard extends StatelessWidget {
  final PromoBanner banner;
  final VoidCallback onTap;
  const _PromoSlideCard({required this.banner, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final hasImage = banner.imageUrl != null && banner.imageUrl!.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: banner.gradient,
          ),
          border:
              Border.all(color: hd.violetBright.withValues(alpha: 0.35)),
        ),
        child: Stack(
          children: [
            if (hasImage)
              Positioned.fill(
                child: Opacity(
                  opacity: 0.22,
                  child: Image.network(
                    banner.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    banner.tagText,
                    style: MtTextStyles.labelSm.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    banner.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                    style: MtTextStyles.h2.copyWith(
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: onTap,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 9,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              banner.buttonText,
                              style: MtTextStyles.labelMd.copyWith(
                                color: hd.violetDeep,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.arrow_forward,
                              size: 16,
                              color: hd.violetDeep,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Page-dot indicator — the active dot stretches into a bright violet pill,
/// the rest are dim muted dots.
class _PromoDots extends StatelessWidget {
  final int count;
  final int active;
  const _PromoDots({required this.count, required this.active});

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == active ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == active ? hd.violetBright : hd.muted,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}


class _ActiveRequestSkeleton extends StatelessWidget {
  const _ActiveRequestSkeleton();

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: hd.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hd.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MtSkeleton.line(width: 110, height: 22),
          const SizedBox(height: 14),
          MtSkeleton.line(width: 180),
          const SizedBox(height: 8),
          MtSkeleton.line(width: 220, height: 10),
          const SizedBox(height: 18),
          MtSkeleton.box(height: 44, radius: 10),
        ],
      ),
    );
  }
}

/// Adaptive Care Services layout, filtered by the active category chip. On
/// mobile-width viewports it renders the edge-to-edge `_ServicesCarousel`
/// rail inside a fixed-height box; on wide (web/desktop) viewports it swaps
/// to a non-scrolling `_ServicesFluidGrid` so cards reflow instead of being
/// cut off at the viewport edge. Screen width comes from `MediaQuery` rather
/// than a `LayoutBuilder` because the home column is capped at 600px, so
/// incoming constraints can never reveal a wide window.
class _ServicesGrid extends ConsumerWidget {
  const _ServicesGrid();

  static const double _wideBreakpoint = 700;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(activeServicesProvider);
    final category = ref.watch(selectedCategoryProvider);
    final bool wide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;

    return AsyncValueView<List<ServiceCatalogItem>>(
      value: async,
      onRetry: () => refreshServiceCatalog(ref),
      // The skeleton is a horizontal rail, so it needs a bounded height in
      // both modes; the data branch bounds only the carousel, letting the
      // grid grow to as many rows as it needs.
      loadingBuilder: (_) => const SizedBox(
        height: kCareServiceCardRailHeight,
        child: _ServicesGridSkeleton(),
      ),
      // Never treat the raw list as empty here — an empty *filtered* result
      // is handled inside dataBuilder so the "no matches" copy can name the
      // active category chip.
      isEmpty: (list) => false,
      emptyBuilder: (_) => const SizedBox.shrink(),
      dataBuilder: (_, items) {
        final filtered = [
          for (final item in items)
            if (serviceMatchesCategoryChip(item, category)) item,
        ];
        if (filtered.isEmpty) {
          return _Inset(
            child: CareServicesEmptyState(
              category: category,
              onShowAll: () => ref
                  .read(selectedCategoryProvider.notifier)
                  .state = kServiceCategoryAll,
            ),
          );
        }
        return wide
            ? _Inset(child: _ServicesFluidGrid(items: filtered))
            : SizedBox(
                height: kCareServiceCardRailHeight,
                child: _ServicesCarousel(items: filtered),
              );
      },
    );
  }
}

/// Non-scrolling fluid grid for wide (web/desktop) viewports. Lives inside
/// the vertical home `ListView`, so it shrink-wraps and delegates scrolling
/// to the page; column count and tile proportions adapt to the window width
/// while the content itself stays within the app-wide 600px cap.
class _ServicesFluidGrid extends StatelessWidget {
  final List<ServiceCatalogItem> items;
  const _ServicesFluidGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    final double w = MediaQuery.sizeOf(context).width;
    final int cols = w >= 1000 ? 3 : 2;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        // Lands the tiles on the same 260px height the mobile rail uses.
        childAspectRatio: careServiceGridAspectRatio(cols),
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => StaggeredAnimatedCard(
        index: i,
        child: _HomeServiceCard(item: items[i]),
      ),
    );
  }
}

/// Flush-edge horizontal rail for the Care Services cards. The 16 px inset
/// lives *inside* the ListView, so at rest the first card aligns with the
/// section header while mid-swipe the cards clip flush against the screen
/// edge. Only the loaded, non-empty list reaches here; the async / filter /
/// empty-state branches stay in [_ServicesGrid].
class _ServicesCarousel extends StatelessWidget {
  final List<ServiceCatalogItem> items;
  const _ServicesCarousel({required this.items});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(width: 12),
      itemBuilder: (_, i) => SizedBox(
        width: kCareServiceCardWidth,
        child: StaggeredAnimatedCard(
          index: i,
          child: _HomeServiceCard(item: items[i]),
        ),
      ),
    );
  }
}

/// Adapts a [ServiceCatalogItem] onto the shared [CareServiceCard].
///
/// The card itself is model-agnostic (it is also driven by the admin SDUI
/// feed), so this thin wrapper owns the two things that are specific to the
/// catalog: how a service's fields map onto the card's slots, and what tapping
/// one does. There is no service detail screen — both the card body and the
/// Book Now button prefill the booking form and jump straight to it.
class _HomeServiceCard extends ConsumerWidget {
  final ServiceCatalogItem item;
  const _HomeServiceCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void book() {
      ref
          .read(newRequestProvider.notifier)
          .applyServicePrefill(item, fromLink: true);
      ref.goToNewRequest();
    }

    return CareServiceCard(
      title: item.title,
      description: item.description,
      // Shown as stored, so an admin sees on Home exactly what they typed;
      // the badge colour comes from the normalized value.
      categoryLabel: item.category,
      priceLabel: careServicePrice(item.price),
      imageUrl: item.imageUrl,
      onTap: book,
    );
  }
}

/// Placeholder rail shown while the catalog loads.
///
/// Mirrors the real card's silhouette — one full-bleed image block with the
/// text stack anchored to the bottom — rather than an arbitrary shape, so the
/// switch to loaded data doesn't visibly reflow the row.
class _ServicesGridSkeleton extends StatelessWidget {
  const _ServicesGridSkeleton();

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return ListView.separated(
      scrollDirection: Axis.horizontal,
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
    );
  }
}

/// Wide support footer — a single tappable row that direct-dials the
/// helpline. Phone glyph in a tinted box, "Need help?" title, and the
/// operational-hours label, with a trailing chevron. Mirrors the mockup's
/// footer card.
class _QuickHelpCard extends StatelessWidget {
  const _QuickHelpCard();

  Future<void> _onCall(BuildContext context) async {
    final uri = Uri(scheme: 'tel', path: SupportConfig.supportPhone);
    final fallback = 'Call ${SupportConfig.supportPhoneDisplay}';
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(fallback)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(fallback)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return Material(
      color: hd.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _onCall(context),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: hd.border),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: hd.violet.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.phone_in_talk_rounded,
                    color: hd.violetBright, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Need help?',
                      style: MtTextStyles.labelLg.copyWith(
                        color: hd.title,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      SupportConfig.supportHoursLabel,
                      style: MtTextStyles.bodySm.copyWith(color: hd.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded,
                  color: hd.muted, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
