import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/home_section_providers.dart';
import '../../../core/api/patient_home_repository.dart';
import '../../../core/api/promo_banner_providers.dart';
import '../../../core/api/service_catalog_providers.dart';
import '../../../core/config/support_config.dart';
import '../../../core/models/assigned_nurse.dart';
import '../../../core/models/patient_active_request.dart';
import '../../../core/models/patient_request_status.dart';
import '../../../core/models/promo_banner.dart';
import '../../../core/models/service_catalog_item.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/frosted_surface.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/mt_empty_state.dart';
import '../../../core/widgets/mt_skeleton.dart';
import '../../auth/auth_provider.dart';
import '../../../core/widgets/mt_search_field.dart';
import '../../notifications/widgets/notification_bell.dart';
import '../../chat/presentation/conversation_inbox_button.dart';
import '../navigation/banner_action_dispatcher.dart';
import '../navigation/patient_nav_provider.dart';
import '../new_request/new_request_notifier.dart';
import 'widgets/dynamic_home_sections.dart';
import 'widgets/patient_home_palette.dart';

final _patientMoneyFmt = NumberFormat('#,###', 'en_US');
String _patientMoney(num n) => '৳${_patientMoneyFmt.format(n.round())}';

/// Health-service category filters shown as the chip rail directly under the
/// header. `'All'` is the sentinel that disables filtering; every other label
/// is matched (case-insensitively) against a service's `category` / `title`.
const List<String> _patientCategories = [
  'All',
  'Post-op',
  'Nursing',
  'Vitals',
  'Elderly',
  'Lab',
];

/// Currently-selected category chip. Defaults to `'All'` (show everything).
/// Watched by both the chip rail (to highlight the active pill) and the
/// services grid (to filter its items).
final selectedCategoryProvider = StateProvider<String>((ref) => 'All');

/// Free-text search query from the neon search bar. Watched by the Care
/// Services rail to filter its cards live alongside the category chip.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Extra keywords that should also match a chip beyond the chip label itself,
/// so the free-form backend `category` strings map onto our fixed filter set.
const Map<String, List<String>> _categoryAliases = {
  'Post-op': ['post-op', 'post op', 'postop', 'post-surgery', 'surgery', 'wound'],
  'Nursing': ['nursing', 'nurse'],
  'Vitals': ['vitals', 'vital', 'checkup', 'check-up', 'monitoring'],
  'Elderly': ['elderly', 'senior', 'geriatric', 'aged'],
  'Lab': ['lab', 'laboratory', 'test', 'sample', 'diagnostic'],
};

/// True when [item] belongs to the [category] chip. `'All'` always matches.
bool _serviceMatchesCategory(ServiceCatalogItem item, String category) {
  if (category == 'All') return true;
  final haystack = '${item.category} ${item.title}'.toLowerCase();
  final needles = _categoryAliases[category] ?? [category.toLowerCase()];
  return needles.any(haystack.contains);
}

/// Picks a service-card header icon from the item's category / title keywords,
/// falling back to a generic medical-bag glyph. Uses the same tolerant
/// lowercase matching as [_serviceMatchesCategory].
IconData _serviceIcon(ServiceCatalogItem item) {
  final h = '${item.category} ${item.title}'.toLowerCase();
  bool has(List<String> ks) => ks.any(h.contains);
  if (has(['wound', 'dressing', 'surgery', 'post-op', 'post op', 'postop'])) {
    return Icons.healing_rounded;
  }
  if (has(['vitals', 'vital', 'monitor', 'checkup', 'check-up', 'check up'])) {
    return Icons.monitor_heart_rounded;
  }
  if (has(['lab', 'laboratory', 'sample', 'diagnostic', 'test'])) {
    return Icons.science_rounded;
  }
  if (has(['elderly', 'senior', 'geriatric', 'aged'])) {
    return Icons.elderly_rounded;
  }
  if (has(['nursing', 'nurse'])) return Icons.vaccines_rounded;
  return Icons.medical_services_rounded;
}

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
      Future.sync(() => ref.refresh(activeServicesProvider.future)),
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
                  const SizedBox(height: 14),
                  _Inset(
                    child: MtSearchField(
                      hintText: 'Search services, doctors...',
                      onChanged: (q) =>
                          ref.read(searchQueryProvider.notifier).state = q,
                    ),
                  ),
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
                          _ActiveRequestCard(request: activeRequest),
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
        const ConversationInboxButton(),
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
        itemCount: _patientCategories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final label = _patientCategories[i];
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

/// "YOUR CARE TIMELINE" card. Premium white container with two rows:
///   Row 1 — cream-tinted provider avatar + name/service-description
///           column + light-blue "ON THE WAY" status pill.
///   Row 2 — warm peach band with the brand-orange transit icon, a
///           bold "Arriving in X min" headline, and a brand-orange
///           "Track live →" action that animates the user straight to
///           the Tracking tab on the patient shell.
class _ActiveRequestCard extends ConsumerWidget {
  final PatientActiveRequest request;
  const _ActiveRequestCard({required this.request});

  // --- Status → pill metadata --------------------------------------------

  String get _statusPillLabel {
    switch (request.status) {
      case PatientRequestStatus.pendingReview:
        return 'IN REVIEW';
      case PatientRequestStatus.accepted:
        return 'ASSIGNED';
      case PatientRequestStatus.enRoute:
        return 'ON THE WAY';
      case PatientRequestStatus.arrived:
        return 'ARRIVED';
      case PatientRequestStatus.inService:
        return 'IN SERVICE';
      case PatientRequestStatus.completed:
        return 'COMPLETED';
      case PatientRequestStatus.rejected:
        return 'REJECTED';
      case PatientRequestStatus.cancelled:
        return 'CANCELLED';
    }
  }

  /// Two-tone pill colors tuned for the dark canvas — a translucent tinted
  /// background with a bright foreground. In-flight rows (on-the-way) read
  /// indigo; terminal / pending rows borrow dark status tints.
  ({Color background, Color foreground}) _statusPillColorsFor(HomeDark hd) {
    switch (request.status) {
      case PatientRequestStatus.pendingReview:
        return (
          background: hd.violet.withValues(alpha: 0.18),
          foreground: hd.violetBright,
        );
      case PatientRequestStatus.completed:
      case PatientRequestStatus.inService:
        return (
          background: hd.positiveBg,
          foreground: hd.positive,
        );
      case PatientRequestStatus.rejected:
      case PatientRequestStatus.cancelled:
        return (
          background: hd.dangerBg,
          foreground: hd.danger,
        );
      case PatientRequestStatus.accepted:
      case PatientRequestStatus.enRoute:
      case PatientRequestStatus.arrived:
        return (
          background: hd.indigo.withValues(alpha: 0.20),
          foreground: hd.violetBright,
        );
    }
  }

  /// Live-context headline shown on the warm bottom strip. ETA-aware
  /// when the backend supplied one; otherwise a status-derived fallback
  /// so the strip is never empty.
  String get _liveContextHeadline {
    final eta = request.etaMinutes;
    if (eta != null && eta > 0) return 'Arriving in $eta min';
    switch (request.status) {
      case PatientRequestStatus.pendingReview:
        return 'Confirming your booking…';
      case PatientRequestStatus.accepted:
        return 'Doctor confirmed';
      case PatientRequestStatus.enRoute:
        return 'Doctor is on the way';
      case PatientRequestStatus.arrived:
        return 'Doctor arrived';
      case PatientRequestStatus.inService:
        return 'Visit in progress';
      case PatientRequestStatus.completed:
        return 'Visit completed';
      case PatientRequestStatus.rejected:
        return 'Request rejected';
      case PatientRequestStatus.cancelled:
        return 'Request cancelled';
    }
  }

  /// Service-description subtitle ("Post-op wound care · with nurse")
  /// stitched from the service title plus any helper / nurse presence
  /// the backend reports on the active row.
  String get _providerSubtitle {
    final parts = <String>[];
    if (request.serviceTitleEn.isNotEmpty) parts.add(request.serviceTitleEn);
    if (parts.isEmpty && request.providerSpecialization != null) {
      parts.add(request.providerSpecialization!);
    }
    if (request.assignedNurse != null) {
      parts.add('with nurse');
    }
    return parts.join(' · ');
  }

  void _onTrackLive(WidgetRef ref) {
    switch (request.status.homeRouteTarget) {
      case HomeRouteTarget.underReview:
        ref.goToActivities(sub: PatientActivitiesTab.underReview);
        break;
      case HomeRouteTarget.tracking:
        ref.goToActivities(sub: PatientActivitiesTab.tracking);
        break;
      case HomeRouteTarget.none:
        // Terminal rows don't have a deep-link target — degrade to
        // the under-review sub-tab so the user can read the summary.
        ref.goToActivities(sub: PatientActivitiesTab.underReview);
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hd = HomeDark.of(context);
    final pill = _statusPillColorsFor(hd);
    final providerName = request.providerName ?? 'Awaiting doctor assignment';
    final showLiveBar = request.status != PatientRequestStatus.cancelled &&
        request.status != PatientRequestStatus.rejected;

    return Container(
      decoration: BoxDecoration(
        color: hd.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hd.glow),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- Row 1: provider info + status pill ----------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CreamProviderAvatar(
                  name: providerName,
                  photoUrl: request.providerAvatarUrl,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        providerName,
                        style: MtTextStyles.labelLg.copyWith(
                          color: hd.title,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_providerSubtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          _providerSubtitle,
                          style: MtTextStyles.bodySm.copyWith(
                            color: hd.body,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _StatusPill(
                  label: _statusPillLabel,
                  background: pill.background,
                  foreground: pill.foreground,
                ),
              ],
            ),
          ),

          // ---- Row 1b: paired nurse sub-row ---------------------------
          // Renders directly under the doctor row when a nurse is
          // assigned, so the patient sees their whole care team at a
          // glance without leaving the home tab.
          if (request.assignedNurse != null)
            _AssignedNurseRow(nurse: request.assignedNurse!),

          // ---- Row 2: warm peach context bar ---------------------------
          if (showLiveBar)
            _LiveContextBar(
              headline: _liveContextHeadline,
              onTrackLive: () => _onTrackLive(ref),
            ),
        ],
      ),
    );
  }
}

/// Compact "Nurse Aliya · ICU Care" row rendered under the doctor row
/// inside the YOUR CARE TIMELINE card. Same cream/brown avatar as the
/// doctor row + a small "Nurse" badge so the role is visually distinct.
class _AssignedNurseRow extends StatelessWidget {
  final AssignedNurse nurse;
  const _AssignedNurseRow({required this.nurse});

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final subtitle = nurse.specialty.isNotEmpty
        ? nurse.specialty
        : (nurse.yearsExperience > 0
            ? '${nurse.yearsExperience}y experience'
            : 'Nursing care');
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: hd.border)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _CreamProviderAvatar(
            name: nurse.fullName,
            photoUrl: nurse.profilePicture,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Nurse ${nurse.fullName}',
                        style: MtTextStyles.labelMd.copyWith(
                          color: hd.title,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (nurse.isVerifiedNurse) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.verified,
                          size: 14, color: hd.violetBright),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: MtTextStyles.bodySm.copyWith(color: hd.body),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const _NurseRoleChip(),
        ],
      ),
    );
  }
}

/// Small pill that says "NURSE" — reused on the active card sub-row
/// and on the recent providers list to flag nurse rows distinctly.
class _NurseRoleChip extends StatelessWidget {
  const _NurseRoleChip();

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: hd.violet.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'NURSE',
        style: MtTextStyles.labelSm.copyWith(
          color: hd.violetBright,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Dark violet-tinted circle with bright-violet initials. Falls back to a
/// network avatar when the backend has a photo for the assigned doctor.
class _CreamProviderAvatar extends StatelessWidget {
  static const double _size = 44;

  final String name;
  final String? photoUrl;
  const _CreamProviderAvatar({required this.name, this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final cream = hd.surfaceHi;
    final brown = hd.violetBright;
    final cleaned = name.replaceFirst(RegExp(r'^[Dd]r\.?\s+'), '');
    final src = photoUrl;
    if (src != null && src.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          src,
          width: _size,
          height: _size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => InitialsAvatar(
            name: cleaned,
            size: _size,
            backgroundColor: cream,
            textColor: brown,
          ),
        ),
      );
    }
    return InitialsAvatar(
      name: cleaned,
      size: _size,
      backgroundColor: cream,
      textColor: brown,
    );
  }
}

/// Pill-shaped chip: small leading dot + bold uppercase label. Both
/// inherit the same foreground color so a missing status mapping never
/// produces a half-styled chip.
class _StatusPill extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  const _StatusPill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: foreground,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: MtTextStyles.labelSm.copyWith(
              color: foreground,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Raised violet-tinted strip with the transit icon + bold ETA headline +
/// "Track live →" CTA. Tapping the trailing action deep-links to the
/// tracking tab via [_ActiveRequestCard._onTrackLive].
class _LiveContextBar extends StatelessWidget {
  final String headline;
  final VoidCallback onTrackLive;

  const _LiveContextBar({required this.headline, required this.onTrackLive});

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return Container(
      decoration: BoxDecoration(
        color: hd.surfaceHi,
        border: Border(top: BorderSide(color: hd.border)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          Icon(
            Icons.directions_car_outlined,
            size: 18,
            color: hd.violetBright,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              headline,
              style: MtTextStyles.labelMd.copyWith(
                color: hd.title,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: onTrackLive,
            style: TextButton.styleFrom(
              foregroundColor: hd.violetBright,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Track live',
                  style: MtTextStyles.labelMd.copyWith(
                    color: hd.violetBright,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward,
                    size: 16, color: hd.violetBright),
              ],
            ),
          ),
        ],
      ),
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

  static const double _railHeight = 190;
  static const double _wideBreakpoint = 700;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(activeServicesProvider);
    final category = ref.watch(selectedCategoryProvider);
    final query = ref.watch(searchQueryProvider).trim().toLowerCase();
    final bool wide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;

    return AsyncValueView<List<ServiceCatalogItem>>(
      value: async,
      onRetry: () => ref.refresh(activeServicesProvider),
      // The skeleton is a horizontal rail, so it needs a bounded height in
      // both modes; the data branch bounds only the carousel, letting the
      // grid grow to as many rows as it needs.
      loadingBuilder: (_) => const SizedBox(
        height: _railHeight,
        child: _ServicesGridSkeleton(),
      ),
      // Never treat the raw list as empty here — an empty *filtered* result
      // is handled inside dataBuilder so the "no matches" copy can name the
      // active category chip / search term.
      isEmpty: (list) => false,
      emptyBuilder: (_) => const SizedBox.shrink(),
      dataBuilder: (_, items) {
        final filtered = [
          for (final item in items)
            if (_serviceMatchesCategory(item, category) &&
                (query.isEmpty ||
                    '${item.title} ${item.category} ${item.description}'
                        .toLowerCase()
                        .contains(query)))
              item,
        ];
        if (filtered.isEmpty) {
          final bool searching = query.isNotEmpty;
          return _Inset(
            child: MtEmptyState(
              icon: searching
                  ? Icons.search_off_rounded
                  : Icons.medical_services_outlined,
              title: searching
                  ? 'No matches for “$query”'
                  : category == 'All'
                      ? 'No services available yet'
                      : 'No $category services yet',
              subtitle: searching
                  ? 'Try a different search or category.'
                  : category == 'All'
                      ? 'Check back soon — new services are added regularly.'
                      : 'Try another category or check back soon.',
            ),
          );
        }
        return wide
            ? _Inset(child: _ServicesFluidGrid(items: filtered))
            : SizedBox(
                height: _railHeight,
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
        // Keeps tile proportions close to the mobile rail's ~226×190 (2 cols)
        // and the 150×190 skeleton card (3 cols) inside the 600px column.
        childAspectRatio: cols == 3 ? 0.95 : 1.30,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _AnimatedCareServiceCard(item: items[i]),
    );
  }
}

/// Flush-edge horizontal rail for the Care Services cards. The 16 px inset
/// lives *inside* the ListView, so at rest the first card aligns with the
/// section header while mid-swipe the cards clip flush against the screen
/// edge. Only the loaded, non-empty list reaches here; the async / filter /
/// empty-state branches stay in [_ServicesGrid].
class _ServicesCarousel extends StatelessWidget {
  /// Fixed card footprint on the rail (the rail's 190 px height comes from
  /// the parent SizedBox in [_ServicesGrid]).
  static const double _railCardWidth = 220;

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
        width: _railCardWidth,
        child: _AnimatedCareServiceCard(item: items[i]),
      ),
    );
  }
}

/// Animated two-tone Care Services card. A tactile press shrinks it to 0.96
/// (glow dimming) and springs back with an `elasticOut` bounce; a faint glass
/// shimmer sweeps the image header periodically. Sized by its parent — the
/// [_ServicesCarousel] rail slot or a [_ServicesFluidGrid] cell.
class _AnimatedCareServiceCard extends ConsumerStatefulWidget {
  final ServiceCatalogItem item;
  const _AnimatedCareServiceCard({required this.item});

  @override
  ConsumerState<_AnimatedCareServiceCard> createState() =>
      _AnimatedCareServiceCardState();
}

class _AnimatedCareServiceCardState
    extends ConsumerState<_AnimatedCareServiceCard>
    with TickerProviderStateMixin {
  // Press-scale controller; `_scale` is re-tweened per gesture so press-in
  // (easeOut) and spring-back (elasticOut) can use different curves.
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  Animation<double> _scale = const AlwaysStoppedAnimation(1.0);

  // Perpetual, gentle shimmer sweep across the image header.
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3500),
  )..repeat();

  @override
  void dispose() {
    _press.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    _scale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _press, curve: Curves.easeOut),
    );
    _press
      ..duration = const Duration(milliseconds: 120)
      ..reset()
      ..forward();
  }

  void _onTapRelease() {
    _scale = Tween<double>(begin: 0.96, end: 1.0).animate(
      CurvedAnimation(parent: _press, curve: Curves.elasticOut),
    );
    _press
      ..duration = const Duration(milliseconds: 450)
      ..reset()
      ..forward();
  }

  /// Pre-selects this card's service in the booking form and jumps straight
  /// to the New Request tab — no intermediate detail screen.
  void _bookService() {
    ref.read(newRequestProvider.notifier).applyServicePrefill(widget.item, fromLink: true);
    ref.goToNewRequest();
  }

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return AnimatedBuilder(
      animation: _press,
      builder: (context, child) {
        final scale = _scale.value;
        // 0 (released) .. 1 (fully pressed) — dims the glow on press.
        final pressed = ((1.0 - scale) / 0.04).clamp(0.0, 1.0);
        return Transform.scale(
          scale: scale,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color:
                      hd.violet.withValues(alpha: 0.30 * (1 - pressed)),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: _cardBody(),
    );
  }

  Widget _cardBody() {
    final hd = HomeDark.of(context);
    final item = widget.item;
    final hasCategory = item.category.trim().isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      // Material + InkWell replace the old DecoratedBox/GestureDetector pair
      // so taps get a ripple clipped to the card's 24px corners. The InkWell
      // also drives the press-scale controller, keeping the squash animation.
      child: Material(
        color: hd.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: hd.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTapDown: _onTapDown,
          onTapCancel: _onTapRelease,
          onTap: () {
            _onTapRelease();
            _bookService();
          },
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- Top: photo / gradient+icon, badge, shimmer sweep ----
            Expanded(
              flex: 5,
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    (item.imageUrl == null || item.imageUrl!.isEmpty)
                        ? _ServiceHeaderFallback(icon: _serviceIcon(item))
                        : CachedNetworkImage(
                            imageUrl: item.imageUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => const _ServiceHeaderFallback(),
                            errorWidget: (_, _, _) =>
                                _ServiceHeaderFallback(icon: _serviceIcon(item)),
                          ),
                    _ShimmerSweep(animation: _shimmer),
                    if (hasCategory)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: hd.canvas.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.category,
                            style: MtTextStyles.labelSm.copyWith(
                              color: Colors.white,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // ---- Bottom: obsidian block, name + price + emerald "+" ----
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: MtTextStyles.labelLg
                                .copyWith(color: hd.title),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'from ${_patientMoney(item.price)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            // Monospace + tabular figures for a clean, legible
                            // price string.
                            style: MtTextStyles.timer.copyWith(
                              color: hd.muted,
                              fontFeatures: const [
                                ui.FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Quick-add — same direct-booking action as tapping the
                    // card body; presses independently (its own gesture wins
                    // the arena over the card's InkWell).
                    _AddServiceButton(onTap: _bookService),
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

/// A faint diagonal light sweep that glides across the card header on a gentle
/// repeat, then rests off-screen — the "living" glass shimmer. Purely
/// decorative, so it ignores pointers.
class _ShimmerSweep extends StatelessWidget {
  final Animation<double> animation;
  const _ShimmerSweep({required this.animation});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          // Sweep only during the first ~45% of the cycle; the band then sits
          // off the right edge for the rest (a brief rest between sweeps).
          final t = const Interval(0.0, 0.45, curve: Curves.easeInOut)
              .transform(animation.value);
          return FractionalTranslation(
            translation: Offset(-1.0 + 2.0 * t, 0),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0x00FFFFFF),
                    Color(0x1AFFFFFF), // white @ ~10%
                    Color(0x00FFFFFF),
                  ],
                  stops: [0.35, 0.5, 0.65],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Vivid violet gradient header used behind a service card — shown on its own
/// (with the service's mapped icon) when there's no photo, and as the
/// placeholder / error state while a photo loads or fails.
class _ServiceHeaderFallback extends StatelessWidget {
  final IconData? icon;
  const _ServiceHeaderFallback({this.icon});

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [hd.violet2, hd.violetDeep],
        ),
      ),
      child: icon == null
          ? null
          : Center(child: Icon(icon, color: Colors.white, size: 40)),
    );
  }
}

/// Small circular "+" affordance on a service card — an emerald-teal glyph on
/// a translucent-teal disc with a thin teal ring. Presses **independently** of
/// the card: its own gesture wins the arena, and it has its own scale-down +
/// elastic spring-back so the button feels tactile on its own.
class _AddServiceButton extends StatefulWidget {
  final VoidCallback onTap;
  const _AddServiceButton({required this.onTap});

  @override
  State<_AddServiceButton> createState() => _AddServiceButtonState();
}

class _AddServiceButtonState extends State<_AddServiceButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );
  Animation<double> _scale = const AlwaysStoppedAnimation(1.0);

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _down(TapDownDetails _) {
    _scale = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _press, curve: Curves.easeOut),
    );
    _press
      ..duration = const Duration(milliseconds: 110)
      ..reset()
      ..forward();
  }

  void _up() {
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _press, curve: Curves.elasticOut),
    );
    _press
      ..duration = const Duration(milliseconds: 400)
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return GestureDetector(
      onTapDown: _down,
      onTapUp: (_) => _up(),
      onTapCancel: _up,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _press,
        builder: (context, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: hd.teal.withValues(alpha: 0.18),
            shape: BoxShape.circle,
            border: Border.all(color: hd.teal, width: 1),
          ),
          child: Icon(Icons.add_rounded, color: hd.teal, size: 20),
        ),
      ),
    );
  }
}

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
        width: _ServicesCarousel._railCardWidth,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: hd.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: hd.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: ColoredBox(
                color: hd.violet.withValues(alpha: 0.16),
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    MtSkeleton.line(width: 90),
                    const SizedBox(height: 8),
                    MtSkeleton.line(width: 60, height: 10),
                  ],
                ),
              ),
            ),
          ],
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
