import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/patient_home_repository.dart';
import '../../../core/payments/gateway_payment.dart';
import '../../../core/widgets/frosted_surface.dart';
import '../../../core/models/booking_transaction.dart';
import '../../auth/auth_provider.dart';
import 'widgets/patient_home_palette.dart';

final _moneyFmt = NumberFormat('#,###', 'en_US');
String money(num n) => '৳${_moneyFmt.format(n.round())}';

/// Fixed slot-confirmation deposit — kept in lockstep with the backend.
const double kDepositAmount = 100;

// ===========================================================================
// Phase 1 — The ৳100 confirmation gateway deck.
// ===========================================================================

/// Presents the premium glassmorphic checkout sheet titled
/// "Confirm Appointment Request". Returns `true` once the deposit has been
/// initiated/settled (the Under Review tab then reflects the new status).
Future<bool> showConfirmAppointmentRequestSheet(
  BuildContext context, {
  required String bookingId,
  required String serviceName,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => _ConfirmAppointmentRequestSheet(
      bookingId: bookingId,
      serviceName: serviceName,
    ),
  );
  return result ?? false;
}

/// The available (cosmetic) payment rails. All route through the SSLCommerz
/// hosted checkout, which surfaces the corresponding method on its page.
enum _PayRail { bkash, nagad, card }

extension _PayRailX on _PayRail {
  String get label {
    switch (this) {
      case _PayRail.bkash:
        return 'bKash';
      case _PayRail.nagad:
        return 'Nagad';
      case _PayRail.card:
        return 'Visa / Mastercard';
    }
  }

  String get glyph {
    switch (this) {
      case _PayRail.bkash:
        return 'bK';
      case _PayRail.nagad:
        return 'N';
      case _PayRail.card:
        return '💳';
    }
  }

  Color get tint {
    switch (this) {
      case _PayRail.bkash:
        return const Color(0xFFE2136E);
      case _PayRail.nagad:
        return const Color(0xFFF6821F);
      case _PayRail.card:
        return const Color(0xFF6366F1); // indigo — theme-agnostic rail tint
    }
  }
}

class _ConfirmAppointmentRequestSheet extends ConsumerStatefulWidget {
  final String bookingId;
  final String serviceName;

  const _ConfirmAppointmentRequestSheet({
    required this.bookingId,
    required this.serviceName,
  });

  @override
  ConsumerState<_ConfirmAppointmentRequestSheet> createState() =>
      _ConfirmAppointmentRequestSheetState();
}

class _ConfirmAppointmentRequestSheetState
    extends ConsumerState<_ConfirmAppointmentRequestSheet> {
  _PayRail _selected = _PayRail.bkash;
  bool _busy = false;
  String? _error;

  Future<void> _pay() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await runDepositPayment(ref, widget.bookingId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _readable(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: blurLayer(
          blur: 18,
          child: Container(
            decoration: BoxDecoration(
              color: hd.canvas.withValues(
                alpha: FrostedSurface.blurSupported ? 0.92 : 0.98,
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: hd.violet.withValues(alpha: 0.35)),
              boxShadow: [
                BoxShadow(
                  color: hd.glow,
                  blurRadius: 40,
                  spreadRadius: 4,
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: hd.border,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Confirm Appointment Request',
                    style: TextStyle(
                      color: hd.title,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'To secure your slot and connect with our care management '
                    'team, a formal ৳100 confirmation deposit is required. '
                    'This amount will be deducted from your final bill.',
                    style: TextStyle(
                      color: hd.body,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _DepositAmountBanner(serviceName: widget.serviceName),
                  const SizedBox(height: 18),
                  Text(
                    'PAYMENT METHOD',
                    style: TextStyle(
                      color: hd.muted,
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final rail in _PayRail.values) ...[
                    _PayRailTile(
                      rail: rail,
                      selected: _selected == rail,
                      onTap: _busy
                          ? null
                          : () => setState(() => _selected = rail),
                    ),
                    if (rail != _PayRail.values.last)
                      const SizedBox(height: 10),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: hd.danger,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _GlowButton(
                    label: 'Pay ৳100 & Confirm',
                    busy: _busy,
                    onTap: _busy ? null : _pay,
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline,
                            size: 13, color: hd.muted),
                        const SizedBox(width: 6),
                        Text(
                          'Secured by SSLCommerz',
                          style:
                              TextStyle(color: hd.muted, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DepositAmountBanner extends StatelessWidget {
  final String serviceName;
  const _DepositAmountBanner({required this.serviceName});

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [hd.violetDeep, hd.violet],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: hd.violetBright.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  serviceName.isEmpty ? 'Care service' : serviceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Confirmation deposit',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            money(kDepositAmount),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PayRailTile extends StatelessWidget {
  final _PayRail rail;
  final bool selected;
  final VoidCallback? onTap;

  const _PayRailTile({
    required this.rail,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: hd.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? hd.violetBright : hd.border,
              width: selected ? 1.6 : 1,
            ),
            boxShadow: selected
                ? [BoxShadow(color: hd.glow, blurRadius: 18)]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: rail.tint.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  rail.glyph,
                  style: TextStyle(
                    color: rail.tint,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  rail.label,
                  style: TextStyle(
                    color: hd.title,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? hd.violetBright : hd.muted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Phase 2 — The dynamic invoice + live tracker view.
// ===========================================================================

/// High-contrast midnight invoice block shown once the admin prices the
/// booking. Renders the transparent breakdown + the outstanding total and a
/// glowing status pill. Drop into any patient surface (e.g. Under Review).
class DynamicInvoiceCard extends ConsumerStatefulWidget {
  final BookingTransaction booking;

  const DynamicInvoiceCard({super.key, required this.booking});

  @override
  ConsumerState<DynamicInvoiceCard> createState() => _DynamicInvoiceCardState();
}

class _DynamicInvoiceCardState extends ConsumerState<DynamicInvoiceCard> {
  bool _busy = false;
  String? _error;

  Future<void> _payBalance() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await runBalancePayment(ref, widget.booking.bookingId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _readable(e);
      });
    }
  }

  /// Escape hatch for a patient who pre-chose cash but wants to pay online
  /// after all (e.g. the provider couldn't collect). Reverts the preference
  /// to digital, then runs the gateway balance payment.
  Future<void> _switchToDigitalAndPay() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(dioClientProvider)
          .setPaymentPreference(widget.booking.bookingId, 'DIGITAL');
      await runBalancePayment(ref, widget.booking.bookingId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _readable(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final b = widget.booking;
    // The balance is only payable AFTER the service completes (new flow)
    // or in the legacy pay-before-dispatch state. While the booking is
    // under review the card stays a quiet notice — pricing is a silent
    // invoice update and must never prompt a payment.
    final payable =
        b.status == BookingStatus.serviceCompletedAwaitingFinalPayment ||
            b.status == BookingStatus.amountAssignedAwaitingFinalPayment;
    final serviceDone =
        b.status == BookingStatus.serviceCompletedAwaitingFinalPayment;
    final reviewing = !payable;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [hd.surface, hd.canvas],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: hd.border),
        boxShadow: [BoxShadow(color: hd.glow, blurRadius: 26)],
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'INVOICE',
                style: TextStyle(
                  color: hd.muted,
                  fontSize: 11,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
              BookingStatusPill(status: b.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            b.serviceName.isEmpty ? 'Care service' : b.serviceName,
            style: TextStyle(
              color: hd.title,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          if (reviewing)
            _ReviewingNotice()
          else ...[
            if (serviceDone) ...[
              Text(
                'Your care visit is complete. Settle the outstanding '
                'balance to close your booking and receive your '
                'prescription.',
                style: TextStyle(
                  color: hd.body,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
            ],
            _InvoiceRow(
              label: 'Base Service Fee',
              value: money(b.finalServiceFee ?? 0),
            ),
            if ((b.adjustedDiscount ?? 0) > 0) ...[
              const SizedBox(height: 12),
              _InvoiceRow(
                label: 'Discount Applied',
                value: '- ${money(b.adjustedDiscount ?? 0)}',
                valueColor: hd.positive,
              ),
            ],
            const SizedBox(height: 12),
            _InvoiceRow(
              label: 'Confirmation Deposit Paid',
              value: '- ${money(b.depositAmount)}',
              valueColor: hd.positive,
            ),
            const SizedBox(height: 14),
            Container(height: 1, color: hd.border),
            const SizedBox(height: 14),
            _InvoiceRow(
              label: 'Total Outstanding Fee',
              value: money(b.outstanding),
              emphasize: true,
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: TextStyle(color: hd.danger, fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 18),
            // When the patient pre-committed to Cash on Service, the digital
            // "Pay Balance" button is replaced by a cash-arranged notice —
            // settlement happens when the provider confirms receipt on their
            // device (collect-cash endpoint), which unlocks the prescription.
            if (b.isCashChosen && b.outstanding > 0)
              _CashArrangedNotice(
                amount: b.outstanding,
                busy: _busy,
                onPayOnline: _busy ? null : _switchToDigitalAndPay,
              )
            else ...[
              _GlowButton(
                label: b.outstanding <= 0
                    ? 'Confirm & Proceed'
                    : 'Pay Balance · ${money(b.outstanding)}',
                busy: _busy,
                onTap: _busy ? null : _payBalance,
              ),
              // Cash-to-provider alternative: the provider confirms receipt
              // on THEIR device (collect-cash endpoint) — nothing for the
              // patient to tap here, so this is an indicator, not a button.
              if (serviceDone && b.outstanding > 0) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: hd.positive.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: hd.positive.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.payments_outlined,
                          color: hd.positive, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Or pay cash to your provider',
                              style: TextStyle(
                                color: hd.title,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'If paying in cash, your prescription will '
                              'unlock immediately once the provider confirms '
                              'receipt on their device.',
                              style: TextStyle(
                                color: hd.body,
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }
}

/// Replaces the digital "Pay Balance" button once the patient has committed
/// to Cash on Service — the balance is settled when the provider confirms
/// receiving the cash on their device (no patient action here).
class _CashArrangedNotice extends StatelessWidget {
  final double amount;
  final bool busy;
  final VoidCallback? onPayOnline;
  const _CashArrangedNotice({
    required this.amount,
    required this.busy,
    required this.onPayOnline,
  });

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hd.positive.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hd.positive.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  color: hd.positive, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cash payment arranged',
                      style: TextStyle(
                        color: hd.title,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Please have ${money(amount)} ready to hand to your '
                      'provider. Your booking settles — and your prescription '
                      'unlocks — the moment they confirm receipt.',
                      style: TextStyle(
                        color: hd.body,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onPayOnline,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: busy
                  ? SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2, color: hd.violetBright),
                    )
                  : Text(
                      'Prefer to pay online? Switch to digital',
                      style: TextStyle(
                        color: hd.violetBright,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewingNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.hourglass_top_rounded,
            color: hd.violetBright, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Your ৳100 deposit is confirmed. Our care management team is '
            'reviewing your case and will finalise your service fee shortly — '
            'your invoice will appear here automatically.',
            style: TextStyle(
              color: hd.body,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool emphasize;

  const _InvoiceRow({
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
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: TextStyle(
            color: emphasize ? hd.title : hd.body,
            fontSize: emphasize ? 15 : 13.5,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? (emphasize ? hd.title : hd.body),
            fontSize: emphasize ? 22 : 14,
            fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Glowing status pill badge — `● Pending Balance Payment`,
/// `● Under Care Management Review`, etc.
class BookingStatusPill extends StatelessWidget {
  final BookingStatus status;
  const BookingStatusPill({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status.pillColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            status.labelEn,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Shared building blocks
// ===========================================================================

class _GlowButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onTap;

  const _GlowButton({required this.label, required this.busy, this.onTap});

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: onTap == null && !busy
              ? null
              : LinearGradient(
                  colors: [hd.violet2, hd.violet],
                ),
          color: onTap == null && !busy ? hd.surfaceHi : null,
          boxShadow: onTap == null
              ? null
              : [BoxShadow(color: hd.glow, blurRadius: 22)],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Payment orchestration (init → gateway/simulated → confirm → refresh)
// ===========================================================================

/// Runs the ৳100 deposit payment. In simulated mode (no gateway keys) it
/// settles instantly; with a real SSLCommerz session it opens the hosted
/// checkout externally and lets the server-side IPN settle it (the home
/// feed poll then reflects the new status).
Future<void> runDepositPayment(WidgetRef ref, String bookingId) async {
  final dio = ref.read(dioClientProvider);
  final session = await dio.initBookingDeposit(bookingId);
  await _completePayment(
    ref: ref,
    session: session,
    confirm: (tranId) => dio.confirmBookingDeposit(bookingId, tranId: tranId),
  );
}

/// Runs the outstanding-balance payment (Phase 2).
Future<void> runBalancePayment(WidgetRef ref, String bookingId) async {
  final dio = ref.read(dioClientProvider);
  final session = await dio.initBookingBalance(bookingId);
  await _completePayment(
    ref: ref,
    session: session,
    confirm: (tranId) => dio.confirmBookingBalance(bookingId, tranId: tranId),
  );
}

Future<void> _completePayment({
  required WidgetRef ref,
  required Map<String, dynamic> session,
  required Future<Map<String, dynamic>> Function(String? tranId) confirm,
}) async {
  // Shared gateway runner (core/payments/gateway_payment.dart); the
  // home-feed refresh stays here because it's booking-flow-specific.
  await completeGatewayPayment(session: session, confirm: confirm);
  // ignore: unused_result
  await ref.read(patientHomeFeedProvider.notifier).refresh();
}

String _readable(Object e) {
  final raw = e.toString().replaceFirst('Exception: ', '');
  return raw.length > 160 ? '${raw.substring(0, 160)}…' : raw;
}
