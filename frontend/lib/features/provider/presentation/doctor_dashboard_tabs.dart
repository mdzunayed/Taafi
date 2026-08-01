import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/care_request_status.dart';
import '../../../core/widgets/mt_search_field.dart';
import '../../../core/models/doctor_dashboard.dart';
import '../../../core/models/doctor_patient.dart';
import '../../../core/models/doctor_stats.dart';
import '../../../core/models/patient_history_item.dart';
import '../../../core/models/prescription.dart';
import '../../../core/theme/app_colors_ext.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/shimmer_loading_placeholder.dart';
import '../../doctor/doctor_providers.dart';
import '../../prescriptions/prescription_pad_actions.dart';
import '../providers/doctor_workflow_provider.dart';
import 'active_care_console_screen.dart';

final _moneyFmt = NumberFormat('#,###', 'en_US');
String _money(num n) => '৳${_moneyFmt.format(n.round())}';

// ═══════════════════════════════════════════════════════════════════════════
// TAB 1 · Assignments — active deployments + the transit progression pipeline
// ═══════════════════════════════════════════════════════════════════════════

class AssignmentsTab extends ConsumerWidget {
  const AssignmentsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(doctorDashboardProvider);
    return RefreshIndicator(
      color: MtColors.brand,
      onRefresh: () => ref.read(doctorDashboardProvider.notifier).refresh(),
      child: async.when(
        // Skeleton deployment cards keep the triage column structurally rigid
        // while the dashboard fetches — no spinner flash, no layout jump.
        loading: () => const ShimmerCareCardList(),
        error: (e, _) => _TabError(
          message: e.toString(),
          onRetry: () => ref.read(doctorDashboardProvider.notifier).refresh(),
        ),
        data: (dashboard) {
          // Every visit currently in the doctor's hands — assigned through
          // in-service. Each renders as a deployment card with the staged
          // progression button.
          final active = dashboard.upcomingToday
              .where((a) => a.awaitingAcceptance || a.isActive)
              .toList();
          final hasPending = dashboard.pendingAssignment != null;

          if (!hasPending && active.isEmpty) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: const [_NoDeploymentsState()],
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              if (dashboard.pendingAssignment case final pending?) ...[
                _OfferCard(assignment: pending),
                const SizedBox(height: 16),
              ],
              if (active.isNotEmpty) ...[
                Text(
                  'ACTIVE DEPLOYMENTS',
                  style: MtTextStyles.sectionLabel
                      .copyWith(color: MtColors.ink3, letterSpacing: 1.0),
                ),
                const SizedBox(height: 10),
                for (final appt in active) ...[
                  _DeploymentCard(appt: appt),
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

/// Pending offer (admin just allocated this doctor) — accept / decline
/// with a live expiry countdown. Ported from the legacy dashboard.
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
        ref.invalidate(doctorDashboardProvider);
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
      await ref.read(acceptAssignmentProvider(widget.assignment.id).future);
      _toast('Assignment accepted');
    } catch (e) {
      HapticFeedback.vibrate();
      _toast('Could not accept: $e', error: true);
    } finally {
      if (mounted) setState(() => _acceptBusy = false);
    }
  }

  Future<void> _decline() async {
    if (_acceptBusy || _declineBusy) return;
    HapticFeedback.lightImpact();
    setState(() => _declineBusy = true);
    try {
      await ref.read(declineAssignmentProvider(widget.assignment.id).future);
      _toast('Assignment declined');
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
                const Icon(Icons.notifications_active,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  'NEW ASSIGNMENT',
                  style: MtTextStyles.labelMd
                      .copyWith(color: Colors.white, letterSpacing: 0.8),
                ),
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
                          label: Text('Accept job',
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

/// Active deployment card — the Phase 2 transit pipeline. The primary
/// button's label + action are derived from the live visit status.
class _DeploymentCard extends ConsumerStatefulWidget {
  final UpcomingAppointment appt;
  const _DeploymentCard({required this.appt});

  @override
  ConsumerState<_DeploymentCard> createState() => _DeploymentCardState();
}

class _DeploymentCardState extends ConsumerState<_DeploymentCard> {
  bool _busy = false;

  UpcomingAppointment get _appt => widget.appt;

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? MtColors.rejected : MtColors.brand700,
    ));
  }

  Future<void> _runStage(_Stage stage) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final workflow = ref.read(doctorWorkflowProvider);
      switch (stage.kind) {
        case _StageKind.startTransit:
          await workflow.advance(_appt.id, CareRequestStatus.onTheWay);
          _toast('En route — patient notified.');
        case _StageKind.markArrived:
          await workflow.advance(_appt.id, CareRequestStatus.arrived);
          _toast('Marked as arrived.');
        case _StageKind.openConsole:
          // Move the visit into service (if not already) so the patient
          // sees "in service", then open the full-screen console.
          if (_appt.status != CareRequestStatus.inService) {
            await workflow.advance(_appt.id, CareRequestStatus.inService);
          }
          if (!mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ActiveCareConsoleScreen(appointment: _appt),
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
                backgroundColor: context.appColors.warningBg,
                textColor: context.appColors.warning,
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
                const Icon(Icons.directions_car_outlined,
                    size: 14, color: MtColors.ink3),
                const SizedBox(width: 6),
                Text(distance,
                    style:
                        MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : () => _runStage(stage),
              icon: _busy
                  ? const _MiniSpinner(light: true)
                  : Icon(stage.icon, size: 20),
              label: Text(
                stage.label,
                style: MtTextStyles.labelLg.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    stage.kind == _StageKind.openConsole
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

enum _StageKind { startTransit, markArrived, openConsole }

class _Stage {
  final _StageKind kind;
  final String label;
  final IconData icon;
  const _Stage(this.kind, this.label, this.icon);

  static _Stage forStatus(String status) {
    switch (status) {
      case CareRequestStatus.enroute:
      case CareRequestStatus.onTheWay:
        return const _Stage(
            _StageKind.markArrived, '📍  MARK AS ARRIVED', Icons.location_on);
      case CareRequestStatus.arrived:
      case CareRequestStatus.inService:
        return const _Stage(_StageKind.openConsole,
            '🩺  OPEN CLINICAL SESSION CONSOLE', Icons.medical_services_outlined);
      case CareRequestStatus.assigned:
      default:
        return const _Stage(_StageKind.startTransit,
            '🚀  START TRANSIT - ON THE WAY', Icons.navigation_outlined);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 2 · Patient Records — searchable portal of treated patients
// ═══════════════════════════════════════════════════════════════════════════

class PatientRecordsTab extends ConsumerStatefulWidget {
  const PatientRecordsTab({super.key});

  @override
  ConsumerState<PatientRecordsTab> createState() => _PatientRecordsTabState();
}

class _PatientRecordsTabState extends ConsumerState<PatientRecordsTab> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(doctorPatientsSearchProvider.notifier).state = v.trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(doctorPatientsProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: MtSearchField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            hintText: 'Search patients by name',
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const _CenteredLoader(),
            error: (e, _) => _TabError(
              message: e.toString(),
              onRetry: () => ref.invalidate(doctorPatientsProvider),
            ),
            data: (patients) {
              if (patients.isEmpty) {
                return const _EmptyRecordsState();
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: patients.length,
                itemBuilder: (_, i) => _PatientRecordTile(patient: patients[i]),
                separatorBuilder: (_, _) => const SizedBox(height: 10),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PatientRecordTile extends StatelessWidget {
  final DoctorPatient patient;
  const _PatientRecordTile({required this.patient});

  @override
  Widget build(BuildContext context) {
    final last = patient.lastVisitAt;
    final lastLabel =
        last == null ? '' : DateFormat('MMM d, yyyy').format(last.toLocal());
    return Material(
      color: MtColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: MtColors.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => _PatientRecordSheet(patient: patient),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: MtColors.line),
          ),
          child: Row(
            children: [
              InitialsAvatar(
                name: patient.name,
                size: 44,
                backgroundColor: MtColors.brandSoft,
                textColor: MtColors.brand,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(patient.name,
                        style: MtTextStyles.labelLg.copyWith(
                            color: MtColors.ink,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (patient.lastCareType.isNotEmpty) patient.lastCareType,
                        if (lastLabel.isNotEmpty) 'Last seen $lastLabel',
                      ].join(' · '),
                      style:
                          MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: MtColors.bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  patient.visitCount == 1
                      ? '1 visit'
                      : '${patient.visitCount} visits',
                  style: MtTextStyles.labelSm.copyWith(color: MtColors.ink2),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: MtColors.ink3, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _PatientRecordSheet extends ConsumerWidget {
  final DoctorPatient patient;
  const _PatientRecordSheet({required this.patient});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = patient.patientAccountId;
    final caseLog = ref.watch(patientCaseLogProvider(id));
    final scripts = ref.watch(patientPrescriptionsProvider(id));
    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: MtColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                InitialsAvatar(
                  name: patient.name,
                  size: 48,
                  backgroundColor: MtColors.brandSoft,
                  textColor: MtColors.brand,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(patient.name,
                          style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
                      if (patient.phone.isNotEmpty)
                        Text(patient.phone,
                            style: MtTextStyles.bodySm
                                .copyWith(color: MtColors.ink3)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('PREVIOUS CASE LOGS',
                style: MtTextStyles.sectionLabel
                    .copyWith(color: MtColors.ink3, letterSpacing: 1.0)),
            const SizedBox(height: 8),
            caseLog.when(
              loading: () => const _InlineLoader(),
              error: (e, _) => _InlineError(),
              data: (items) => items.isEmpty
                  ? _InlineEmpty('No case logs on file.')
                  : Column(
                      children: [for (final c in items) _CaseLogRow(item: c)],
                    ),
            ),
            const SizedBox(height: 20),
            Text('HISTORICAL PRESCRIPTIONS',
                style: MtTextStyles.sectionLabel
                    .copyWith(color: MtColors.ink3, letterSpacing: 1.0)),
            const SizedBox(height: 8),
            scripts.when(
              loading: () => const _InlineLoader(),
              error: (e, _) => _InlineError(),
              data: (list) => list.isEmpty
                  ? _InlineEmpty('No prescriptions on file.')
                  : Column(
                      children: [
                        for (final p in list) _ScriptRow(prescription: p),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaseLogRow extends StatelessWidget {
  final PatientHistoryItem item;
  const _CaseLogRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('MMM d, yyyy').format(item.updatedAt.toLocal());
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MtColors.bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.serviceName,
                    style: MtTextStyles.labelMd.copyWith(
                        color: MtColors.ink, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('$date · ${item.status}',
                    style:
                        MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
              ],
            ),
          ),
          Text(_money(item.effectivePrice),
              style: MtTextStyles.labelMd.copyWith(color: MtColors.brand)),
        ],
      ),
    );
  }
}

class _ScriptRow extends StatelessWidget {
  final Prescription prescription;
  const _ScriptRow({required this.prescription});

  @override
  Widget build(BuildContext context) {
    final p = prescription;
    final date = DateFormat('MMM d, yyyy').format(p.issuedAt.toLocal());
    final drugs = p.items.map((i) => i.drugName).where((s) => s.isNotEmpty);
    // Tap opens the shared prescription pad in a bottom sheet — same
    // layout the patient sees, no re-implementation.
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showPrescriptionPadSheet(context, p),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MtColors.bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.diagnosis.isEmpty ? 'Prescription' : p.diagnosis,
                    style: MtTextStyles.labelMd.copyWith(
                        color: MtColors.ink, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(date,
                    style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
                const SizedBox(width: 4),
                const Icon(Icons.open_in_full,
                    size: 14, color: MtColors.ink3),
              ],
            ),
            if (drugs.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(drugs.join(' · '),
                  style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2)),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 3 · Performance — earnings, sessions, rating analytics
// ═══════════════════════════════════════════════════════════════════════════

class PerformanceTab extends ConsumerWidget {
  const PerformanceTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(doctorStatsProvider).valueOrNull ?? DoctorStats.empty;
    return RefreshIndicator(
      color: MtColors.brand,
      onRefresh: () => ref.read(doctorStatsProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _EarningsHero(stats: stats),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: 'TODAY',
                  value: _money(stats.todayEarnings),
                  caption: stats.todayVisits == 1
                      ? '1 session'
                      : '${stats.todayVisits} sessions',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(
                  label: 'THIS WEEK',
                  value: _money(stats.weekEarnings),
                  caption: stats.weekVisits == 1
                      ? '1 session'
                      : '${stats.weekVisits} sessions',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _MetricCard(
            label: 'RATING',
            value: stats.rating.toStringAsFixed(2),
            caption: stats.reviewCount == 1
                ? 'from 1 review'
                : 'from ${stats.reviewCount} reviews',
            trailing: Icon(Icons.star_rounded,
                color: context.appColors.warning, size: 28),
          ),
        ],
      ),
    );
  }
}

class _EarningsHero extends StatelessWidget {
  final DoctorStats stats;
  const _EarningsHero({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [MtColors.brand, MtColors.brand700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('THIS WEEK\'S EARNINGS',
              style: MtTextStyles.labelSm.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                  letterSpacing: 1.0)),
          const SizedBox(height: 8),
          Text(_money(stats.weekEarnings),
              style: MtTextStyles.displayLg
                  .copyWith(color: Colors.white, fontSize: 38)),
          const SizedBox(height: 4),
          Text(
            '${stats.weekVisits} care sessions completed',
            style: MtTextStyles.bodyMd
                .copyWith(color: Colors.white.withValues(alpha: 0.9)),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String caption;
  final Widget? trailing;
  const _MetricCard({
    required this.label,
    required this.value,
    required this.caption,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MtColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: MtTextStyles.sectionLabel.copyWith(
                        color: MtColors.ink3, letterSpacing: 1.0)),
                const SizedBox(height: 6),
                Text(value,
                    style: MtTextStyles.h2
                        .copyWith(color: MtColors.ink, fontSize: 24)),
                const SizedBox(height: 2),
                Text(caption,
                    style:
                        MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Shared small widgets
// ═══════════════════════════════════════════════════════════════════════════

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
        Center(
          child: CircularProgressIndicator(color: MtColors.brand),
        ),
      ],
    );
  }
}

class _InlineLoader extends StatelessWidget {
  const _InlineLoader();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child:
                CircularProgressIndicator(strokeWidth: 2, color: MtColors.brand),
          ),
        ),
      );
}

class _InlineError extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Text(
        "Couldn't load this section.",
        style: MtTextStyles.bodySm.copyWith(color: MtColors.rejected),
      );
}

class _InlineEmpty extends StatelessWidget {
  final String message;
  const _InlineEmpty(this.message);

  @override
  Widget build(BuildContext context) => Text(
        message,
        style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
      );
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
        Text("Something went wrong",
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

class _NoDeploymentsState extends StatelessWidget {
  const _NoDeploymentsState();

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
          Text('No active deployments',
              style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
          const SizedBox(height: 4),
          Text(
            'New assignments from the admin will appear here.',
            textAlign: TextAlign.center,
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
          ),
        ],
      ),
    );
  }
}

class _EmptyRecordsState extends StatelessWidget {
  const _EmptyRecordsState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 24),
      children: [
        const Icon(Icons.folder_open_outlined, color: MtColors.ink3, size: 40),
        const SizedBox(height: 12),
        Text('No patient records yet',
            textAlign: TextAlign.center,
            style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
        const SizedBox(height: 6),
        Text(
          'Patients you complete visits for will be listed here.',
          textAlign: TextAlign.center,
          style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
        ),
      ],
    );
  }
}
