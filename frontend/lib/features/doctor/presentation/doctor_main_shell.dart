import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/doctor_dashboard.dart';
import '../../../core/network/socket_manager.dart';
import '../../../core/theme/app_colors_ext.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../auth/auth_provider.dart';
import '../../navigation/presentation/widgets/custom_floating_navbar.dart';
import '../../prescriptions/prescription_entry.dart';
import '../../provider/presentation/doctor_dashboard_tabs.dart';
import '../../provider/presentation/provider_wallet_page.dart';
import '../doctor_providers.dart';
import '../screens/doctor_profile_screen.dart';
import 'controllers/doctor_nav_controller.dart';

// ───────────────────────────────────────────────────────────────────────────
// Dark chrome reserved for the ALWAYS-DARK surfaces of this shell — the wide
// navigation rail and the active-call banner keep a deep-slate look in both
// themes (deliberate design intent, like the floating navbar pill). Every
// adaptive surface below reads `context.appColors` tokens instead so light
// values can't leak into dark mode.
// ───────────────────────────────────────────────────────────────────────────
const Color _slate = Color(0xFF0F172A);
const Color _slate700 = Color(0xFF1E293B);
const Color _slate400 = Color(0xFF94A3B8);
const Color _coral = Color(0xFFF43F5E);

/// Premium, adaptive application shell for the Doctor role. Serves a
/// floating bottom navigation bar on phones and an elegant slate
/// `NavigationRail`-style mini-sidebar on tablet / web. Hosts the five
/// specialised clinical modules, a live-engagement pulse banner, the BMDC
/// verification tag, and a haptic layer on every tab transition.
class DoctorMainShell extends ConsumerWidget {
  const DoctorMainShell({super.key});

  /// The workspace bodies, index-aligned with [DoctorTab]. `const` so the
  /// [IndexedStack] preserves each module's scroll position + state across
  /// tab switches with zero rebuild.
  static const List<Widget> _bodies = [
    AppointmentsPanel(),
    PatientRecordsTab(),
    SmartPrescriberPanel(),
    ScheduleSlotsPanel(),
    PerformanceTab(),
    ProviderWalletPage(),
  ];

  /// Single tab-change entry point — fires a crisp haptic tick before
  /// committing the selection, giving every transition a tactile feel.
  void _select(WidgetRef ref, int index) {
    HapticFeedback.lightImpact();
    ref.read(doctorNavProvider.notifier).select(index);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Live-refresh the workspace the instant an admin assigns this doctor —
    // same contract the nurse shell honours. `dispatch:incoming` lands in the
    // doctor's own room on assignment, and invalidating here pulls the new
    // visit into Appointments (and the triage badge) in the same beat as the
    // dispatch banner, instead of waiting out the 10s dashboard poll.
    ref.listen<DispatchAlert?>(dispatchAlertProvider, (prev, next) {
      if (next != null) ref.invalidate(doctorDashboardProvider);
    });

    final index = ref.watch(doctorNavProvider);
    final alert = ref.watch(doctorLiveAlertProvider);
    final pendingTriage = ref.watch(pendingTriageCountProvider);
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      backgroundColor: context.appColors.canvas,
      body: SafeArea(
        child: Row(
          children: [
            if (isWide)
              _DoctorRail(
                index: index,
                onSelect: (i) => _select(ref, i),
              ),
            Expanded(
              child: Column(
                children: [
                  _DoctorHeader(compact: !isWide),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: IndexedStack(index: index, children: _bodies),
                        ),
                        // Live-engagement banner — pinned to the base of the
                        // content area above whatever nav surface is showing.
                        if (alert != null)
                          Positioned(
                            left: 16,
                            right: 16,
                            bottom: 16,
                            child: _ActiveCallBanner(
                              alert: alert,
                              onTap: () => _select(ref, alert.target.index),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: isWide
          ? null
          : CustomFloatingNavBar(
              currentIndex: index,
              onTap: (i) => _select(ref, i),
              items: [
                for (final tab in DoctorTab.values)
                  FloatingNavItem(
                    icon: tab.icon,
                    activeIcon: tab.selectedIcon,
                    label: tab.label,
                    badgeCount:
                        tab == DoctorTab.appointments ? pendingTriage : 0,
                  ),
              ],
            ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Wide layout — slate mini-sidebar / rail
// ───────────────────────────────────────────────────────────────────────────

class _DoctorRail extends ConsumerWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const _DoctorRail({required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingTriage = ref.watch(pendingTriageCountProvider);
    final online = ref.watch(doctorAvailabilityProvider).valueOrNull ?? true;
    final user = ref.watch(currentUserProvider);

    return Container(
      width: 98,
      color: _slate,
      child: Column(
        children: [
          const SizedBox(height: 20),
          // App mark.
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: context.appColors.accent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.medical_services_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final tab in DoctorTab.values)
                  _RailItem(
                    tab: tab,
                    selected: tab.index == index,
                    badge: tab == DoctorTab.appointments ? pendingTriage : 0,
                    onTap: () => onSelect(tab.index),
                  ),
              ],
            ),
          ),
          // On-duty indicator + avatar.
          Tooltip(
            message: online ? 'On duty' : 'Off duty',
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: online ? context.appColors.positive : _slate400,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(height: 12),
          InitialsAvatar(
            name: (user?.name ?? 'Dr').replaceFirst('Dr. ', ''),
            size: 36,
            backgroundColor: _slate700,
            textColor: Colors.white,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final DoctorTab tab;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  const _RailItem({
    required this.tab,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.appColors.accent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color:
                selected ? accent.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              _BadgedIcon(
                icon: selected ? tab.selectedIcon : tab.icon,
                color: selected ? accent : _slate400,
                badge: badge,
              ),
              const SizedBox(height: 4),
              Text(
                tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MtTextStyles.labelSm.copyWith(
                  color: selected ? Colors.white : _slate400,
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Icon + count-badge stack used by the wide-layout rail (the compact layout
/// uses [CustomFloatingNavBar], which renders its own badge).
class _BadgedIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int badge;
  const _BadgedIcon({
    required this.icon,
    required this.color,
    required this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, color: color, size: 22),
        if (badge > 0)
          Positioned(
            top: -6,
            right: -8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16),
              decoration: BoxDecoration(
                color: _coral,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _slate, width: 1.5),
              ),
              child: Text(
                badge > 9 ? '9+' : '$badge',
                textAlign: TextAlign.center,
                style: MtTextStyles.labelSm.copyWith(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Header with BMDC verification tag
// ───────────────────────────────────────────────────────────────────────────

class _DoctorHeader extends ConsumerWidget {
  final bool compact;
  const _DoctorHeader({required this.compact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final online = ref.watch(doctorAvailabilityProvider).valueOrNull ?? true;
    final name = user?.name ?? 'Doctor';
    final firstName = name.replaceFirst('Dr. ', '');
    final title = name.startsWith('Dr.') ? name : 'Dr. $firstName';
    final specialization = (user?.specialization ?? '').trim();

    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.cardBorder)),
      ),
      child: Row(
        children: [
          // Avatar doubles as the entry point to the full Profile screen —
          // the only surface that hosts the account menu (Schedule, Earnings,
          // Settings, Logout) and the prominent availability card.
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DoctorProfileScreen(),
                ),
              );
            },
            child: InitialsAvatar(
              name: firstName,
              size: 44,
              backgroundColor: c.accent.withValues(alpha: 0.12),
              textColor: c.accent,
            ),
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
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MtTextStyles.h3.copyWith(color: c.title),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _BmdcTag(verified: user?.isVerified ?? false),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  specialization.isEmpty
                      ? 'Physician · Home & tele care'
                      : specialization,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MtTextStyles.bodySm.copyWith(color: c.body),
                ),
              ],
            ),
          ),
          // Compact duty pill (the full toggle lives in the Schedule tab).
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: online ? c.positiveBg : c.surfaceHi,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: online ? c.positive : c.muted,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  online ? 'On duty' : 'Off duty',
                  style: MtTextStyles.labelSm.copyWith(
                    color: online ? c.positive : c.muted,
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

/// BMDC (Bangladesh Medical & Dental Council) quick-status tag, driven by
/// the account's real verification flag.
class _BmdcTag extends StatelessWidget {
  final bool verified;
  const _BmdcTag({required this.verified});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final fg = verified ? c.accent : c.warning;
    final bg = verified ? c.accent.withValues(alpha: 0.12) : c.warningBg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            verified ? Icons.verified_rounded : Icons.pending_outlined,
            size: 13,
            color: fg,
          ),
          const SizedBox(width: 4),
          Text(
            verified ? 'BMDC Verified' : 'BMDC Pending',
            style: MtTextStyles.labelSm.copyWith(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Active-call / triage pulse banner
// ───────────────────────────────────────────────────────────────────────────

class _ActiveCallBanner extends StatefulWidget {
  final DoctorLiveAlert alert;
  final VoidCallback onTap;
  const _ActiveCallBanner({required this.alert, required this.onTap});

  @override
  State<_ActiveCallBanner> createState() => _ActiveCallBannerState();
}

class _ActiveCallBannerState extends State<_ActiveCallBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.alert.urgent ? _coral : context.appColors.accent;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        // Breathing glow — tracks the controller so the banner reads as a
        // live, attention-seeking element without being jarring.
        final glow = 0.18 + 0.22 * _ctrl.value;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: glow),
                blurRadius: 18 + 8 * _ctrl.value,
                spreadRadius: 1,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Material(
        color: _slate,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                _PulseDot(accent: accent, controller: _ctrl),
                const SizedBox(width: 14),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(widget.alert.icon, color: accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.alert.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MtTextStyles.labelLg.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.alert.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MtTextStyles.bodySm.copyWith(color: _slate400),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: _slate400, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The expanding ring at the banner's leading edge.
class _PulseDot extends StatelessWidget {
  final Color accent;
  final AnimationController controller;
  const _PulseDot({required this.accent, required this.controller});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 6 + 10 * controller.value,
            height: 6 + 10 * controller.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: (1 - controller.value) * 0.5),
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 1 · Appointments — Home Visits / Tele-Consults dual pipeline
// ═══════════════════════════════════════════════════════════════════════════

class AppointmentsPanel extends ConsumerWidget {
  const AppointmentsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segment = ref.watch(appointmentSegmentProvider);
    final pendingTriage = ref.watch(pendingTriageCountProvider);

    return Column(
      children: [
        _SegmentBar(
          segment: segment,
          homeBadge: pendingTriage,
          onChanged: (s) =>
              ref.read(appointmentSegmentProvider.notifier).state = s,
        ),
        Expanded(
          child: segment == AppointmentSegment.homeVisits
              // Physical dispatch pipeline — reuses the proven doctor
              // assignments board (offer card + transit pipeline).
              ? const AssignmentsTab()
              : const _TeleConsultsView(),
        ),
      ],
    );
  }
}

class _SegmentBar extends StatelessWidget {
  final AppointmentSegment segment;
  final int homeBadge;
  final ValueChanged<AppointmentSegment> onChanged;
  const _SegmentBar({
    required this.segment,
    required this.homeBadge,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surfaceHi,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.cardBorder),
      ),
      child: Row(
        children: [
          _SegmentPill(
            label: 'Home Visits',
            icon: Icons.home_work_outlined,
            badge: homeBadge,
            selected: segment == AppointmentSegment.homeVisits,
            onTap: () => onChanged(AppointmentSegment.homeVisits),
          ),
          _SegmentPill(
            label: 'Tele-Consults',
            icon: Icons.videocam_outlined,
            badge: 0,
            selected: segment == AppointmentSegment.teleConsults,
            onTap: () => onChanged(AppointmentSegment.teleConsults),
          ),
        ],
      ),
    );
  }
}

class _SegmentPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final int badge;
  final bool selected;
  final VoidCallback onTap;
  const _SegmentPill({
    required this.label,
    required this.icon,
    required this.badge,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? c.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? c.onAccent : c.body),
              const SizedBox(width: 6),
              Text(
                label,
                style: MtTextStyles.labelMd.copyWith(
                  color: selected ? c.onAccent : c.body,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (badge > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected ? c.onAccent : c.danger,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badge',
                    style: MtTextStyles.labelSm.copyWith(
                      color: selected ? c.accent : c.onAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TeleConsultsView extends StatelessWidget {
  const _TeleConsultsView();

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: c.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.videocam_outlined, color: c.accent, size: 30),
            ),
            const SizedBox(height: 16),
            Text('No virtual consults scheduled',
                style: MtTextStyles.h3.copyWith(color: c.title)),
            const SizedBox(height: 6),
            Text(
              'Open the Schedule tab to publish bookable tele-consult '
              'windows — confirmed video appointments will appear here.',
              textAlign: TextAlign.center,
              style: MtTextStyles.bodySm.copyWith(color: c.muted),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 3 · Smart Prescriber
// ═══════════════════════════════════════════════════════════════════════════

class SmartPrescriberPanel extends ConsumerWidget {
  const SmartPrescriberPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(doctorDashboardProvider);
    return async.when(
      loading: () => Center(
          child:
              CircularProgressIndicator(color: context.appColors.accent)),
      error: (e, _) => _PanelMessage(
        icon: Icons.error_outline,
        title: "Couldn't load visits",
        subtitle: e.toString(),
      ),
      data: (dashboard) {
        final visits = dashboard.upcomingToday
            .where((a) => a.isActive || a.awaitingAcceptance)
            .toList(growable: false);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            _PanelHeader(
              icon: Icons.healing_rounded,
              title: 'Smart Prescriber',
              subtitle:
                  'Build and issue a digital prescription for an active visit.',
            ),
            const SizedBox(height: 16),
            if (visits.isEmpty)
              const _PanelMessage(
                icon: Icons.inbox_outlined,
                title: 'No active visits',
                subtitle:
                    'Prescriptions are written against an in-progress visit. '
                    'Accept a dispatch from the Appointments tab to begin.',
              )
            else
              for (final v in visits) ...[
                _PrescribeCard(appointment: v),
                const SizedBox(height: 10),
              ],
          ],
        );
      },
    );
  }
}

class _PrescribeCard extends ConsumerWidget {
  final UpcomingAppointment appointment;
  const _PrescribeCard({required this.appointment});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = appointment;
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.cardBorder),
      ),
      child: Row(
        children: [
          InitialsAvatar(
            name: a.patientName,
            size: 44,
            backgroundColor: c.accent.withValues(alpha: 0.12),
            textColor: c.accent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.patientName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MtTextStyles.labelLg.copyWith(
                        color: c.title, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(a.serviceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MtTextStyles.bodySm.copyWith(color: c.body)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => openPrescriptionFlow(
              context,
              ref,
              appointmentId: a.id,
              patientAccountId: a.patientAccountId,
              patientName: a.patientName,
              careType: a.serviceName,
            ),
            icon: const Icon(Icons.edit_note_rounded, size: 18),
            label: Text('Prescribe',
                style: MtTextStyles.labelMd.copyWith(color: c.onAccent)),
            style: ElevatedButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: c.onAccent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 4 · Schedule & Slots optimizer
// ═══════════════════════════════════════════════════════════════════════════

class ScheduleSlotsPanel extends ConsumerStatefulWidget {
  const ScheduleSlotsPanel({super.key});

  @override
  ConsumerState<ScheduleSlotsPanel> createState() => _ScheduleSlotsPanelState();
}

class _ScheduleSlotsPanelState extends ConsumerState<ScheduleSlotsPanel> {
  // Bookable tele-consult windows. Managed locally — the doctor publishes
  // them here; persistence to a slots collection is a follow-on.
  final List<TimeOfDay> _slots = [
    const TimeOfDay(hour: 9, minute: 0),
    const TimeOfDay(hour: 11, minute: 30),
    const TimeOfDay(hour: 16, minute: 0),
  ];

  int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  Future<void> _addSlot() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
      helpText: 'Add a bookable consult slot',
    );
    if (picked == null) return;
    if (_slots.any((s) => _minutes(s) == _minutes(picked))) return;
    setState(() {
      _slots
        ..add(picked)
        ..sort((a, b) => _minutes(a).compareTo(_minutes(b)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final availability = ref.watch(doctorAvailabilityProvider);
    final online = availability.valueOrNull ?? true;
    final busy = availability.isLoading;
    final c = context.appColors;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        _PanelHeader(
          icon: Icons.calendar_month_rounded,
          title: 'Schedule & Slots',
          subtitle:
              'Manage your duty status and publish bookable consult windows.',
        ),
        const SizedBox(height: 16),
        // Duty toggle.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.cardBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: online ? c.positiveBg : c.surfaceHi,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(online ? Icons.bolt : Icons.bolt_outlined,
                    color: online ? c.positive : c.muted, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(online ? 'On duty' : 'Off duty',
                        style: MtTextStyles.labelLg.copyWith(
                            color: c.title, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      online
                          ? 'Discoverable for new dispatches & consults'
                          : 'Hidden from the matching system',
                      style: MtTextStyles.bodySm.copyWith(color: c.muted),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: online,
                activeThumbColor: c.positive,
                onChanged: busy
                    ? null
                    : (_) =>
                        ref.read(doctorAvailabilityProvider.notifier).toggle(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Text('BOOKABLE TELE-CONSULT SLOTS',
                style: MtTextStyles.sectionLabel
                    .copyWith(color: c.muted, letterSpacing: 1.0)),
            const Spacer(),
            TextButton.icon(
              onPressed: _addSlot,
              icon: const Icon(Icons.add, size: 16),
              label: Text('Add slot', style: MtTextStyles.labelMd),
              style: TextButton.styleFrom(foregroundColor: c.accent),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.cardBorder),
          ),
          child: _slots.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No slots published yet — tap “Add slot” to open a '
                    'consult window.',
                    style: MtTextStyles.bodySm.copyWith(color: c.muted),
                  ),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final slot in _slots)
                      _SlotChip(
                        label: slot.format(context),
                        onRemove: () => setState(() => _slots.remove(slot)),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _SlotChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _SlotChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
      decoration: BoxDecoration(
        color: c.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule, size: 14, color: c.accent),
          const SizedBox(width: 6),
          Text(label,
              style: MtTextStyles.labelMd.copyWith(
                  color: c.accent, fontWeight: FontWeight.w700)),
          const SizedBox(width: 2),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close, size: 14, color: c.accent),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Shared panel chrome
// ───────────────────────────────────────────────────────────────────────────

class _PanelHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _PanelHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: c.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: c.accent, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style:
                      MtTextStyles.h2.copyWith(color: c.title, fontSize: 20)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: MtTextStyles.bodySm.copyWith(color: c.muted)),
            ],
          ),
        ),
      ],
    );
  }
}

class _PanelMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _PanelMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: c.muted),
          const SizedBox(height: 10),
          Text(title,
              textAlign: TextAlign.center,
              style: MtTextStyles.h3.copyWith(color: c.title)),
          const SizedBox(height: 4),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: MtTextStyles.bodySm.copyWith(color: c.muted)),
        ],
      ),
    );
  }
}
