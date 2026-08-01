import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/admin_models.dart';
import '../../../../core/models/prescription.dart';
import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/widgets/mt_error_state.dart';
import '../../../auth/auth_provider.dart';
import '../../admin_providers.dart';
import '../../widgets/triage_slide_over.dart';
import 'admin_booking_review.dart'
    show bookingReviewQueueProvider, awaitingPaymentQueueProvider;
import 'admin_table_chrome.dart';

final _moneyFmt = NumberFormat('#,###', 'en_US');
String _money(num n) => '৳${_moneyFmt.format(n.round())}';
final _pipelineDate = DateFormat('MMM d · h:mm a');

/// Bookings paid/approved and waiting for a team — the third pipeline stage.
/// Derived from the shared care-requests feed (`approved` = admin-approved,
/// awaiting dispatch; also where a doctor decline lands).
final _needsAssignmentQueueProvider = Provider<List<AdminCareRequest>>((ref) {
  final async = ref.watch(adminRequestsProvider);
  return async.maybeWhen(
    data: (list) =>
        list.where((r) => r.status == 'approved').toList(growable: false),
    orElse: () => const <AdminCareRequest>[],
  );
});

/// Priced bookings awaiting the patient's balance payment — stage two. Spans
/// both the legacy `amount_assigned_awaiting_final_payment` state and the
/// pay-after-service `service_completed_awaiting_final_payment` state.
final _awaitingPaymentAllProvider = Provider<List<AdminCareRequest>>((ref) {
  final legacy = ref.watch(awaitingPaymentQueueProvider);
  final async = ref.watch(adminRequestsProvider);
  final postService = async.maybeWhen(
    data: (list) => list
        .where((r) => r.status == 'service_completed_awaiting_final_payment')
        .toList(growable: false),
    orElse: () => const <AdminCareRequest>[],
  );
  return [...legacy, ...postService];
});

enum _Stage { pricing, payment, assignment, review }

extension _StageMeta on _Stage {
  String get label => switch (this) {
        _Stage.pricing => 'Awaiting Fee Pricing',
        _Stage.payment => 'Awaiting Payment',
        _Stage.assignment => 'Needs Team Assignment',
        _Stage.review => 'Rx & Report Review',
      };

  IconData get icon => switch (this) {
        _Stage.pricing => Icons.request_quote_outlined,
        _Stage.payment => Icons.hourglass_bottom_outlined,
        _Stage.assignment => Icons.groups_2_outlined,
        _Stage.review => Icons.fact_check_outlined,
      };
}

/// Unified Live Booking Pipeline — the whole booking lifecycle on one
/// high-density board. The four stages read from the SAME providers the
/// standalone Booking-review / Assign-team / Rx-approvals tabs use, so this
/// consolidated view and those tabs never drift. Clicking any booking row
/// opens the shared triage slide-over drawer for full detail + quick actions.
class LiveBookingPipelinePage extends ConsumerStatefulWidget {
  /// Cross-navigation to sibling admin tabs (used to hand a booking to the
  /// full Assign-team workspace at index 2).
  final ValueChanged<int>? onNavigateTab;
  const LiveBookingPipelinePage({super.key, this.onNavigateTab});

  @override
  ConsumerState<LiveBookingPipelinePage> createState() =>
      _LiveBookingPipelinePageState();
}

class _LiveBookingPipelinePageState
    extends ConsumerState<LiveBookingPipelinePage> {
  _Stage _stage = _Stage.pricing;

  @override
  Widget build(BuildContext context) {
    final pricing = ref.watch(bookingReviewQueueProvider);
    final payment = ref.watch(_awaitingPaymentAllProvider);
    final assignment = ref.watch(_needsAssignmentQueueProvider);
    final rxAsync = ref.watch(adminPrescriptionQueueProvider);
    final rxCount = rxAsync.maybeWhen(data: (l) => l.length, orElse: () => 0);

    final counts = {
      _Stage.pricing: pricing.length,
      _Stage.payment: payment.length,
      _Stage.assignment: assignment.length,
      _Stage.review: rxCount,
    };

    return AdminListScaffold(
      title: 'Live Booking Pipeline',
      subtitle:
          'One board for the full booking lifecycle — pricing, payment, dispatch, and review',
      onRefresh: () async {
        ref.invalidate(adminRequestsProvider);
        ref.invalidate(adminPrescriptionQueueProvider);
        await ref.read(adminRequestsProvider.future);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Stage selector ───────────────────────────────────────────
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final s in _Stage.values)
                _StageChip(
                  stage: s,
                  count: counts[s] ?? 0,
                  selected: _stage == s,
                  onTap: () => setState(() => _stage = s),
                ),
            ],
          ),
          const SizedBox(height: 20),
          // ── Active stage body ────────────────────────────────────────
          switch (_stage) {
            _Stage.pricing =>
              _PricingStage(requests: pricing, onOpen: _openDrawer),
            _Stage.payment =>
              _PaymentStage(requests: payment, onOpen: _openDrawer),
            _Stage.assignment => _AssignmentStage(
                requests: assignment,
                onOpen: _openDrawer,
                onAssign: _handOffToAssign,
              ),
            _Stage.review => _ReviewStage(async: rxAsync),
          },
        ],
      ),
    );
  }

  void _openDrawer(AdminCareRequest request) {
    showTriageSlideOver(
      context,
      request: request,
      onAssignTeam: () {
        Navigator.pop(context);
        _handOffToAssign(request);
      },
    );
  }

  /// Hand a booking to the full Assign-team workspace (index 2), which owns
  /// the roster matcher + dispatch flow. Reuses the existing selection state.
  void _handOffToAssign(AdminCareRequest request) {
    ref.read(selectedRequestProvider.notifier).state = request;
    widget.onNavigateTab?.call(2);
  }
}

class _StageChip extends StatelessWidget {
  final _Stage stage;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const _StageChip({
    required this.stage,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? MtColors.brand : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? MtColors.brand : MtColors.line,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(stage.icon,
                size: 18,
                color: selected ? Colors.white : MtColors.ink3),
            const SizedBox(width: 8),
            Text(stage.label,
                style: MtTextStyles.labelMd.copyWith(
                  color: selected ? Colors.white : MtColors.ink,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.22)
                    : MtColors.brandSofter,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('$count',
                  style: MtTextStyles.labelSm.copyWith(
                    color: selected ? Colors.white : MtColors.brand,
                    fontWeight: FontWeight.w800,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared row shell ────────────────────────────────────────────────────────

class _BookingRow extends StatelessWidget {
  final AdminCareRequest request;
  final VoidCallback onOpen;
  final Widget action;
  final String priceLabel;
  const _BookingRow({
    required this.request,
    required this.onOpen,
    required this.action,
    required this.priceLabel,
  });

  @override
  Widget build(BuildContext context) {
    final r = request;
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            if (r.isUrgent) ...[
              const Icon(Icons.local_fire_department,
                  size: 16, color: MtColors.rejected),
              const SizedBox(width: 6),
            ],
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.patientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MtTextStyles.labelMd
                          .copyWith(color: MtColors.ink)),
                  const SizedBox(height: 2),
                  Text('${r.serviceName} · ${r.area}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MtTextStyles.bodySm
                          .copyWith(color: MtColors.ink3)),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(_pipelineDate.format(r.createdAt),
                  style:
                      MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
            ),
            Expanded(
              flex: 2,
              child: Text(priceLabel,
                  textAlign: TextAlign.right,
                  style: MtTextStyles.labelMd
                      .copyWith(color: MtColors.brand)),
            ),
            const SizedBox(width: 12),
            action,
          ],
        ),
      ),
    );
  }
}

Widget _stageCard(List<Widget> rows) {
  return AdminCard(
    child: Column(
      children: [
        for (int i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: MtColors.line),
          rows[i],
        ],
      ],
    ),
  );
}

// ── Stage 1: Pricing ────────────────────────────────────────────────────────

class _PricingStage extends ConsumerWidget {
  final List<AdminCareRequest> requests;
  final ValueChanged<AdminCareRequest> onOpen;
  const _PricingStage({required this.requests, required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (requests.isEmpty) {
      return const AdminEmptyState(
        icon: Icons.request_quote_outlined,
        title: 'Nothing awaiting pricing',
        subtitle: 'Deposit-paid bookings needing a service fee show up here.',
      );
    }
    return _stageCard([
      for (final r in requests)
        _BookingRow(
          request: r,
          onOpen: () => onOpen(r),
          priceLabel: 'Offer ${_money(r.patientOffer)}',
          action: ElevatedButton.icon(
            onPressed: () => _openSetFee(context, ref, r),
            icon: const Icon(Icons.send_outlined, size: 15),
            label: Text('Send invoice',
                style: MtTextStyles.labelMd.copyWith(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: MtColors.brand,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
    ]);
  }
}

Future<void> _openSetFee(
  BuildContext context,
  WidgetRef ref,
  AdminCareRequest request,
) async {
  final feeCtrl = TextEditingController(
    text: (request.adjustedPrice ?? request.patientOffer).toStringAsFixed(0),
  );
  final noteCtrl = TextEditingController(text: request.adminNote ?? '');
  bool submitting = false;
  String? error;

  await showDialog<void>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (dialogCtx, setLocal) {
        Future<void> submit() async {
          final fee = double.tryParse(feeCtrl.text.trim()) ?? 0;
          if (fee <= 0) {
            setLocal(() => error = 'Enter a service fee greater than ৳0.');
            return;
          }
          setLocal(() {
            submitting = true;
            error = null;
          });
          try {
            await ref.read(dioClientProvider).adminSetBookingPrice(
                  request.id,
                  finalServiceFee: fee,
                  adminNote: noteCtrl.text.trim().isEmpty
                      ? null
                      : noteCtrl.text.trim(),
                );
            ref.invalidate(adminRequestsProvider);
            if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
          } catch (e) {
            setLocal(() {
              submitting = false;
              error = e.toString().replaceFirst('Exception: ', '');
            });
          }
        }

        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Invoice ${request.patientName}',
              style: MtTextStyles.h3),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${request.serviceName} · patient offered '
                  '${_money(request.patientOffer)}',
                  style:
                      MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
              const SizedBox(height: 16),
              TextField(
                controller: feeCtrl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Final service fee',
                  prefixText: '৳ ',
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Note to patient (optional)',
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!,
                    style: MtTextStyles.bodySm
                        .copyWith(color: MtColors.rejected)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed:
                  submitting ? null : () => Navigator.of(dialogCtx).pop(),
              child: Text('Cancel',
                  style:
                      MtTextStyles.labelMd.copyWith(color: MtColors.ink3)),
            ),
            ElevatedButton(
              onPressed: submitting ? null : submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: MtColors.brand,
                foregroundColor: Colors.white,
              ),
              child: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text('Send Invoice',
                      style: MtTextStyles.labelMd
                          .copyWith(color: Colors.white)),
            ),
          ],
        );
      },
    ),
  );
}

// ── Stage 2: Awaiting payment ───────────────────────────────────────────────

class _PaymentStage extends StatelessWidget {
  final List<AdminCareRequest> requests;
  final ValueChanged<AdminCareRequest> onOpen;
  const _PaymentStage({required this.requests, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return const AdminEmptyState(
        icon: Icons.hourglass_bottom_outlined,
        title: 'No pending payments',
        subtitle: 'Priced bookings waiting on the patient appear here.',
      );
    }
    return _stageCard([
      for (final r in requests)
        _BookingRow(
          request: r,
          onOpen: () => onOpen(r),
          priceLabel: _money(r.adjustedPrice ?? r.patientOffer),
          action: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: MtColors.pending.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('Awaiting patient',
                style: MtTextStyles.labelSm.copyWith(
                  color: MtColors.pending,
                  fontWeight: FontWeight.w700,
                )),
          ),
        ),
    ]);
  }
}

// ── Stage 3: Needs assignment ───────────────────────────────────────────────

class _AssignmentStage extends StatelessWidget {
  final List<AdminCareRequest> requests;
  final ValueChanged<AdminCareRequest> onOpen;
  final ValueChanged<AdminCareRequest> onAssign;
  const _AssignmentStage({
    required this.requests,
    required this.onOpen,
    required this.onAssign,
  });

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return const AdminEmptyState(
        icon: Icons.groups_2_outlined,
        title: 'No bookings need a team',
        subtitle: 'Approved bookings awaiting dispatch show up here.',
      );
    }
    return _stageCard([
      for (final r in requests)
        _BookingRow(
          request: r,
          onOpen: () => onOpen(r),
          priceLabel: _money(r.adjustedPrice ?? r.patientOffer),
          action: ElevatedButton.icon(
            onPressed: () => onAssign(r),
            icon: const Icon(Icons.person_add_alt_1, size: 15),
            label: Text('Assign team',
                style: MtTextStyles.labelMd.copyWith(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: MtColors.ink,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
    ]);
  }
}

// ── Stage 4: Rx & report review ─────────────────────────────────────────────

class _ReviewStage extends ConsumerWidget {
  final AsyncValue<List<Prescription>> async;
  const _ReviewStage({required this.async});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => MtErrorState(
        message: e.toString(),
        onRetry: () => ref.invalidate(adminPrescriptionQueueProvider),
      ),
      data: (scripts) {
        if (scripts.isEmpty) {
          return const AdminEmptyState(
            icon: Icons.fact_check_outlined,
            title: 'Nothing to review',
            subtitle:
                'Paid prescriptions awaiting a release decision appear here.',
          );
        }
        return _stageCard([
          for (final p in scripts) _RxReviewRow(script: p),
        ]);
      },
    );
  }
}

class _RxReviewRow extends ConsumerWidget {
  final Prescription script;
  const _RxReviewRow({required this.script});

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref, {
    required bool approve,
  }) async {
    HapticFeedback.lightImpact();
    String? reason;
    if (!approve) {
      final ctrl = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Reject prescription', style: MtTextStyles.h3),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Reason (shared with the doctor)',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              style:
                  ElevatedButton.styleFrom(backgroundColor: MtColors.rejected),
              child: const Text('Reject',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (reason == null) return;
    }
    try {
      await ref.read(adminPrescriptionQueueProvider.notifier).decide(
            script.id,
            approve: approve,
            reason: reason,
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = script;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.patientName.isEmpty ? 'Patient' : p.patientName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        MtTextStyles.labelMd.copyWith(color: MtColors.ink)),
                const SizedBox(height: 2),
                Text(
                    '${p.doctorName.isEmpty ? 'Attending physician' : p.doctorName}'
                    ' · ${p.items.length} item(s)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
                p.diagnosis.isEmpty ? '—' : p.diagnosis,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2)),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: () => _decide(context, ref, approve: false),
            style: OutlinedButton.styleFrom(
              foregroundColor: MtColors.rejected,
              side: const BorderSide(color: MtColors.rejected),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            child: Text('Reject', style: MtTextStyles.labelMd),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => _decide(context, ref, approve: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: MtColors.completed,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            child: Text('Approve',
                style: MtTextStyles.labelMd.copyWith(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
