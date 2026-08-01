import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../doctor_providers.dart';

/// The specialised modules of the Doctor Operations workspace. Kept as an
/// enum (with its icon + label metadata) so the shell's rail and bottom bar
/// render from a single source of truth and can never drift out of sync.
///
/// `earnings` is the performance/analytics rollup (visits, rating, revenue
/// trend); `wallet` is the money itself — withdrawable balance, commission
/// splits and payouts. They are deliberately separate: one answers "how am I
/// doing", the other "what am I owed".
enum DoctorTab { appointments, ehrVault, prescriber, schedule, earnings, wallet }

extension DoctorTabX on DoctorTab {
  /// Short label shown under each destination.
  String get label {
    switch (this) {
      case DoctorTab.appointments:
        return 'Appointments';
      case DoctorTab.ehrVault:
        return 'EHR Vault';
      case DoctorTab.prescriber:
        return 'Prescriber';
      case DoctorTab.schedule:
        return 'Schedule';
      case DoctorTab.earnings:
        return 'Earnings';
      case DoctorTab.wallet:
        return 'Wallet';
    }
  }

  /// Outline icon for the unselected state.
  IconData get icon {
    switch (this) {
      case DoctorTab.appointments:
        return Icons.assignment_outlined;
      case DoctorTab.ehrVault:
        return Icons.assignment_ind_outlined;
      case DoctorTab.prescriber:
        return Icons.healing_outlined;
      case DoctorTab.schedule:
        return Icons.calendar_month_outlined;
      case DoctorTab.earnings:
        return Icons.analytics_outlined;
      case DoctorTab.wallet:
        return Icons.account_balance_wallet_outlined;
    }
  }

  /// Filled icon for the selected state.
  IconData get selectedIcon {
    switch (this) {
      case DoctorTab.appointments:
        return Icons.assignment_rounded;
      case DoctorTab.ehrVault:
        return Icons.assignment_ind_rounded;
      case DoctorTab.prescriber:
        return Icons.healing_rounded;
      case DoctorTab.schedule:
        return Icons.calendar_month_rounded;
      case DoctorTab.earnings:
        return Icons.analytics_rounded;
      case DoctorTab.wallet:
        return Icons.account_balance_wallet_rounded;
    }
  }
}

/// Active workspace tab. A tiny [Notifier<int>] so deep-link helpers (a
/// notification tap, the active-call banner's CTA) can address any module
/// atomically, and the shell's rail + bottom bar stay in lockstep.
class DoctorNavController extends Notifier<int> {
  @override
  int build() => 0;

  /// Single mutation entry point. Clamps to the valid range and short-
  /// circuits a no-op tap so widgets can call this freely.
  void select(int index) {
    if (index < 0 || index >= DoctorTab.values.length) return;
    if (index != state) state = index;
  }
}

final doctorNavProvider =
    NotifierProvider<DoctorNavController, int>(DoctorNavController.new);

/// The Appointments panel splits into two pipelines: physical home
/// dispatches and virtual tele-consults.
enum AppointmentSegment { homeVisits, teleConsults }

final appointmentSegmentProvider =
    StateProvider<AppointmentSegment>((_) => AppointmentSegment.homeVisits);

/// Live count of assigned-but-not-yet-accepted visits — drives the badge
/// overlay on the Appointments destination. Derived from the doctor
/// dashboard feed so it stays current with the 10 s heartbeat.
final pendingTriageCountProvider = Provider<int>((ref) {
  final dash = ref.watch(doctorDashboardProvider).valueOrNull;
  if (dash == null) return 0;
  return dash.upcomingToday.where((a) => a.awaitingAcceptance).length;
});

/// A live-engagement alert surfaced by the pulsing banner at the base of
/// the shell. Carries everything the banner needs to render + route.
class DoctorLiveAlert {
  final String title;
  final String subtitle;
  final IconData icon;

  /// `true` for triage/dispatch events (coral, stronger pulse); `false`
  /// for an in-progress visit (teal, calmer pulse).
  final bool urgent;

  /// Destination tab to open when the banner is tapped.
  final DoctorTab target;

  const DoctorLiveAlert({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.target,
    this.urgent = false,
  });
}

/// Derives the current live alert (or null) from the dashboard state.
/// Priority: a brand-new pending offer → an in-progress visit → a backlog
/// of unaccepted triage. Null collapses the banner entirely.
final doctorLiveAlertProvider = Provider<DoctorLiveAlert?>((ref) {
  final dash = ref.watch(doctorDashboardProvider).valueOrNull;
  if (dash == null) return null;

  if (dash.pendingAssignment != null) {
    return const DoctorLiveAlert(
      title: 'New home triage assigned',
      subtitle: 'Tap to review and accept the dispatch',
      icon: Icons.crisis_alert_rounded,
      target: DoctorTab.appointments,
      urgent: true,
    );
  }

  final active =
      dash.upcomingToday.where((a) => a.isActive).toList(growable: false);
  if (active.isNotEmpty) {
    final a = active.first;
    return DoctorLiveAlert(
      title: 'Visit in progress',
      subtitle: '${a.patientName} · ${a.serviceName}',
      icon: Icons.videocam_rounded,
      target: DoctorTab.appointments,
    );
  }

  final awaiting = dash.upcomingToday
      .where((a) => a.awaitingAcceptance)
      .toList(growable: false);
  if (awaiting.isNotEmpty) {
    return DoctorLiveAlert(
      title: 'High-priority triage waiting',
      subtitle: awaiting.length == 1
          ? '1 request needs your review'
          : '${awaiting.length} requests need your review',
      icon: Icons.notifications_active_rounded,
      target: DoctorTab.appointments,
      urgent: true,
    );
  }

  return null;
});
