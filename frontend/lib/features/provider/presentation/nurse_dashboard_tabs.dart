import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/care_request_status.dart';
import '../../../core/models/doctor_dashboard.dart';
import '../../../core/models/patient_history_item.dart';
import '../../../core/theme/app_colors_ext.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/shimmer_loading_placeholder.dart';
import '../providers/nurse_workflow_provider.dart';
import 'active_nurse_console_screen.dart';

final _moneyFmt = NumberFormat('#,###', 'en_US');
String _money(num n) => '৳${_moneyFmt.format(n.round())}';

// ═══════════════════════════════════════════════════════════════════════════
// TAB 1 · Dispatches — active callouts + the procedural transit pipeline
// ═══════════════════════════════════════════════════════════════════════════

class DispatchesTab extends ConsumerWidget {
  const DispatchesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(nurseDashboardProvider);
    return RefreshIndicator(
      color: MtColors.brand,
      onRefresh: () async => ref.invalidate(nurseDashboardProvider),
      child: async.when(
        // Skeleton dispatch cards hold the job-log layout steady while the
        // board fetches, replacing the centred spinner.
        loading: () => const ShimmerCareCardList(),
        error: (e, _) => _TabError(
          message: e.toString(),
          onRetry: () => ref.invalidate(nurseDashboardProvider),
        ),
        data: (dashboard) {
          // Incoming = freshly assigned (needs Accept/Decline).
          // Active = already accepted and in transit / on-site.
          final incoming = dashboard.upcomingToday
              .where((a) => a.awaitingAcceptance)
              .toList();
          final active =
              dashboard.upcomingToday.where((a) => a.isActive).toList();
          final hasPending = dashboard.pendingAssignment != null;
          // "Busy" the moment any accepted visit is on-site / in service.
          final onJob = active
              .any((a) => a.status == CareRequestStatus.inService);

          if (!hasPending && incoming.isEmpty && active.isEmpty) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                const _CashLedgerCard(),
                const SizedBox(height: 16),
                const _NoDispatchesState(),
              ],
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _CashLedgerCard(onJob: onJob),
              const SizedBox(height: 16),
              if (dashboard.pendingAssignment case final pending?) ...[
                _OfferCard(assignment: pending),
                const SizedBox(height: 16),
              ],
              if (incoming.isNotEmpty) ...[
                Text('INCOMING DISPATCH',
                    style: MtTextStyles.sectionLabel
                        .copyWith(color: MtColors.brand, letterSpacing: 1.0)),
                const SizedBox(height: 10),
                for (final appt in incoming) ...[
                  _IncomingDispatchCard(appt: appt),
                  const SizedBox(height: 12),
                ],
              ],
              if (active.isNotEmpty) ...[
                if (incoming.isNotEmpty) const SizedBox(height: 8),
                Text('ACTIVE DISPATCHES',
                    style: MtTextStyles.sectionLabel
                        .copyWith(color: MtColors.ink3, letterSpacing: 1.0)),
                const SizedBox(height: 10),
                for (final appt in active) ...[
                  _DispatchCard(appt: appt),
                  const SizedBox(height: 12),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _OfferCard extends ConsumerStatefulWidget {
  final PendingAssignment assignment;
  const _OfferCard({required this.assignment});

  @override
  ConsumerState<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends ConsumerState<_OfferCard> {
  Timer? _ticker;
  Duration _remaining = Duration.zero;
  bool _acceptBusy = false;
  bool _declineBusy = false;

  @override
  void initState() {
    super.initState();
    _remaining = widget.assignment.remainingFrom(DateTime.now());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final r = widget.assignment.remainingFrom(DateTime.now());
      setState(() => _remaining = r);
      if (r == Duration.zero) {
        _ticker?.cancel();
        ref.invalidate(nurseDashboardProvider);
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _countdown {
    final m = _remaining.inMinutes;
    final s = _remaining.inSeconds.remainder(60);
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? MtColors.rejected : MtColors.brand700,
    ));
  }

  Future<void> _accept() async {
    if (_acceptBusy || _declineBusy) return;
    HapticFeedback.lightImpact();
    setState(() => _acceptBusy = true);
    try {
      // Role-neutral accept (PATCH /api/appointments/:id/accept) — never the
      // doctor-only /doctor/assignments route, which clears the wrong side
      // for a nurse. Matches _IncomingDispatchCard below.
      await ref.read(nurseWorkflowProvider).acceptDispatch(widget.assignment.id);
      _toast('Dispatch accepted');
    } catch (e) {
      HapticFeedback.vibrate();
      _toast('Could not accept: $e', error: true);
    } finally {
      // Re-sync the board on BOTH outcomes. On success the card moves to
      // "active"; on a 409 conflict (someone else won the atomic claim)
      // this clears the now-unavailable card instead of leaving a stale
      // tap target behind.
      ref.invalidate(nurseDashboardProvider);
      if (mounted) setState(() => _acceptBusy = false);
    }
  }

  Future<void> _decline() async {
    if (_acceptBusy || _declineBusy) return;
    HapticFeedback.lightImpact();
    setState(() => _declineBusy = true);
    try {
      // Role-neutral reject (PATCH /api/appointments/:id/reject) — clears
      // only the nurse's side of the assignment.
      await ref.read(nurseWorkflowProvider).rejectDispatch(widget.assignment.id);
      ref.invalidate(nurseDashboardProvider);
      _toast('Dispatch declined');
    } catch (e) {
      HapticFeedback.vibrate();
      _toast('Could not decline: $e', error: true);
    } finally {
      if (mounted) setState(() => _declineBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.assignment;
    final canTap = !_acceptBusy && !_declineBusy;
    return Container(
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MtColors.brand, width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: MtColors.brand,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12.5),
                topRight: Radius.circular(12.5),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.local_hospital, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('NEW DISPATCH',
                    style: MtTextStyles.labelMd
                        .copyWith(color: Colors.white, letterSpacing: 0.8)),
                const Spacer(),
                Text('Expires in $_countdown',
                    style: MtTextStyles.labelMd.copyWith(color: Colors.white)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(a.serviceNameEn,
                          style:
                              MtTextStyles.h3.copyWith(color: MtColors.ink)),
                    ),
                    Text(_money(a.fee),
                        style: MtTextStyles.h2.copyWith(color: MtColors.brand)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  a.patientAgeSex.isEmpty
                      ? a.patientName
                      : '${a.patientName}, ${a.patientAgeSex}',
                  style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
                ),
                if (a.address.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _LocationRow(address: a.address),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: canTap ? _decline : null,
                          icon: _declineBusy
                              ? const _MiniSpinner()
                              : const Icon(Icons.close, size: 18),
                          label:
                              Text('Decline', style: MtTextStyles.labelLg),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: MtColors.ink,
                            side: const BorderSide(color: MtColors.line),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: canTap ? _accept : null,
                          icon: _acceptBusy
                              ? const _MiniSpinner(light: true)
                              : const Icon(Icons.check, size: 18),
                          label: Text('Accept dispatch',
                              style: MtTextStyles.labelLg
                                  .copyWith(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: MtColors.brand,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Active dispatch tracker — the Phase 2 procedural transit pipeline.
class _DispatchCard extends ConsumerStatefulWidget {
  final UpcomingAppointment appt;
  const _DispatchCard({required this.appt});

  @override
  ConsumerState<_DispatchCard> createState() => _DispatchCardState();
}

class _DispatchCardState extends ConsumerState<_DispatchCard> {
  bool _busy = false;

  UpcomingAppointment get _appt => widget.appt;

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? MtColors.rejected : MtColors.brand700,
    ));
  }

  /// Open the patient's address in the device maps app.
  Future<void> _openRoute() async {
    final address = _appt.address;
    if (address == null || address.trim().isEmpty) {
      _toast('No address on file for this visit yet', error: true);
      return;
    }
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _toast('Could not open maps', error: true);
    }
  }

  /// Place a phone call to the patient.
  Future<void> _callPatient() async {
    final phone = _appt.patientPhone;
    if (phone == null || phone.trim().isEmpty) {
      _toast('Patient phone is not available yet', error: true);
      return;
    }
    if (!await launchUrl(Uri(scheme: 'tel', path: phone))) {
      _toast('No phone app available to place the call', error: true);
    }
  }

  Future<void> _runStage(_Stage stage) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final workflow = ref.read(nurseWorkflowProvider);
      switch (stage.kind) {
        case _StageKind.confirmArrival:
          await workflow.advance(_appt.id, NurseTransit.arrived);
          _toast('Arrival confirmed.');
        case _StageKind.openTerminal:
          if (_appt.status != CareRequestStatus.inService) {
            await workflow.advance(_appt.id, NurseTransit.inService);
          }
          if (!mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ActiveNurseConsoleScreen(appointment: _appt),
            ),
          );
      }
    } catch (e) {
      _toast('Could not update status: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stage = _Stage.forStatus(_appt.status);
    final distance = _appt.distanceKm != null
        ? '${(_appt.distanceKm ?? 0).toStringAsFixed(1)} km away'
        : '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialsAvatar(
                name: _appt.patientName,
                size: 48,
                backgroundColor: context.appColors.infoBg,
                textColor: context.appColors.info,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_appt.patientName,
                        style: MtTextStyles.labelLg.copyWith(
                            color: MtColors.ink,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(_appt.serviceName,
                        style: MtTextStyles.bodySm
                            .copyWith(color: MtColors.ink2)),
                  ],
                ),
              ),
              _StatusChip(status: _appt.status),
            ],
          ),
          if (_appt.address != null && _appt.address!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _LocationRow(address: _appt.address!),
          ],
          if (distance.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.near_me_outlined,
                    size: 14, color: MtColors.ink3),
                const SizedBox(width: 6),
                Text(distance,
                    style:
                        MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _CardActionButton(
                  icon: Icons.directions_outlined,
                  label: 'Route',
                  onTap: _openRoute,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CardActionButton(
                  icon: Icons.phone_outlined,
                  label: 'Call',
                  onTap: _callPatient,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : () => _runStage(stage),
              icon: _busy
                  ? const _MiniSpinner(light: true)
                  : Icon(stage.icon, size: 20),
              label: Text(stage.label,
                  style: MtTextStyles.labelLg.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w800)),
              style: ElevatedButton.styleFrom(
                backgroundColor: stage.kind == _StageKind.openTerminal
                    ? MtColors.completed
                    : MtColors.brand,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _StageKind { confirmArrival, openTerminal }

class _Stage {
  final _StageKind kind;
  final String label;
  final IconData icon;
  const _Stage(this.kind, this.label, this.icon);

  static _Stage forStatus(String status) {
    switch (status) {
      case CareRequestStatus.arrived:
      case CareRequestStatus.inService:
        return const _Stage(_StageKind.openTerminal,
            '🩺  OPEN NURSING PROCEDURAL TERMINAL',
            Icons.medical_services_outlined);
      // enroute / on-the-way (and any active fallback) → confirm arrival.
      default:
        return const _Stage(_StageKind.confirmArrival,
            '📍  CONFIRM ARRIVAL AT RESIDENCE', Icons.location_on);
    }
  }
}

/// Phase 1 — the interactive incoming callout. Shown for a freshly
/// `assigned` dispatch: patient, procedure, address, guaranteed payout,
/// and the Accept / Decline action engine.
class _IncomingDispatchCard extends ConsumerStatefulWidget {
  final UpcomingAppointment appt;
  const _IncomingDispatchCard({required this.appt});

  @override
  ConsumerState<_IncomingDispatchCard> createState() =>
      _IncomingDispatchCardState();
}

class _IncomingDispatchCardState
    extends ConsumerState<_IncomingDispatchCard> {
  bool _accepting = false;
  bool _declining = false;

  UpcomingAppointment get _appt => widget.appt;

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? MtColors.rejected : MtColors.brand700,
    ));
  }

  Future<void> _accept() async {
    if (_accepting || _declining) return;
    setState(() => _accepting = true);
    try {
      await ref.read(nurseWorkflowProvider).acceptDispatch(_appt.id);
      _toast('Dispatch accepted — you are on the way.');
    } catch (e) {
      _toast('Could not accept: $e', error: true);
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  Future<void> _decline() async {
    if (_accepting || _declining) return;
    setState(() => _declining = true);
    try {
      await ref.read(nurseWorkflowProvider).rejectDispatch(_appt.id);
      _toast('Dispatch declined.');
    } catch (e) {
      _toast('Could not decline: $e', error: true);
    } finally {
      if (mounted) setState(() => _declining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canTap = !_accepting && !_declining;
    return Container(
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.brand, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: MtColors.brand.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header strip.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: MtColors.brand,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14.5),
                topRight: Radius.circular(14.5),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.notifications_active,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('NEW VISIT ASSIGNED',
                    style: MtTextStyles.labelMd
                        .copyWith(color: Colors.white, letterSpacing: 0.8)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(_money(_appt.fee),
                      style: MtTextStyles.labelMd
                          .copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    InitialsAvatar(
                      name: _appt.patientName,
                      size: 48,
                      backgroundColor: context.appColors.infoBg,
                      textColor: context.appColors.info,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_appt.patientName,
                              style: MtTextStyles.h3
                                  .copyWith(color: MtColors.ink)),
                          const SizedBox(height: 2),
                          Text(_appt.serviceName,
                              style: MtTextStyles.bodySm
                                  .copyWith(color: MtColors.ink2)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_appt.address != null && _appt.address!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _LocationRow(address: _appt.address!),
                ],
                const SizedBox(height: 8),
                _PayoutRow(fee: _appt.fee),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: canTap ? _decline : null,
                          icon: _declining
                              ? const _MiniSpinner()
                              : const Icon(Icons.close, size: 18),
                          label: Text('Decline',
                              style: MtTextStyles.labelLg
                                  .copyWith(color: MtColors.rejected)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: MtColors.rejected,
                            side: const BorderSide(color: MtColors.line),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: canTap ? _accept : null,
                          icon: _accepting
                              ? const _MiniSpinner(light: true)
                              : const Icon(Icons.rocket_launch, size: 18),
                          label: Text('Accept Dispatch',
                              style: MtTextStyles.labelLg.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: MtColors.brand,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PayoutRow extends StatelessWidget {
  final num fee;
  const _PayoutRow({required this.fee});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: MtColors.brandSofter,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.payments_outlined, color: MtColors.brand, size: 18),
          const SizedBox(width: 8),
          Text('Guaranteed payout',
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2)),
          const Spacer(),
          Text(_money(fee),
              style: MtTextStyles.labelLg.copyWith(
                  color: MtColors.brand700, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 2 · Task History — past sessions bucketed by service tier
// ═══════════════════════════════════════════════════════════════════════════

class TaskHistoryTab extends ConsumerWidget {
  const TaskHistoryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(nurseHistoryProvider);
    return RefreshIndicator(
      color: MtColors.brand,
      onRefresh: () async => ref.invalidate(nurseHistoryProvider),
      child: async.when(
        loading: () => const _CenteredLoader(),
        error: (e, _) => _TabError(
          message: e.toString(),
          onRetry: () => ref.invalidate(nurseHistoryProvider),
        ),
        data: (items) {
          if (items.isEmpty) return const _EmptyHistoryState();
          // Bucket by service tier (care_type), preserving recency order.
          final tiers = <String, List<PatientHistoryItem>>{};
          for (final it in items) {
            final key = it.serviceName.isEmpty ? 'Other' : it.serviceName;
            (tiers[key] ??= []).add(it);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              for (final entry in tiers.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, top: 4),
                  child: Row(
                    children: [
                      Text(entry.key.toUpperCase(),
                          style: MtTextStyles.sectionLabel.copyWith(
                              color: MtColors.ink3, letterSpacing: 1.0)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: MtColors.brandSoft,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('${entry.value.length}',
                            style: MtTextStyles.labelSm
                                .copyWith(color: MtColors.brand700)),
                      ),
                    ],
                  ),
                ),
                for (final it in entry.value) _HistoryRow(item: it),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final PatientHistoryItem item;
  const _HistoryRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('MMM d, yyyy').format(item.updatedAt.toLocal());
    final c = context.appColors;
    final (statusFg, statusBg) = switch (item.status) {
      'completed' => (c.positive, c.positiveBg),
      'cancelled' => (c.muted, c.surfaceHi),
      'rejected' => (c.danger, c.dangerBg),
      _ => (c.muted, c.surfaceHi),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(date,
                        style: MtTextStyles.labelMd.copyWith(
                            color: MtColors.ink, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(item.status.toUpperCase(),
                          style: MtTextStyles.labelSm
                              .copyWith(color: statusFg, fontSize: 9)),
                    ),
                  ],
                ),
                if (item.locationText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(item.locationText,
                      style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          Text(_money(item.effectivePrice),
              style: MtTextStyles.labelLg.copyWith(color: MtColors.brand)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Shared small widgets
// ═══════════════════════════════════════════════════════════════════════════

/// Workspace header ledger: the company cash the nurse is physically holding
/// from door-step CASH collections (`Wallet.cashInHand`, surfaced on
/// `GET /api/provider/earnings`). The full picture — withdrawable balance,
/// commission splits, payouts — lives on the Wallet tab
/// ([ProviderWalletPage]); this card is just the at-a-glance figure. Also
/// carries the derived "Busy — on a job" duty pill when a visit is in service.
class _CashLedgerCard extends ConsumerWidget {
  final bool onJob;
  const _CashLedgerCard({this.onJob = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    // Live reset: when an admin receives this provider's cash and zeroes the
    // ledger, `cash_ledger_cleared` fires — re-pull earnings so the card
    // drops to ৳0 without waiting for a manual refresh.
    ref.listen(cashLedgerClearedSignalProvider, (_, _) {
      ref.invalidate(nurseEarningsProvider);
    });
    final async = ref.watch(nurseEarningsProvider);
    final cash = async.valueOrNull?.cashInHand ?? 0;
    final money = NumberFormat.decimalPattern('en').format(cash);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.brand, c.brand.withValues(alpha: 0.78)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.account_balance_wallet_outlined,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CASH IN HAND',
                    style: MtTextStyles.sectionLabel.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        letterSpacing: 1.0)),
                const SizedBox(height: 2),
                Text('৳ $money',
                    style: MtTextStyles.h2.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('Company cash you are holding to remit',
                    style: MtTextStyles.bodySm
                        .copyWith(color: Colors.white.withValues(alpha: 0.8))),
              ],
            ),
          ),
          _DutyPill(onJob: onJob),
        ],
      ),
    );
  }
}

class _DutyPill extends StatelessWidget {
  final bool onJob;
  const _DutyPill({required this.onJob});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: onJob ? const Color(0xFFFFC24B) : const Color(0xFF7BE495),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(onJob ? 'On a job' : 'On duty',
              style: MtTextStyles.labelSm.copyWith(
                  color: Colors.white, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Compact secondary action (Route / Call) on the active dispatch card.
class _CardActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _CardActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label,
            style: MtTextStyles.labelMd.copyWith(color: MtColors.ink)),
        style: OutlinedButton.styleFrom(
          foregroundColor: MtColors.ink,
          side: const BorderSide(color: MtColors.line),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  final String address;
  const _LocationRow({required this.address});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: MtColors.bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_on, color: MtColors.brand, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(address,
                style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink)),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final (label, fg, bg) = switch (status) {
      CareRequestStatus.assigned =>
        ('ASSIGNED', c.accent, c.accent.withValues(alpha: 0.15)),
      CareRequestStatus.enroute ||
      CareRequestStatus.onTheWay => ('ON THE WAY', c.info, c.infoBg),
      CareRequestStatus.arrived =>
        ('ARRIVED', c.accent, c.accent.withValues(alpha: 0.15)),
      CareRequestStatus.inService => ('IN SERVICE', c.brand, c.glow),
      _ => (status.toUpperCase(), c.muted, c.surfaceHi),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          style: MtTextStyles.labelSm.copyWith(color: fg, fontSize: 10)),
    );
  }
}

class _MiniSpinner extends StatelessWidget {
  final bool light;
  const _MiniSpinner({this.light = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: light
            ? const AlwaysStoppedAnimation<Color>(Colors.white)
            : const AlwaysStoppedAnimation<Color>(MtColors.brand),
      ),
    );
  }
}

class _CenteredLoader extends StatelessWidget {
  const _CenteredLoader();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        SizedBox(height: 120),
        Center(child: CircularProgressIndicator(color: MtColors.brand)),
      ],
    );
  }
}

class _TabError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _TabError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 24),
      children: [
        const Icon(Icons.error_outline, color: MtColors.rejected, size: 40),
        const SizedBox(height: 12),
        Text('Something went wrong',
            textAlign: TextAlign.center,
            style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
        const SizedBox(height: 6),
        Text(message,
            textAlign: TextAlign.center,
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: MtColors.brand,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoDispatchesState extends StatelessWidget {
  const _NoDispatchesState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle_outline,
              color: MtColors.completed, size: 40),
          const SizedBox(height: 10),
          Text('No active dispatches',
              style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
          const SizedBox(height: 4),
          Text('Stay on duty — new dispatches will appear here.',
              textAlign: TextAlign.center,
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
        ],
      ),
    );
  }
}

class _EmptyHistoryState extends StatelessWidget {
  const _EmptyHistoryState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 24),
      children: [
        const Icon(Icons.history, color: MtColors.ink3, size: 40),
        const SizedBox(height: 12),
        Text('No past sessions yet',
            textAlign: TextAlign.center,
            style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
        const SizedBox(height: 6),
        Text('Completed nursing sessions will be logged here.',
            textAlign: TextAlign.center,
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
      ],
    );
  }
}
