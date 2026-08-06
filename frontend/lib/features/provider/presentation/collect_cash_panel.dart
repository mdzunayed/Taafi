import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/booking_payment_state.dart';
import '../../../core/models/care_request_status.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/mt_button.dart';
import '../../auth/auth_provider.dart';
import '../providers/booking_payment_provider.dart';
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

/// True when the patient pre-committed to paying cash at the door.
/// Reads the raw appointment document the completion endpoints return.
bool isCashOnServiceAppointment(Map<String, dynamic>? appointment) =>
    (appointment?['payment_preference'] ?? '').toString() == 'CASH_ON_SERVICE';

/// If the just-completed visit still owes its balance **and the patient is
/// still paying cash**, present the "Collect Cash" panel and let the provider
/// settle it on the spot.
///
/// The posture is re-read from the server before the sheet opens
/// ([BookingPaymentController.refresh]) rather than taken from the completion
/// response alone: the patient may have switched to Online — or paid — in the
/// seconds between the provider tapping Complete and this call. Opening the
/// sheet on a stale document is exactly what produced the red "Cash cannot be
/// collected — this booking is not awaiting its balance payment" rejection.
///
/// No-op for online-payment bookings: those settle through the gateway and
/// are released by an admin after verification, so a provider must never be
/// shown a cash prompt for one. Also a no-op for already-paid / legacy
/// visits, so the consoles can call it unconditionally after every
/// completion.
Future<void> offerCashCollection(
  BuildContext context,
  WidgetRef ref, {
  required Map<String, dynamic>? appointment,
  required String patientName,
}) async {
  final appointmentId =
      (appointment?['id'] ?? appointment?['_id'] ?? '').toString();
  if (appointmentId.isEmpty) return;

  final controller = ref.read(bookingPaymentProvider(appointmentId).notifier);
  controller.seed(appointment);
  await controller.refresh();
  if (!context.mounted) return;

  final posture = ref.read(bookingPaymentProvider(appointmentId));
  // Server's verdict first; the completion document is only consulted when
  // the posture could not be resolved at all (offline, legacy backend).
  final collectable = posture?.requiresCashCollection ??
      (isCashOnServiceAppointment(appointment) &&
          cashDueFromAppointment(appointment) != null);
  if (!collectable) return;

  final due = posture?.remainingBalance ?? cashDueFromAppointment(appointment);
  if (due == null || due <= 0) return;

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
    ),
  );
}

/// The payment posture card for a provider's active-visit surfaces: the cash
/// warning when a handoff is coming, the read-only online banner otherwise.
///
/// Live by construction — it watches [bookingPaymentProvider], so a patient
/// switching their remaining-balance method mid-visit flips the card on the
/// clinician's screen without a manual refresh. [appointment] is only the
/// seed: whatever the server last said wins over it.
class BookingPaymentBanner extends ConsumerStatefulWidget {
  final String bookingId;

  /// The booking document the screen was launched with, if any — used to
  /// render something sensible before the first fetch resolves.
  final Map<String, dynamic>? appointment;

  /// Fallback posture for consoles that only hold the patient's stated
  /// preference (the dashboard's `UpcomingAppointment`).
  final bool fallbackIsCashOnService;

  const BookingPaymentBanner({
    super.key,
    required this.bookingId,
    this.appointment,
    this.fallbackIsCashOnService = false,
  });

  @override
  ConsumerState<BookingPaymentBanner> createState() =>
      _BookingPaymentBannerState();
}

class _BookingPaymentBannerState extends ConsumerState<BookingPaymentBanner>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Seed from the document in hand so the first frame isn't empty, then
    // converge on the server. Deferred: providers cannot be mutated during
    // build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller =
          ref.read(bookingPaymentProvider(widget.bookingId).notifier);
      controller.seed(widget.appointment);
      controller.refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A backgrounded app misses socket events; the clinician must not come
    // back to a payment card that stopped being true while their screen was
    // off. Re-read on every resume.
    if (state == AppLifecycleState.resumed && mounted) {
      ref.read(bookingPaymentProvider(widget.bookingId).notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final posture = ref.watch(bookingPaymentProvider(widget.bookingId));
    final showCash =
        posture?.requiresCashCollection ?? widget.fallbackIsCashOnService;
    if (showCash) {
      return CashOnServiceBadge(amountDue: posture?.remainingBalance);
    }
    return OnlinePaymentStatusBanner(posture: posture);
  }
}

/// Compact inline banner surfaced on a provider's active-job surfaces when
/// the patient is paying cash at the door, so the provider knows to collect
/// the balance before they mark the visit complete.
class CashOnServiceBadge extends StatelessWidget {
  /// Outstanding balance, when known — naming the figure up front is what
  /// stops the amount being a surprise at the door.
  final double? amountDue;

  const CashOnServiceBadge({super.key, this.amountDue});

  @override
  Widget build(BuildContext context) {
    final amount = amountDue;
    final message = amount != null && amount > 0
        ? 'Cash on service — collect ৳${amount.round()} in cash before you '
            'complete this visit.'
        : 'Cash on service — collect the balance in cash before you '
            'complete this visit.';
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
              message,
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

/// Read-only payment banner for an ONLINE-payment visit — the counterpart
/// to [CashOnServiceBadge]. The provider takes no payment action on these
/// bookings: the patient settles through the gateway and an admin verifies
/// the transaction before the prescription is released.
///
/// Two states, driven by whether the balance has actually landed. Showing
/// "Paid" on a visit whose balance is still open would tell the doctor a
/// settlement happened that hasn't — so an unsettled booking says so
/// plainly instead.
class OnlinePaymentStatusBanner extends StatelessWidget {
  /// Live posture. Null-safe: an unresolved posture falls back to the pending
  /// wording, which is the safer of the two claims.
  final BookingPaymentState? posture;

  const OnlinePaymentStatusBanner({super.key, this.posture});

  @override
  Widget build(BuildContext context) {
    final settled = posture?.isPaid ?? false;
    final message = settled
        ? '💳 Payment Status: Paid via Online Payment '
            '(No Cash Collection Needed)'
        : '💳 Online payment — the patient settles the balance from their '
            'invoice. No cash to collect.';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kOnlineBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kOnlineFg.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.credit_card_rounded, color: _kOnlineFg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
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

// Informational blue for the online-payment banner. Local tokens — MtColors
// has no `info` hue, matching how assign_team_tab declares its ON_SERVICE
// amber locally.
const Color _kOnlineFg = Color(0xFF1D4ED8); // blue-700
const Color _kOnlineBg = Color(0xFFDBEAFE); // blue-100

/// The "Collect Cash" panel — shown right after a provider completes a
/// CASH_ON_SERVICE visit whose balance is unpaid. Green = completion action.
///
/// Single-action by design: the patient committed to cash at booking time,
/// so `Confirm Cash Received` is the only way out. There is no "pay online
/// instead" skip — an online settlement is a different flow entirely
/// (gateway payment + admin verification), not something a provider elects
/// at the door. The sheet is non-dismissible to match.
///
/// It is NOT, however, unconditional. The sheet watches the booking's live
/// payment posture and tears itself down — closing the confirmation dialog
/// too, if one is open — the moment the balance stops being cash-collectable:
/// the patient switched their remaining payment method to Online, paid
/// online, or the other assigned clinician took the cash. Without that guard
/// the provider is left tapping Confirm on a settled booking and reading the
/// server's "Cash cannot be collected" rejection as if they had done
/// something wrong.
class CollectCashSheet extends ConsumerStatefulWidget {
  final String appointmentId;
  final String patientName;
  final double amountDue;

  const CollectCashSheet({
    super.key,
    required this.appointmentId,
    required this.patientName,
    required this.amountDue,
  });

  @override
  ConsumerState<CollectCashSheet> createState() => _CollectCashSheetState();
}

class _CollectCashSheetState extends ConsumerState<CollectCashSheet> {
  bool _busy = false;
  String? _error;

  /// True while the "Confirm cash received?" dialog sits on top of this
  /// sheet — an auto-dismiss has to close that first, or the doctor is left
  /// staring at a confirm button for a booking that no longer exists.
  bool _confirmOpen = false;

  /// Latches the moment a teardown starts, so a burst of socket events (the
  /// posture event plus its follow-up refetch) can't pop the navigator twice.
  bool _dismissing = false;

  String get _amountLabel => '৳${widget.amountDue.round()}';

  /// The booking is no longer awaiting cash — close everything this sheet
  /// opened and tell the provider why, in the same words the console banner
  /// will now be showing.
  void _dismissForSettledBooking(BookingPaymentState posture) {
    if (_dismissing || !mounted) return;
    _dismissing = true;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (_confirmOpen) navigator.pop(false); // the confirmation dialog
    navigator.pop(); // the sheet itself
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: MtColors.brand,
        content: Text(
          posture.isPaid
              ? 'Payment settled online — no cash to collect for this visit.'
              : 'The patient switched to online payment — no cash to collect.',
        ),
      ),
    );
  }

  Future<void> _confirmAndCollect() async {
    if (_busy || _dismissing) return;
    // Last-moment guard: between this sheet opening and the provider tapping,
    // the posture may have flipped. Re-read before asking for confirmation.
    final controller =
        ref.read(bookingPaymentProvider(widget.appointmentId).notifier);
    await controller.refresh();
    if (!mounted) return;
    final fresh = ref.read(bookingPaymentProvider(widget.appointmentId));
    if (fresh != null && !fresh.requiresCashCollection) {
      _dismissForSettledBooking(fresh);
      return;
    }
    HapticFeedback.mediumImpact();
    // Explicit confirmation — this credits company cash onto the
    // provider's own reconciliation ledger and cannot be undone in-app.
    _confirmOpen = true;
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
    _confirmOpen = false;
    // A posture change may have closed the dialog under us while it was open.
    if (sure != true || !mounted || _dismissing) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(dioClientProvider)
          .confirmCashReceived(widget.appointmentId);
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
                ? "Cash confirmed — the patient's prescription is unlocked."
                : 'Cash confirmed — prescription unlocked. You now hold '
                    '৳$holding for Taafi.',
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
    // Defensive check on every build: if the booking is no longer awaiting a
    // cash balance, this sheet must not be tappable. The listener handles the
    // live flip; the `stale` read below covers the case where the posture was
    // already settled by the time this frame was built (a sheet opened from a
    // cached document), rendering a disabled state until the pop lands.
    ref.listen<BookingPaymentState?>(
      bookingPaymentProvider(widget.appointmentId),
      (_, next) {
        if (next == null || _busy) return;
        if (!next.requiresCashCollection) _dismissForSettledBooking(next);
      },
    );
    final posture = ref.watch(bookingPaymentProvider(widget.appointmentId));
    final stale =
        !_busy && posture != null && !posture.requiresCashCollection;

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
                          stale
                              ? 'No cash to collect'
                              : 'Collect Cash · Required',
                          style: MtTextStyles.h3.copyWith(color: MtColors.ink),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          stale
                              ? 'This balance is being settled online — '
                                  'closing…'
                              : 'Patient chose to pay in cash at the door',
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
              // The only action. No skip, no escape hatch — the patient
              // committed to cash and the prescription release depends on
              // this confirmation. Disabled outright once the booking stops
              // being cash-collectable, so the tap can never reach a server
              // that would reject it.
              MtButton(
                label: stale
                    ? 'Settled — nothing to collect'
                    : 'Confirm Cash Received',
                leadingIcon: Icons.check_circle_outline,
                backgroundColor: MtColors.completed,
                isLoading: _busy,
                onPressed: stale ? null : _confirmAndCollect,
              ),
            ],
          ),
        ),
      ),
    );
  }

}
