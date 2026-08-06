import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/home_data_providers.dart';
import '../../../core/api/home_section_providers.dart';
import '../../../core/api/patient_home_repository.dart';
import '../../../core/api/platform_pricing_provider.dart';
import '../../../core/api/promo_banner_providers.dart';
import '../../../core/api/service_catalog_providers.dart';
import '../../../core/config/support_config.dart';
import '../../../core/models/home_category.dart';
import '../../../core/models/promo_banner.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/frosted_surface.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/mt_skeleton.dart';
import '../../auth/auth_provider.dart';
import '../../notifications/widgets/notification_bell.dart';
import '../navigation/banner_action_dispatcher.dart';
import '../navigation/patient_nav_provider.dart';
import 'booking_tracking_screen.dart';
import 'widgets/care_services_section.dart';
import 'widgets/category_filter_bar.dart';
import 'widgets/category_services_view.dart';
import 'widgets/dynamic_home_sections.dart';
import 'widgets/ongoing_care_card.dart';
import 'widgets/patient_home_palette.dart';

/// Tab 0 of the patient shell — the dashboard, and the category browser it
/// turns into.
///
/// **Two views, one screen.** The category rail is pinned inside the frosted
/// header and stays put in both:
///
///   * **All** (the default) — the full dashboard: the promo carousel, the
///     ongoing-care card, the Care Services block, the CMS sections, and the
///     quick-help footer.
///   * **Any other pill** — [CategoryServicesView]: a full-height list of only
///     the services tagged with it, and nothing else. No masthead, no
///     sub-filter row; the cards start directly under the rail. The generic
///     promos and home widgets are gone, because they are about the whole
///     catalog and the patient has just said they aren't browsing the whole
///     catalog.
///
/// The switch is a pure state change — nothing re-fetches. Every card the
/// category view needs already arrived in the `/api/home-data` payload the
/// dashboard was built from, which is why the transition can be a 250 ms
/// cross-fade rather than a spinner.
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
      // Same repository-not-provider rule as the catalog above: the chip rail
      // and the Care Services layout both come from here, so a pull-to-refresh
      // that skipped it would leave a stale CMS change on screen.
      refreshHomeData(ref),
      ref.read(platformPricingProvider.notifier).refresh(),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Warm the deposit config here rather than in main(): Home is mounted at
    // app entry, so the fetch is long finished by the time the patient reaches
    // checkout, and no `await` lands on the cold-start path.
    ref.watch(platformPricingProvider);
    final selected = ref.watch(selectedCategorySlugProvider);
    final hd = HomeDark.of(context);

    // Height of the frosted header's content row (below the status bar). The
    // brand lockup is a two-line stack, so it needs a touch more room than
    // the old single-line greeting.
    //
    // Both rows are text-driven — a two-line wordmark above a rail of pills
    // that are themselves up to two lines — so the box has to follow the
    // system text scale. Pinned at 60/46 it clipped the moment a patient
    // turned type up. Measured off a 14 dp label (the size both the caption
    // and the pill labels sit near) and clamped: past ~1.3 the header starts
    // eating the fold, and the rows ellipsize from there anyway.
    final double textScale = (MediaQuery.textScalerOf(context).scale(14) / 14)
        .clamp(1.0, 1.3);
    final double headerContent = 60 * textScale;
    final double railHeight = kCategoryRailHeight * textScale;
    final double topInset = MediaQuery.of(context).padding.top;
    // The rail now lives inside the glass bar, so the header owns its height
    // and the body has to clear the whole stack — the hairline included.
    final double headerTotal =
        headerContent + _kRailGap + railHeight + _kRailBottomPad;
    final double bodyTop = topInset + headerTotal + kGlassBarBorder + 12;

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
              // The header offset is handed to each view rather than applied
              // here, because the two need it in different forms: the
              // dashboard wants it as scroll padding so its content still
              // flows *under* the frosted bar and blurs through it, while the
              // category listing wants a genuine bounded box that starts below
              // the header.
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeIn,
                // Keyed by *view*, not by slug: moving between two categories
                // should re-render the list in place (the inner switcher
                // animates that), while entering or leaving the dashboard is
                // the real transition.
                child: selected == HomeCategory.allSlug
                    ? _HomeDashboardView(
                        key: const ValueKey('home'),
                        topPadding: bodyTop,
                      )
                    : _CategoryBrowseView(
                        key: const ValueKey('category'),
                        categorySlug: selected,
                        topPadding: bodyTop,
                      ),
              ),
            ),
          ),
        ),
        _GlassTopBar(
          topInset: topInset,
          height: headerTotal,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The brand row keeps the page inset the bar used to apply for
              // it (8 on the right, where the avatar's own padding makes up
              // the difference).
              SizedBox(
                height: headerContent,
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 8, 0),
                  child: _HeaderRow(),
                ),
              ),
              const SizedBox(height: _kRailGap),
              // Admin-managed filter pills. Pinned here rather than left in
              // the scroll body: it is the only way back out of a category
              // view, so it must not be something a patient can scroll away
              // from — and it makes hopping between pills a single tap from
              // anywhere on the page.
              //
              // Handed the scaled height rather than reading the constant
              // itself, so the rail and the box the header reserved for it
              // can never disagree.
              CategoryFilterBar(height: railHeight),
              const SizedBox(height: _kRailBottomPad),
            ],
          ),
        ),
      ],
    );
  }
}

/// Vertical breathing room around the pinned category rail inside the glass
/// header. Named because [PatientHomeScreen] has to add them up to work out
/// where the scroll body starts.
const double _kRailGap = 8;
const double _kRailBottomPad = 10;

/// The hairline under the glass bar.
///
/// Named because it is load-bearing twice over, and silently so. It lives in
/// the bar's `BoxDecoration`, and a decoration border **insets its child** —
/// `BoxDecoration.padding` returns `border.dimensions` — so the bar has to add
/// it back on top of the content height or the last dp gets taken from the
/// `Column`. That is the whole of the "overflowed by 1.00 pixels" bug: the
/// header asked for exactly 124 dp of content, the hairline took one back, and
/// the children had nowhere to put it. It also has to be cleared by the scroll
/// body's top padding, or the first card sits a pixel under the line.
const double kGlassBarBorder = 1;

/// VIEW A — the full dashboard, shown while the "All" pill is selected.
///
/// Everything here is about the catalog as a whole: the promo carousel, the
/// patient's ongoing care, the Care Services block in whatever layout the CMS
/// chose, the admin's server-driven sections, and the support footer.
class _HomeDashboardView extends ConsumerWidget {
  /// Clears the frosted header. Applied as scroll padding, not as a `Padding`
  /// wrapper, so the list keeps flowing full-bleed underneath the glass bar
  /// and visibly blurs through it on the way past.
  final double topPadding;

  const _HomeDashboardView({super.key, required this.topPadding});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeRequest = ref.watch(patientActiveRequestProvider);
    final feedAsync = ref.watch(patientHomeFeedProvider);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      // Horizontal padding is 0 so full-bleed rails (chips, providers) can run
      // edge-to-edge; each block re-applies its own 16 px inset. The bottom
      // pad keeps the last card above the floating nav pill.
      padding: EdgeInsets.fromLTRB(0, topPadding, 0, 24),
      children: [
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
                      sub: PatientActivitiesTab.activeCare,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                OngoingCareCard(
                  request: activeRequest,
                  onTrackDetails: () =>
                      openBookingTracking(context, activeRequest),
                ),
              ],
            ),
          ),
        if (feedAsync.isLoading || activeRequest != null)
          const SizedBox(height: 24),
        // Care Services: the CMS owns its title, its layout
        // (carousel / 2-column grid / list), and — when an admin has
        // curated it — its cards. Carries its own header and insets.
        const CareServicesSection(),
        const SizedBox(height: 24),
        // Admin-managed server-driven sections (carries its own
        // insets/gaps; collapses to zero height when none exist).
        const DynamicHomeSections(),
        const _Inset(child: _QuickHelpCard()),
      ],
    );
  }
}

/// VIEW B — the dedicated category listing.
///
/// A thin wrapper so the switcher has a stable widget to key on while
/// [CategoryServicesView] re-renders underneath for each pill.
class _CategoryBrowseView extends StatelessWidget {
  final String categorySlug;

  /// A real `Padding`, unlike the dashboard's scroll inset: this view is one
  /// full-height list with no chrome of its own, so it wants a box that starts
  /// cleanly below the glass bar. Cards meet the rail at a hard edge here
  /// rather than blurring under it — with nothing but cards on screen, a row
  /// half-dissolved behind the pills reads as a rendering fault.
  final double topPadding;

  const _CategoryBrowseView({
    super.key,
    required this.categorySlug,
    required this.topPadding,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: CategoryServicesView(
        categorySlug: categorySlug,
        // Clears the floating nav pill, same as the dashboard's trailing pad.
        bottomInset: 24,
      ),
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
          // Only the status-bar inset. Horizontal padding is the child's own
          // business now that the bar holds the category rail as well as the
          // brand row — the rail has to bleed to both screen edges, and a
          // padding here would have boxed it in and made it asymmetric.
          padding: EdgeInsets.only(top: topInset),
          // Status bar + content + the hairline. The border is added rather
          // than absorbed: a `BoxDecoration` border insets the child, so
          // without it here [child] would be handed one dp less than the
          // [height] it was measured for and overflow by exactly that.
          height: topInset + height + kGlassBarBorder,
          decoration: BoxDecoration(
            // On web (no backdrop blur) the fill carries the frosting, so it
            // sits more opaque; native keeps the translucent blur look.
            color: hd.canvas.withValues(
              alpha: FrostedSurface.blurSupported ? 0.72 : 0.92,
            ),
            border: Border(
              bottom: BorderSide(color: hd.border, width: kGlassBarBorder),
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
                      style: MtTextStyles.h2.copyWith(color: hd.violetBright),
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
            boxShadow: [BoxShadow(color: hd.glow, blurRadius: 10)],
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

/// Section header for the blocks this screen still owns. Care Services moved
/// its own header into [CareServicesSection] along with the title, which the
/// CMS now supplies — hence no Bengali slot here; the one caller left pairs
/// its title with a [_SectionAction] instead.
class _SectionHeader extends StatelessWidget {
  final String en;

  /// Optional right-aligned action (e.g. "Track ›", "View all ›").
  final Widget? trailing;

  const _SectionHeader({required this.en, this.trailing});

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
        ?trailing,
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
            Icon(Icons.chevron_right_rounded, size: 18, color: hd.violetBright),
          ],
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
      loading: () =>
          const SizedBox(height: _cardHeight, child: _PromoSkeleton()),
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
///
/// The **whole card** is the tap target, not just the CTA button — a promo
/// slide reads as one clickable poster, and patients tap the artwork or the
/// headline at least as often as the button. Both routes run the same
/// [handleBannerTap]. The card is `Material > InkWell > Ink` rather than a
/// plain `Container` so the ripple paints *above* the gradient instead of
/// behind it, and the button keeps its own nested `InkWell` (the inner
/// recognizer wins the arena, so a tap on it fires exactly once).
class _PromoSlideCard extends StatelessWidget {
  final PromoBanner banner;
  final VoidCallback onTap;
  const _PromoSlideCard({required this.banner, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final hasImage = banner.imageUrl != null && banner.imageUrl!.isNotEmpty;
    // A display-only banner gets no tap target anywhere on the card: the
    // dispatcher would no-op, and a ripple that leads nowhere reads as a
    // broken link rather than as "this one is just a poster".
    final action = banner.actionType == BannerActionType.none ? null : onTap;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: action,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: banner.gradient,
            ),
            border: Border.all(color: hd.violetBright.withValues(alpha: 0.35)),
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
                        onTap: action,
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(fallback)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(fallback)));
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
                child: Icon(
                  Icons.phone_in_talk_rounded,
                  color: hd.violetBright,
                  size: 22,
                ),
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
              Icon(Icons.chevron_right_rounded, color: hd.muted, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
