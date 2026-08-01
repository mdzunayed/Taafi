import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/prescription.dart';
import '../../../../core/network/socket_manager.dart';
import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/widgets/mt_empty_state.dart';
import '../../../../core/widgets/mt_error_state.dart';
import '../../../../core/widgets/mt_search_field.dart';
import '../../../prescriptions/prescription_release_gate.dart';
import '../../admin_providers.dart';

/// Which slice of the release pipeline the tab is looking at.
enum _QueueFilter { awaiting, approved, rejected }

extension _QueueFilterX on _QueueFilter {
  String get label {
    switch (this) {
      case _QueueFilter.awaiting:
        return 'Awaiting review';
      case _QueueFilter.approved:
        return 'Approved';
      case _QueueFilter.rejected:
        return 'Rejected';
    }
  }
}

/// Rx Approvals — the admin gate of the prescription release pipeline.
/// Lists every PAID script awaiting an explicit decision (oldest paid
/// first), with full clinical content, and Approve / Reject actions.
/// Approving unlocks the script for the patient instantly (socket
/// fan-out server-side).
class PrescriptionApprovalTab extends ConsumerStatefulWidget {
  const PrescriptionApprovalTab({super.key});

  @override
  ConsumerState<PrescriptionApprovalTab> createState() =>
      _PrescriptionApprovalTabState();
}

class _PrescriptionApprovalTabState
    extends ConsumerState<PrescriptionApprovalTab> {
  _QueueFilter _filter = _QueueFilter.awaiting;
  String _query = '';
  StreamSubscription<Map<String, dynamic>>? _paidSub;

  @override
  void initState() {
    super.initState();
    // Live refresh: `prescription:paid` fires on the admin role room the
    // moment a patient settles their balance — pull the queue instead of
    // waiting out the 15 s poll.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _paidSub =
          ref.read(socketManagerProvider)?.onPrescriptionPaid.listen((_) {
        if (!mounted) return;
        ref.invalidate(adminPrescriptionQueueProvider);
      });
    });
  }

  @override
  void dispose() {
    _paidSub?.cancel();
    super.dispose();
  }

  Future<void> _decide(Prescription p, {required bool approve}) async {
    HapticFeedback.lightImpact();
    String? reason;
    if (!approve) {
      reason = await _askRejectReason(p);
      if (reason == null) return; // dialog dismissed
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: MtColors.surface,
          title: Text('Approve prescription?',
              style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
          content: Text(
            'The script by ${p.doctorName.isEmpty ? 'the doctor' : p.doctorName} '
            'for ${p.patientName.isEmpty ? 'the patient' : p.patientName} '
            'unlocks immediately after approval.',
            style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: MtColors.completed),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Approve'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    try {
      await ref
          .read(adminPrescriptionQueueProvider.notifier)
          .decide(p.id, approve: approve, reason: reason);
      // Decided rows land in the history chips.
      ref.invalidate(adminPrescriptionHistoryProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: approve ? MtColors.completed : MtColors.ink,
          content: Text(
            approve
                ? 'Prescription approved — unlocked for the patient.'
                : 'Prescription rejected.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: MtColors.rejected,
          content: Text('Decision failed: $e'),
        ),
      );
    }
  }

  Future<String?> _askRejectReason(Prescription p) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MtColors.surface,
        title: Text('Reject prescription?',
            style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The patient keeps the locked view and is told to contact '
              'support. The reason below stays internal.',
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Reason (internal note)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MtColors.rejected),
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    controller.dispose();
    return reason;
  }

  bool _matchesQuery(Prescription p) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return p.patientName.toLowerCase().contains(q) ||
        p.doctorName.toLowerCase().contains(q) ||
        p.diagnosis.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final awaiting = _filter == _QueueFilter.awaiting;
    final async = awaiting
        ? ref.watch(adminPrescriptionQueueProvider)
        : ref.watch(adminPrescriptionHistoryProvider(_filter.name));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Rx Approvals',
                        style:
                            MtTextStyles.h2.copyWith(color: MtColors.ink)),
                    const SizedBox(height: 2),
                    Text(
                      'Paid prescriptions stay locked for the patient until '
                      'you approve them.',
                      style:
                          MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh, color: MtColors.ink2),
                onPressed: () {
                  if (awaiting) {
                    ref.read(adminPrescriptionQueueProvider.notifier).refresh();
                  } else {
                    ref.invalidate(
                        adminPrescriptionHistoryProvider(_filter.name));
                  }
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: MtSearchField(
                  hintText: 'Search patient, doctor or diagnosis…',
                  dense: true,
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Wrap(
            spacing: 8,
            children: [
              for (final f in _QueueFilter.values)
                ChoiceChip(
                  label: Text(f.label),
                  selected: _filter == f,
                  selectedColor: MtColors.brandSofter,
                  labelStyle: MtTextStyles.labelSm.copyWith(
                    color: _filter == f ? MtColors.brand : MtColors.ink2,
                    fontWeight: FontWeight.w700,
                  ),
                  onSelected: (_) => setState(() => _filter = f),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: async.when(
            loading: () => const Center(
                child: CircularProgressIndicator(color: MtColors.brand)),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(20),
              child: MtErrorState(
                title: "Couldn't load the approval queue",
                message: e.toString(),
                onRetry: () => awaiting
                    ? ref.read(adminPrescriptionQueueProvider.notifier).refresh()
                    : ref.invalidate(
                        adminPrescriptionHistoryProvider(_filter.name)),
              ),
            ),
            data: (rows) {
              final visible = [
                for (final p in rows)
                  if (_matchesQuery(p)) p,
              ];
              if (visible.isEmpty) {
                return MtEmptyState(
                  icon: Icons.verified_outlined,
                  title: awaiting
                      ? 'No prescriptions awaiting review'
                      : 'Nothing here yet',
                  subtitle: awaiting
                      ? 'Scripts appear here the moment the patient settles '
                          'their service balance.'
                      : null,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                itemCount: visible.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _ApprovalCard(
                  script: visible[i],
                  showActions: awaiting,
                  onApprove: () => _decide(visible[i], approve: true),
                  onReject: () => _decide(visible[i], approve: false),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One review row: patient + doctor context, fee/paid metadata, the full
/// Rx table in an expansion body, and the decision buttons.
class _ApprovalCard extends StatelessWidget {
  final Prescription script;
  final bool showActions;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ApprovalCard({
    required this.script,
    required this.showActions,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final paidAt = DateFormat('d MMM y, h:mm a').format(script.issuedAt);
    final chip = releaseChipColors(script.releaseStatus);
    return Container(
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: chip.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.medication_outlined, color: chip.fg),
          ),
          title: Text(
            script.patientName.isEmpty
                ? 'Unknown patient'
                : script.patientName,
            style: MtTextStyles.labelLg
                .copyWith(color: MtColors.ink, fontWeight: FontWeight.w800),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${script.doctorName.isEmpty ? 'Attending physician' : script.doctorName}'
              '${script.doctorVerified ? ' ✓' : ''}'
              ' · ${script.effectiveItemCount} med'
              '${script.effectiveItemCount == 1 ? '' : 's'}'
              ' · balance paid',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (script.patientPhone.isNotEmpty)
                    _MetaLine(
                        icon: Icons.call_outlined,
                        text: script.patientPhone),
                  _MetaLine(
                      icon: Icons.event_outlined, text: 'Issued $paidAt'),
                  if (script.diagnosis.isNotEmpty)
                    _MetaLine(
                        icon: Icons.coronavirus_outlined,
                        text: 'Diagnosis: ${script.diagnosis}'),
                  const SizedBox(height: 8),
                  const Divider(height: 1, color: MtColors.line),
                  const SizedBox(height: 8),
                  for (final item in script.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '• ${item.drugName} — ${item.dosage}, '
                        '${item.frequencyCode}, ${item.mealContext.labelEn}, '
                        '${item.durationDays} day'
                        '${item.durationDays == 1 ? '' : 's'}'
                        '${item.notes.isEmpty ? '' : ' (${item.notes})'}',
                        style: MtTextStyles.bodySm
                            .copyWith(color: MtColors.ink2),
                      ),
                    ),
                ],
              ),
            ),
            if (showActions) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MtColors.rejected,
                        side: const BorderSide(color: MtColors.rejected),
                      ),
                      onPressed: onReject,
                      icon: const Icon(Icons.block_outlined, size: 18),
                      label: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: MtColors.completed),
                      onPressed: onApprove,
                      icon: const Icon(Icons.verified_outlined, size: 18),
                      label: const Text('Approve Prescription'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: MtColors.ink3),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2)),
          ),
        ],
      ),
    );
  }
}
