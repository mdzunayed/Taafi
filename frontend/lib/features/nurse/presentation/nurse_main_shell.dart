import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/socket_manager.dart';
import '../../../core/theme/app_colors_ext.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../auth/auth_provider.dart';
import '../../navigation/presentation/widgets/custom_floating_navbar.dart';
import '../../notifications/widgets/notification_bell.dart';
import '../../provider/presentation/nurse_dashboard_tabs.dart';
import '../../provider/presentation/provider_wallet_page.dart';
import '../../provider/providers/nurse_workflow_provider.dart';
import 'controllers/nurse_nav_controller.dart';
import 'nurse_profile_screen.dart';

// ── Nurse-module identity palette ───────────────────────────────────────────
// Dark chrome reserved for the ALWAYS-DARK surfaces (rail / wordmark tile /
// flash-banner gradient) which keep the same look in both themes — deliberate
// design intent, like the floating navbar pill. Every adaptive surface reads
// `context.appColors` tokens instead; on-duty/online semantics use
// `appColors.positive`.
const Color _kIndigo = MtColors.ink; // dark-slate foundation (chrome only)
const Color _kIndigoSoft = Color(0xFF1E293B); // slate-800 (chrome only)
const Color _kMint = MtColors.brand; // accent on dark chrome → burnt orange

/// Width at/above which the shell promotes the mobile floating bottom bar
/// into a left-anchored [NavigationRail] (tablet / desktop-web layouts).
const double _kRailBreakpoint = 720;

/// One descriptor per destination — shared by the rail and the floating bar so
/// the two navigation surfaces can never drift in label, icon or order.
class _NavDest {
  final IconData icon;
  final String label;
  const _NavDest(this.icon, this.label);
}

const List<_NavDest> _kDestinations = [
  _NavDest(Icons.local_shipping_rounded, 'Dispatches'),
  _NavDest(Icons.history_toggle_off_rounded, 'History'),
  _NavDest(Icons.account_balance_wallet_rounded, 'Wallet'),
  _NavDest(Icons.person_rounded, 'Profile'),
];

/// The Nurse Operations shell — the single `/nurse/:name` destination.
///
/// An adaptive navigation scaffold: a modern floating bottom bar on phones
/// that morphs into an elegant [NavigationRail] on wide viewports. The active
/// tab is owned by [nurseNavProvider] so descendants (e.g. the Profile
/// console) can drive navigation without callback threading. An assertive,
/// pulsing flash banner overlays the workspace whenever an emergency dispatch
/// is waiting and the nurse is looking at a different tab.
class NurseMainShell extends ConsumerWidget {
  const NurseMainShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Live-refresh the Dispatches board the instant an admin assigns a job.
    // `nurseDashboardProvider` is a plain FutureProvider (no poll), so without
    // this a freshly-assigned nurse job wouldn't surface until a manual pull-
    // to-refresh. `dispatch:incoming` fires for the nurse's own room on
    // assignment; invalidating the dashboard cascades to the incoming-count
    // badge + flash banner, which both derive from it.
    ref.listen<DispatchAlert?>(dispatchAlertProvider, (prev, next) {
      if (next != null) ref.invalidate(nurseDashboardProvider);
    });

    final index = ref.watch(nurseNavProvider);
    final incoming = ref.watch(nurseIncomingCountProvider);
    final nav = ref.read(nurseNavProvider.notifier);
    final wide = MediaQuery.sizeOf(context).width >= _kRailBreakpoint;

    final content = _ContentArea(index: index, incoming: incoming);

    return Scaffold(
      backgroundColor: context.appColors.canvas,
      body: SafeArea(
        bottom: false,
        child: wide
            ? Row(
                children: [
                  _NurseRail(
                    index: index,
                    incoming: incoming,
                    onSelect: nav.select,
                  ),
                  VerticalDivider(
                      width: 1, color: context.appColors.cardBorder),
                  Expanded(child: content),
                ],
              )
            : content,
      ),
      bottomNavigationBar: wide
          ? null
          : CustomFloatingNavBar(
              currentIndex: index,
              onTap: nav.select,
              items: [
                for (var i = 0; i < _kDestinations.length; i++)
                  FloatingNavItem(
                    icon: _kDestinations[i].icon,
                    label: _kDestinations[i].label,
                    badgeCount: i == NurseTab.dispatches ? incoming : 0,
                  ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Content area — header + tabs + the active-job flash overlay
// ─────────────────────────────────────────────────────────────────────────────

class _ContentArea extends ConsumerWidget {
  final int index;
  final int incoming;
  const _ContentArea({required this.index, required this.incoming});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The flash only fires for an emergency dispatch the nurse can't already
    // see — i.e. they're parked on another tab. On the Dispatches board itself
    // the offer card is the call-to-action, so the banner would be noise.
    final showFlash = incoming > 0 && index != NurseTab.dispatches;

    return Column(
      children: [
        const _NurseHeader(),
        Expanded(
          child: Stack(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: IndexedStack(
                    index: index,
                    children: const [
                      _DispatchesView(),
                      TaskHistoryTab(),
                      ProviderWalletPage(),
                      NurseProfileScreen(),
                    ],
                  ),
                ),
              ),
              if (showFlash)
                Positioned(
                  top: 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 620),
                        child: _ActiveJobFlashBanner(
                          count: incoming,
                          onTap: () =>
                              ref.read(nurseNavProvider.notifier).openDispatches(),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Slim workspace header — module wordmark, signed-in nurse name + the
/// notification bell. Deliberately light so the tab content reads as the focus.
class _NurseHeader extends ConsumerWidget {
  const _NurseHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final name = user?.name ?? 'Nurse';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_kIndigo, _kIndigoSoft],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.health_and_safety_rounded,
                color: _kMint, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NURSE OPERATIONS',
                    style: MtTextStyles.labelSm.copyWith(
                        color: context.appColors.muted, letterSpacing: 1.1)),
                Text(
                  name,
                  style:
                      MtTextStyles.h3.copyWith(color: context.appColors.title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const NotificationBell(),
        ],
      ),
    );
  }
}

/// Tab 1 view = the on-duty toggle stacked above the reused Dispatches feed.
class _DispatchesView extends StatelessWidget {
  const _DispatchesView();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _DutyToggleCard(),
        Expanded(child: DispatchesTab()),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Duty toggle — flips remote discoverability for dispatches
// ─────────────────────────────────────────────────────────────────────────────

class _DutyToggleCard extends ConsumerWidget {
  const _DutyToggleCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final availability = ref.watch(nurseAvailabilityProvider);
    final online = availability.valueOrNull ?? false;
    final busy = availability.isLoading;
    final c = context.appColors;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: online ? c.positiveBg : c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: online ? c.positive : c.cardBorder),
      ),
      child: Row(
        children: [
          Icon(
            online ? Icons.bolt_rounded : Icons.bolt_outlined,
            size: 20,
            color: online ? c.positive : c.muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              online
                  ? 'On duty · discoverable for dispatches'
                  : 'Off duty · not receiving dispatches',
              style: MtTextStyles.labelMd.copyWith(
                color: online ? c.positive : c.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Switch.adaptive(
            value: online,
            activeThumbColor: c.positive,
            activeTrackColor: c.positive.withValues(alpha: 0.4),
            onChanged: busy
                ? null
                : (_) {
                    // Tactile confirmation, then flip the remote availability
                    // flag (and start/stop GPS streaming) on the server.
                    HapticFeedback.lightImpact();
                    ref.read(nurseAvailabilityProvider.notifier).toggle();
                  },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Active-job flash banner — pulsing emergency alert (TweenAnimationBuilder)
// ─────────────────────────────────────────────────────────────────────────────

class _ActiveJobFlashBanner extends StatefulWidget {
  final int count;
  final VoidCallback onTap;
  const _ActiveJobFlashBanner({required this.count, required this.onTap});

  @override
  State<_ActiveJobFlashBanner> createState() => _ActiveJobFlashBannerState();
}

class _ActiveJobFlashBannerState extends State<_ActiveJobFlashBanner> {
  // Ping-pong target the TweenAnimationBuilder drives toward; flipped in
  // `onEnd` to produce a continuous, breathing glow without an explicit
  // AnimationController.
  double _target = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _target = 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.count == 1
        ? 'New emergency dispatch · tap to respond'
        : '${widget.count} dispatches waiting · tap to respond';

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: _target),
      duration: const Duration(milliseconds: 850),
      curve: Curves.easeInOut,
      onEnd: () {
        if (mounted) setState(() => _target = _target == 1 ? 0 : 1);
      },
      builder: (context, t, child) {
        return Transform.scale(
          scale: 1 + 0.015 * t,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_kMint, MtColors.brand700],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _kMint.withValues(alpha: 0.30 + 0.45 * t),
                  blurRadius: 14 + 20 * t,
                  spreadRadius: 1 + 2 * t,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.mediumImpact();
            widget.onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.notifications_active_rounded,
                    color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: MtTextStyles.labelLg.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded,
                    color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wide-layout navigation rail
// ─────────────────────────────────────────────────────────────────────────────

class _NurseRail extends StatelessWidget {
  final int index;
  final int incoming;
  final ValueChanged<int> onSelect;
  const _NurseRail({
    required this.index,
    required this.incoming,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      backgroundColor: _kIndigo,
      selectedIndex: index,
      onDestinationSelected: onSelect,
      labelType: NavigationRailLabelType.all,
      groupAlignment: -0.85,
      indicatorColor: _kMint.withValues(alpha: 0.22),
      selectedIconTheme: const IconThemeData(color: _kMint),
      unselectedIconTheme:
          IconThemeData(color: Colors.white.withValues(alpha: 0.55)),
      selectedLabelTextStyle:
          MtTextStyles.labelSm.copyWith(color: _kMint, fontWeight: FontWeight.w800),
      unselectedLabelTextStyle: MtTextStyles.labelSm
          .copyWith(color: Colors.white.withValues(alpha: 0.55)),
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.health_and_safety_rounded,
              color: _kMint, size: 24),
        ),
      ),
      destinations: [
        for (var i = 0; i < _kDestinations.length; i++)
          NavigationRailDestination(
            icon: _RailIcon(
              icon: _kDestinations[i].icon,
              badge: i == NurseTab.dispatches ? incoming : 0,
            ),
            label: Text(_kDestinations[i].label),
          ),
      ],
    );
  }
}

class _RailIcon extends StatelessWidget {
  final IconData icon;
  final int badge;
  const _RailIcon({required this.icon, required this.badge});

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: badge > 0,
      label: Text('$badge'),
      backgroundColor: context.appColors.danger,
      child: Icon(icon),
    );
  }
}

