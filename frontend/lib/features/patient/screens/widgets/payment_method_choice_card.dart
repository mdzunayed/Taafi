import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/patient_home_repository.dart';
import '../../../../core/models/care_request_status.dart';
import '../../../../core/models/patient_active_request.dart';
import '../../../../core/theme/app_colors_ext.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../auth/auth_provider.dart';

final _moneyFmt = NumberFormat.decimalPattern();
String _taka(num n) => '৳${_moneyFmt.format(n.round())}';

const _kCash = 'CASH_ON_SERVICE';
const _kDigital = 'DIGITAL';

/// Raw `care_requests.status` values in which the patient is actively
/// tracking a dispatched provider and can still pre-commit to how they'll
/// settle the balance. Deliberately excludes review (no provider yet) and
/// terminal / awaiting-final-payment states (the visit is already done).
const _selectableRawStatuses = <String>{
  CareRequestStatus.assigned,
  CareRequestStatus.enroute,
  CareRequestStatus.onTheWay,
  CareRequestStatus.arrived,
  CareRequestStatus.inService,
};

/// The patient's upfront "how will you pay the balance?" selector, shown on
/// the Tracking bottom sheet while the assigned provider is en route / on
/// site. Picking **Cash on Service** records the intent server-side
/// (`PATCH /patient/requests/:id/payment-preference`) so the provider's
/// collect-cash step becomes mandatory at completion; **Digital** keeps the
/// gateway path. No money moves here — this is a pre-commitment only.
class PaymentMethodChoiceCard extends ConsumerStatefulWidget {
  final PatientActiveRequest request;

  const PaymentMethodChoiceCard({super.key, required this.request});

  /// Whether the selector is relevant for [r]: the booking is priced, still
  /// has an outstanding balance, and is in a live tracking state.
  static bool shouldShow(PatientActiveRequest r) {
    return (r.finalServiceFee ?? 0) > 0 &&
        r.outstandingBalance > 0 &&
        _selectableRawStatuses.contains(r.rawStatus);
  }

  @override
  ConsumerState<PaymentMethodChoiceCard> createState() =>
      _PaymentMethodChoiceCardState();
}

class _PaymentMethodChoiceCardState
    extends ConsumerState<PaymentMethodChoiceCard> {
  late String _choice = widget.request.paymentPreference ?? _kDigital;
  bool _busy = false;
  String? _error;

  @override
  void didUpdateWidget(covariant PaymentMethodChoiceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A live poll / socket refresh landed a committed preference — realign
    // the local selection so the "Confirm" button dismisses on its own.
    final committed = widget.request.paymentPreference;
    if (committed != null &&
        committed != oldWidget.request.paymentPreference &&
        !_busy) {
      _choice = committed;
    }
  }

  bool get _dirty => _choice != (widget.request.paymentPreference ?? _kDigital);

  Future<void> _confirm() async {
    if (_busy) return;
    HapticFeedback.selectionClick();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(dioClientProvider)
          .setPaymentPreference(widget.request.id, _choice);
      // Pull the authoritative row back so every dependent card (invoice,
      // provider badge on the next poll) reflects the committed choice.
      await ref.read(patientHomeFeedProvider.notifier).refresh();
      if (!mounted) return;
      setState(() => _busy = false);
      final choseCash = _choice == _kCash;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: context.appColors.positive,
          content: Text(
            choseCash
                ? 'Cash payment selected — pay your provider at the door.'
                : 'Digital payment selected.',
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
    final c = context.appColors;
    final r = widget.request;
    final cashSelected = _choice == _kCash;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surfaceHi,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HOW WILL YOU PAY THE BALANCE?',
            style: MtTextStyles.sectionLabel.copyWith(
              color: c.brand,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose now so your provider knows what to expect. You can '
            'change this any time before the visit ends.',
            style: MtTextStyles.bodySm.copyWith(color: c.body),
          ),
          const SizedBox(height: 12),
          _OptionTile(
            icon: Icons.credit_card_rounded,
            title: 'Digital Payment',
            subtitle: 'bKash · Nagad · Card — pay in the app',
            selected: !cashSelected,
            onTap: _busy ? null : () => setState(() => _choice = _kDigital),
          ),
          const SizedBox(height: 10),
          _OptionTile(
            icon: Icons.payments_rounded,
            title: 'Cash on Service',
            subtitle: 'Pay the doctor / nurse at your doorstep',
            selected: cashSelected,
            onTap: _busy ? null : () => setState(() => _choice = _kCash),
          ),
          if (cashSelected) ...[
            const SizedBox(height: 12),
            _CashSummaryBox(
              totalFee: r.finalServiceFee ?? 0,
              deposit: r.depositAmount,
              discount: r.adjustedDiscount ?? 0,
              due: r.outstandingBalance,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: MtTextStyles.bodySm.copyWith(color: c.danger),
            ),
          ],
          if (_dirty) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _confirm,
                style: FilledButton.styleFrom(
                  backgroundColor: cashSelected ? c.positive : c.brand,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        cashSelected
                            ? 'Confirm Cash Payment Choice'
                            : 'Confirm Digital Payment',
                        style: MtTextStyles.labelLg.copyWith(
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ] else if (r.paymentPreference != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    size: 18, color: c.positive),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    cashSelected
                        ? 'Cash selected — please have ${_taka(r.outstandingBalance)} '
                            'ready for your provider.'
                        : 'Digital payment selected.',
                    style: MtTextStyles.bodySm.copyWith(color: c.body),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final accent = selected ? c.brand : c.cardBorder;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? c.brand.withValues(alpha: 0.08) : c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: accent,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected
                    ? c.brand.withValues(alpha: 0.14)
                    : c.surfaceHi,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  color: selected ? c.brand : c.muted, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: MtTextStyles.labelLg.copyWith(color: c.title)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: MtTextStyles.bodySm.copyWith(color: c.muted)),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? c.brand : c.muted,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _CashSummaryBox extends StatelessWidget {
  final double totalFee;
  final double deposit;
  final double discount;
  final double due;

  const _CashSummaryBox({
    required this.totalFee,
    required this.deposit,
    required this.discount,
    required this.due,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.positiveBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.positive.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          _row(context, 'Total Fee', _taka(totalFee)),
          const SizedBox(height: 8),
          _row(context, 'Deposit Paid', '- ${_taka(deposit)}',
              valueColor: c.positive),
          if (discount > 0) ...[
            const SizedBox(height: 8),
            _row(context, 'Discount', '- ${_taka(discount)}',
                valueColor: c.positive),
          ],
          const SizedBox(height: 10),
          Container(height: 1, color: c.positive.withValues(alpha: 0.25)),
          const SizedBox(height: 10),
          _row(context, 'Cash Due at Door', _taka(due), emphasize: true),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: c.body),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Please pay exactly ${_taka(due)} in cash to your assigned '
                  'provider after the visit is complete.',
                  style: MtTextStyles.bodySm.copyWith(color: c.body),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {bool emphasize = false, Color? valueColor}) {
    final c = context.appColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: emphasize
              ? MtTextStyles.labelLg.copyWith(color: c.title)
              : MtTextStyles.bodyMd.copyWith(color: c.body),
        ),
        Text(
          value,
          style: emphasize
              ? MtTextStyles.h3.copyWith(
                  color: c.positive, fontWeight: FontWeight.w800)
              : MtTextStyles.bodyMd.copyWith(
                  color: valueColor ?? c.title,
                  fontWeight: FontWeight.w600,
                ),
        ),
      ],
    );
  }
}
