import 'package:flutter/material.dart';

import '../../../../core/models/booking_transaction.dart';
import '../../../../core/models/deposit_status.dart';
import '../booking_flow_pages.dart' show money;
import 'patient_home_palette.dart';

/// PHASE 2 — the care team called and set the numbers. This is the first (and
/// only) time the patient is asked for money before their visit.
///
/// Rendered inline under the "Admin Call & Fee Set" step of the Active Care
/// timeline, so the ask sits on the step that produced it rather than in a
/// separate surface the patient has to go find.
class DepositPromptCard extends StatelessWidget {
  final BookingTransaction booking;
  final VoidCallback onPay;

  const DepositPromptCard({
    super.key,
    required this.booking,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final failed = booking.depositStatus == DepositStatus.failed;

    return Container(
      decoration: BoxDecoration(
        color: hd.surfaceHi,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hd.accent.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            failed
                ? '⏳ Your last ${money(booking.depositDue)} attempt did not go '
                    'through. Please try again to confirm your visit — the '
                    'deposit is deducted from your final bill.'
                : '📞 Your care team set your booking deposit to '
                    '${money(booking.depositDue)}. Pay it to confirm your '
                    'visit — it is deducted from your final bill.',
            style: TextStyle(color: hd.body, fontSize: 12.5, height: 1.45),
          ),
          // The full picture the review call produced, so the deposit is
          // legible as part of a total rather than an unexplained charge.
          if (booking.hasFinalPrice) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: hd.canvas,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: hd.border),
              ),
              child: Column(
                children: [
                  _DepositLine(
                    label: 'Total service fee',
                    value: money(booking.finalServiceFee ?? 0),
                  ),
                  if ((booking.adjustedDiscount ?? 0) > 0) ...[
                    const SizedBox(height: 8),
                    _DepositLine(
                      label: 'Discount',
                      value: '− ${money(booking.adjustedDiscount ?? 0)}',
                      valueColor: hd.positive,
                    ),
                  ],
                  const SizedBox(height: 8),
                  _DepositLine(
                    label: 'Deposit due now',
                    value: money(booking.depositDue),
                    emphasize: true,
                  ),
                  const SizedBox(height: 8),
                  _DepositLine(
                    label: 'Remaining after your visit',
                    value: money(
                      (booking.finalServiceFee ?? 0) -
                          booking.depositDue -
                          (booking.adjustedDiscount ?? 0),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(colors: [hd.violet2, hd.violet]),
                boxShadow: [BoxShadow(color: hd.glow, blurRadius: 18)],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onPay,
                  borderRadius: BorderRadius.circular(14),
                  child: Center(
                    child: Text(
                      failed
                          ? 'Retry ${money(booking.depositDue)} Deposit'
                          : 'Pay ${money(booking.depositDue)} to Confirm',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// PHASE 1 — the request is in, free, and the care team owes the patient a
/// call. Reassurance only: no amount, no CTA, nothing to pay.
///
/// This card exists so "nothing is due" reads as a deliberate state rather
/// than a screen that failed to load its price.
class AwaitingReviewCallCard extends StatelessWidget {
  const AwaitingReviewCallCard({super.key});

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return Container(
      decoration: BoxDecoration(
        color: hd.surfaceHi,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hd.border),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.phone_in_talk_rounded, size: 18, color: hd.positive),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "We'll call you shortly",
                  style: TextStyle(
                    color: hd.title,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '✅ You paid nothing to place this request. Our care team is '
            'reviewing your case and will call you to discuss your medical '
            'needs, set the service fee, and confirm the advance deposit for '
            'your visit.',
            style: TextStyle(color: hd.body, fontSize: 12.5, height: 1.45),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: hd.canvas,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: hd.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total paid so far',
                  style: TextStyle(color: hd.muted, fontSize: 12.5),
                ),
                Text(
                  money(0),
                  style: TextStyle(
                    color: hd.positive,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
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

/// One `label ........ value` row in the deposit prompt's fee breakdown.
class _DepositLine extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool emphasize;

  const _DepositLine({
    required this.label,
    required this.value,
    this.valueColor,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: emphasize ? hd.title : hd.muted,
              fontSize: 12.5,
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? (emphasize ? hd.title : hd.body),
            fontSize: emphasize ? 14.5 : 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
