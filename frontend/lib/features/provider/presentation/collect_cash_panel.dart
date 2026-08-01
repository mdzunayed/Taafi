import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/care_request_status.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/mt_button.dart';
import '../../auth/auth_provider.dart';
import '../providers/nurse_workflow_provider.dart';

/// Outstanding cash due on a freshly completed visit, or `null` when
/// there is nothing to collect. Reads the raw appointment document the
/// completion endpoints return (`status`, `final_price`,
/// `deposit_amount`, `adjusted_discount`) — the same formula as the
/// backend's `outstandingBalanceFor`, used here only for DISPLAY; the
/// collect-cash endpoint recomputes the amount server-side and never
/// trusts the client.
double? cashDueFromAppointment(Map<String, dynamic>? appointment) {
  if (appointment == null) return null;
  final status = (appointment['status'] ?? '').toString();
  if (status != CareRequestStatus.serviceCompletedAwaitingFinalPayment) {
    return null;
  }
  double money(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  final due = money(appointment['final_price']) -
      money(appointment['deposit_amount']) -
      money(appointment['adjusted_discount']);
  return due > 0 ? due : null;
}

/// If the just-completed visit still owes its balance, present the
/// "Collect Cash" panel and let the provider settle it on the spot.
/// No-op (returns immediately) for already-paid / legacy visits, so the
/// consoles can call it unconditionally after every completion.
Future<void> offerCashCollection(
  BuildContext context,
  WidgetRef ref, {
  required Map<String, dynamic>? appointment,
  required String patientName,
}) async {
  final due = cashDueFromAppointment(appointment);
  if (due == null || !context.mounted) return;
  final appointmentId =
      (appointment!['id'] ?? appointment['_id'] ?? '').toString();
  if (appointmentId.isEmpty) return;
  // When the patient pre-committed to Cash on Service, collection is
  // mandatory — the sheet drops the prominent "pay online later" skip.
  final mandatory =
      (appointment['payment_preference'] ?? '').toString() == 'CASH_ON_SERVICE';
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => CollectCashSheet(
      appointmentId: appointmentId,
      patientName: patientName,
      amountDue: due,
      mandatory: mandatory,
    ),
  );
}

/// Compact inline banner surfaced on a provider's active-job surfaces when
/// the patient pre-selected Cash on Service, so the provider knows to collect
/// the balance in cash before they mark the visit complete.
class CashOnServiceBadge extends StatelessWidget {
  const CashOnServiceBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: MtColors.completedBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.completed.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.payments_rounded,
              color: MtColors.completed, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Cash on service — collect the balance in cash before you '
              'complete this visit.',
              style: MtTextStyles.bodySm.copyWith(
                color: MtColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The "Collect Cash" panel — shown right after a provider completes a
/// visit whose balance is unpaid. Green = completion action. The patient
/// can alternatively pay online later, so skipping is always available.
class CollectCashSheet extends ConsumerStatefulWidget {
  final String appointmentId;
  final String patientName;
  final double amountDue;

  /// True when the patient pre-selected Cash on Service. The sheet then omits
  /// the prominent "pay online" skip and de-emphasizes the escape hatch so
  /// collection is the clear expected action.
  final bool mandatory;

  const CollectCashSheet({
    super.key,
    required this.appointmentId,
    required this.patientName,
    required this.amountDue,
    this.mandatory = false,
  });

  @override
  ConsumerState<CollectCashSheet> createState() => _CollectCashSheetState();
}

class _CollectCashSheetState extends ConsumerState<CollectCashSheet> {
  bool _busy = false;
  String? _error;

  String get _amountLabel => '৳${widget.amountDue.round()}';

  Future<void> _confirmAndCollect() async {
    if (_busy) return;
    HapticFeedback.mediumImpact();
    // Explicit confirmation — this credits company cash onto the
    // provider's own reconciliation ledger and cannot be undone in-app.
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MtColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Confirm cash received?',
            style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
        content: Text(
          'You are confirming that ${widget.patientName} handed you '
          '$_amountLabel in cash. The amount is added to your cash-in-hand '
          "ledger and the patient's prescription gate unlocks instantly.",
          style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MtColors.completed),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, cash received'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(dioClientProvider)
          .collectCashPayment(widget.appointmentId);
      if (!mounted) return;
      final holding = (result['cashInHand'] as num?)?.round();
      // Refresh the provider's cash-in-hand ledger card instantly (the
      // workspace badge reads nurseEarningsProvider.cashInHand) instead of
      // waiting out its poll.
      ref.invalidate(nurseEarningsProvider);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: MtColors.completed,
          content: Text(
            holding == null
                ? 'Cash payment recorded — booking settled.'
                : 'Cash payment recorded — you now hold ৳$holding for Taafi.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _busy = false;
        _error = raw.length > 160 ? '${raw.substring(0, 160)}…' : raw;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: MtColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MtColors.line,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: MtColors.completedBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.payments_outlined,
                        color: MtColors.completed),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            widget.mandatory
                                ? 'Collect Cash · Required'
                                : 'Collect Cash',
                            style:
                                MtTextStyles.h3.copyWith(color: MtColors.ink)),
                        const SizedBox(height: 2),
                        Text(
                          widget.mandatory
                              ? 'Patient chose to pay in cash at the door'
                              : 'Outstanding balance for this visit',
                          style: MtTextStyles.bodySm
                              .copyWith(color: MtColors.ink3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // The amount owed — big, unambiguous, green-framed.
              Container(
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: MtColors.completedBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: MtColors.completed.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      _amountLabel,
                      textAlign: TextAlign.center,
                      style: MtTextStyles.h1.copyWith(
                        color: MtColors.completed,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'due from ${widget.patientName}',
                      textAlign: TextAlign.center,
                      style:
                          MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Confirming adds this amount to your cash-in-hand ledger '
                '(company money you are holding) and instantly unlocks the '
                "patient's prescription gate.",
                style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: MtTextStyles.bodySm.copyWith(color: MtColors.rejected),
                ),
              ],
              const SizedBox(height: 18),
              MtButton(
                label: 'Confirm Cash Received',
                leadingIcon: Icons.check_circle_outline,
                backgroundColor: MtColors.completed,
                isLoading: _busy,
                onPressed: _confirmAndCollect,
              ),
              const SizedBox(height: 10),
              if (widget.mandatory)
                // Mandatory flow: no prominent skip. A de-emphasized escape
                // hatch (with confirmation) for the real-world case where the
                // patient can't produce cash — the patient can then settle
                // online from their invoice ("Pay online instead").
                Center(
                  child: TextButton(
                    onPressed: _busy ? null : _handleCouldNotCollect,
                    child: Text(
                      "Patient couldn't pay in cash",
                      style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                    ),
                  ),
                )
              else
                MtButton(
                  label: 'Skip — patient will pay online',
                  isOutlined: true,
                  onPressed: () {
                    if (!_busy) Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleCouldNotCollect() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MtColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Close without collecting?',
            style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
        content: Text(
          'The patient chose Cash on Service. If you close without collecting, '
          'the balance stays open and the patient can settle it online from '
          'their invoice. Only do this if cash truly could not be collected.',
          style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep collecting'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Close', style: TextStyle(color: MtColors.rejected)),
          ),
        ],
      ),
    );
    if (proceed == true && mounted) Navigator.of(context).pop();
  }
}
