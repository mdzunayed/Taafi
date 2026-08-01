import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors_ext.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../auth/auth_provider.dart';
import '../../doctor/doctor_providers.dart';
import '../../doctor/screens/doctor_profile_screen.dart';
import '../../doctor/services/location_tracking_service.dart';
import '../../notifications/widgets/notification_bell.dart';
import '../../chat/presentation/conversation_inbox_button.dart';
import 'doctor_dashboard_tabs.dart';

/// Doctor Operations Hub shell — the single `/doctor/:name` destination.
///
/// A persistent 3-tab bottom navigation (Assignments · Patient Records ·
/// Performance) under a profile banner whose trailing switch flips the
/// provider's real-time Online/Offline visibility. All content is centred
/// at `maxWidth: 600` so wide browser/tablet viewports don't stretch.
class DoctorMainShell extends ConsumerStatefulWidget {
  const DoctorMainShell({super.key});

  @override
  ConsumerState<DoctorMainShell> createState() => _DoctorMainShellState();
}

class _DoctorMainShellState extends ConsumerState<DoctorMainShell> {
  int _index = 0;
  bool hasActiveAlert = true;

  static const _tabs = [
    AssignmentsTab(),
    PatientRecordsTab(),
    PerformanceTab(),
  ];

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sign out?', style: MtTextStyles.h3),
        content: Text(
          'সাইন আউট করবেন?',
          style: MtTextStyles.bodyMd.copyWith(
              color: ctx.appColors.body, fontFamily: 'Kalpurush'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style:
                TextButton.styleFrom(foregroundColor: ctx.appColors.danger),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // Stop location tracking before tearing down the auth-scoped Dio the
    // tracker depends on.
    await ref.read(locationTrackingServiceProvider).stop();
    if (!mounted) return;
    await ref.read(authTokenProvider.notifier).logout();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final navDestinations = const [
      NavigationDestination(
        icon: Icon(Icons.assignment_outlined),
        selectedIcon: Icon(Icons.assignment),
        label: 'Assignments',
      ),
      NavigationDestination(
        icon: Icon(Icons.folder_shared_outlined),
        selectedIcon: Icon(Icons.folder_shared),
        label: 'Records',
      ),
      NavigationDestination(
        icon: Icon(Icons.insights_outlined),
        selectedIcon: Icon(Icons.insights),
        label: 'Performance',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;

        final bodyContent = Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                _DoctorBanner(
                  onProfile: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DoctorProfileScreen(),
                    ),
                  ),
                  onSignOut: _confirmSignOut,
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: IndexedStack(index: _index, children: _tabs),
                      ),
                      if (hasActiveAlert)
                        const Positioned(
                          left: 16,
                          right: 16,
                          bottom: 16,
                          child: _ActiveCallBanner(),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

        final c = context.appColors;
        return Scaffold(
          backgroundColor: c.canvas,
          body: SafeArea(
            bottom: false,
            child: isDesktop
                ? Row(
                    children: [
                      NavigationRail(
                        backgroundColor: const Color(0xFF0F172A),
                        selectedIndex: _index,
                        onDestinationSelected: (i) {
                          HapticFeedback.lightImpact();
                          setState(() => _index = i);
                        },
                        unselectedLabelTextStyle: MtTextStyles.labelSm.copyWith(color: MtColors.ink3),
                        selectedLabelTextStyle: MtTextStyles.labelSm.copyWith(color: Colors.white),
                        unselectedIconTheme: const IconThemeData(color: MtColors.ink3),
                        selectedIconTheme: const IconThemeData(color: Colors.white),
                        indicatorColor: MtColors.brandSoft.withValues(alpha: 0.2),
                        labelType: NavigationRailLabelType.all,
                        destinations: const [
                          NavigationRailDestination(
                            icon: Icon(Icons.assignment_outlined),
                            selectedIcon: Icon(Icons.assignment),
                            label: Text('Assignments'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.folder_shared_outlined),
                            selectedIcon: Icon(Icons.folder_shared),
                            label: Text('Records'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.insights_outlined),
                            selectedIcon: Icon(Icons.insights),
                            label: Text('Performance'),
                          ),
                        ],
                      ),
                      Expanded(child: bodyContent),
                    ],
                  )
                : bodyContent,
          ),
          bottomNavigationBar: isDesktop
              ? null
              : NavigationBarTheme(
                  data: NavigationBarThemeData(
                    backgroundColor: c.surface,
                    indicatorColor: c.accent.withValues(alpha: 0.15),
                    labelTextStyle: WidgetStateProperty.resolveWith(
                      (states) => MtTextStyles.labelSm.copyWith(
                        color: states.contains(WidgetState.selected)
                            ? c.accent
                            : c.muted,
                      ),
                    ),
                    iconTheme: WidgetStateProperty.resolveWith(
                      (states) => IconThemeData(
                        color: states.contains(WidgetState.selected)
                            ? c.accent
                            : c.muted,
                      ),
                    ),
                  ),
                  child: NavigationBar(
                    height: 66,
                    selectedIndex: _index,
                    onDestinationSelected: (i) {
                      HapticFeedback.lightImpact();
                      setState(() => _index = i);
                    },
                    destinations: navDestinations,
                  ),
                ),
        );
      },
    );
  }
}

/// Profile banner with credentials + the Online/Offline visibility switch.
class _DoctorBanner extends ConsumerWidget {
  final VoidCallback onProfile;
  final VoidCallback onSignOut;
  const _DoctorBanner({required this.onProfile, required this.onSignOut});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final user = ref.watch(currentUserProvider);
    final availability = ref.watch(doctorAvailabilityProvider);
    final online = availability.valueOrNull ?? true;
    final isBusy = availability.isLoading;

    final name = user?.name ?? 'Doctor';
    final firstName = name.replaceFirst('Dr. ', '');
    final credentials = (user?.specialization ?? '').trim();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              InitialsAvatar(
                name: firstName,
                size: 46,
                backgroundColor: c.accent.withValues(alpha: 0.12),
                textColor: c.accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.startsWith('Dr.') ? name : 'Dr. $firstName',
                      style: MtTextStyles.h3.copyWith(color: c.title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      credentials.isEmpty ? 'Care provider' : credentials,
                      style: MtTextStyles.bodySm.copyWith(color: c.body),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const ConversationInboxButton(),
              const SizedBox(width: 8),
              const NotificationBell(),
              IconButton(
                tooltip: 'My profile',
                icon: Icon(Icons.account_circle_outlined,
                    color: c.muted, size: 22),
                onPressed: onProfile,
              ),
              IconButton(
                tooltip: 'Sign out',
                icon: Icon(Icons.logout, color: c.muted, size: 20),
                onPressed: onSignOut,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            decoration: BoxDecoration(
              color: online ? c.positiveBg : c.surfaceHi,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: online ? c.positive : c.muted,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    online
                        ? 'Online · accepting new assignments'
                        : 'Offline · not receiving assignments',
                    style: MtTextStyles.labelMd.copyWith(
                      color: online ? c.positive : c.muted,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: online,
                  activeThumbColor: c.positive,
                  onChanged: isBusy
                      ? null
                      : (_) => ref
                          .read(doctorAvailabilityProvider.notifier)
                          .toggle(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveCallBanner extends StatefulWidget {
  const _ActiveCallBanner();

  @override
  State<_ActiveCallBanner> createState() => _ActiveCallBannerState();
}

class _ActiveCallBannerState extends State<_ActiveCallBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final glow = 0.2 + 0.3 * _ctrl.value;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.redAccent.withValues(alpha: glow),
                blurRadius: 15 + 10 * _ctrl.value,
                spreadRadius: 2,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Material(
        color: const Color(0xFF1E293B), // Dark slate
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '🚨 High-Priority Triage Assigned',
                        style: MtTextStyles.labelLg.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap to review patient details',
                        style: MtTextStyles.bodySm.copyWith(color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
