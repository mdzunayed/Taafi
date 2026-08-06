import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import 'care_request_status.dart';
import 'deposit_status.dart';
import 'patient_active_request.dart';
import 'platform_pricing.dart' show resolveDepositRequired;

/// The canonical states of the four-phase booking lifecycle.
///
/// This is a typed VIEW over the existing `care_requests` document — it does
/// not introduce a second collection or network path. The intermediate
/// provider-dispatch states (assigned/enroute/…) collapse into
/// [BookingStatus.completed]'s "in progress" bucket for the booking surface's
/// purposes; the dedicated Tracking tab owns that detail.
enum BookingStatus {
  /// PHASE 1 — placed free of charge, awaiting the admin's review call.
  /// Nothing is owed and there is nothing for the patient to do.
  requestSubmitted,

  /// PHASE 2 — the admin set the service fee and the deposit. The patient owes
  /// that deposit to confirm the visit.
  depositRequired,

  /// LEGACY pre-payment state from the retired fixed-deposit flow.
  awaitingDeposit,

  /// PHASE 3 — deposit cleared; awaiting verification and team assignment.
  depositPaidAdminReviewing,

  /// LEGACY pay-before-service state — still payable for in-flight docs.
  amountAssignedAwaitingFinalPayment,

  /// Service delivered at home; the outstanding balance is now due.
  serviceCompletedAwaitingFinalPayment,
  completed,
  cancelled,
}

extension BookingStatusX on BookingStatus {
  String toWire() {
    switch (this) {
      case BookingStatus.requestSubmitted:
        return CareRequestStatus.submitted;
      case BookingStatus.depositRequired:
        return CareRequestStatus.depositRequired;
      case BookingStatus.awaitingDeposit:
        return CareRequestStatus.awaitingDeposit;
      case BookingStatus.depositPaidAdminReviewing:
        return CareRequestStatus.depositPaidAdminReviewing;
      case BookingStatus.amountAssignedAwaitingFinalPayment:
        return CareRequestStatus.amountAssignedAwaitingFinalPayment;
      case BookingStatus.serviceCompletedAwaitingFinalPayment:
        return CareRequestStatus.serviceCompletedAwaitingFinalPayment;
      case BookingStatus.completed:
        return CareRequestStatus.completed;
      case BookingStatus.cancelled:
        return CareRequestStatus.cancelled;
    }
  }

  static BookingStatus fromWire(String? raw) {
    switch (raw?.toLowerCase().replaceAll('-', '_')) {
      case CareRequestStatus.submitted:
        return BookingStatus.requestSubmitted;
      case CareRequestStatus.depositRequired:
        return BookingStatus.depositRequired;
      case CareRequestStatus.awaitingDeposit:
        return BookingStatus.awaitingDeposit;
      case CareRequestStatus.depositPaidAdminReviewing:
        return BookingStatus.depositPaidAdminReviewing;
      case CareRequestStatus.amountAssignedAwaitingFinalPayment:
        return BookingStatus.amountAssignedAwaitingFinalPayment;
      case CareRequestStatus.serviceCompletedAwaitingFinalPayment:
        return BookingStatus.serviceCompletedAwaitingFinalPayment;
      case CareRequestStatus.cancelled:
      case CareRequestStatus.rejected:
        return BookingStatus.cancelled;
      // Everything from `approved` onward (the request has cleared the
      // deposit gate and entered/finished the dispatch pipeline).
      default:
        return BookingStatus.completed;
    }
  }

  String get labelEn {
    switch (this) {
      case BookingStatus.requestSubmitted:
        return 'Request placed — awaiting review call';
      case BookingStatus.depositRequired:
        return 'Deposit required to confirm';
      case BookingStatus.awaitingDeposit:
        return 'Confirm your booking';
      case BookingStatus.depositPaidAdminReviewing:
        return 'Under Care Management Review';
      case BookingStatus.amountAssignedAwaitingFinalPayment:
        return 'Pending Balance Payment';
      case BookingStatus.serviceCompletedAwaitingFinalPayment:
        return 'Service completed — payment due';
      case BookingStatus.completed:
        return 'Confirmed';
      case BookingStatus.cancelled:
        return 'Cancelled';
    }
  }

  String get labelBn {
    switch (this) {
      case BookingStatus.requestSubmitted:
        return 'অনুরোধ জমা হয়েছে — কল আসবে';
      case BookingStatus.depositRequired:
        return 'নিশ্চিত করতে অগ্রিম জমা দিন';
      case BookingStatus.awaitingDeposit:
        return 'বুকিং নিশ্চিত করুন';
      case BookingStatus.depositPaidAdminReviewing:
        return 'পর্যালোচনায়';
      case BookingStatus.amountAssignedAwaitingFinalPayment:
        return 'বাকি পরিশোধ বাকি';
      case BookingStatus.serviceCompletedAwaitingFinalPayment:
        return 'সেবা সম্পন্ন — বাকি পরিশোধ করুন';
      case BookingStatus.completed:
        return 'নিশ্চিত';
      case BookingStatus.cancelled:
        return 'বাতিল';
    }
  }

  /// Status-pill foreground colour used by the patient invoice surface
  /// (paired with a 14%-alpha background of the same hue). Tuned for the
  /// midnight `#0D151C` canvas — no light surfaces, no orange.
  Color get pillColor {
    switch (this) {
      case BookingStatus.requestSubmitted:
        return const Color(0xFF60A5FA); // sky — informational, no action due
      case BookingStatus.depositRequired:
        return const Color(0xFFFBBF24); // amber — the patient must act
      case BookingStatus.awaitingDeposit:
        return const Color(0xFFA78BFA); // violetBright
      case BookingStatus.depositPaidAdminReviewing:
        return const Color(0xFF60A5FA); // sky (reviewing)
      case BookingStatus.amountAssignedAwaitingFinalPayment:
        return const Color(0xFFFBBF24); // amber (action needed — not orange)
      case BookingStatus.serviceCompletedAwaitingFinalPayment:
        return const Color(0xFFFBBF24); // amber (action needed — pay balance)
      case BookingStatus.completed:
        return const Color(0xFF34D399); // emerald
      case BookingStatus.cancelled:
        return const Color(0xFFF87171); // rose
    }
  }
}

/// Typed booking-transaction view of a `care_requests` document.
class BookingTransaction extends Equatable {
  final String bookingId;
  final String serviceName;
  final BookingStatus status;

  /// What this booking actually PAID as its slot-confirmation deposit.
  /// 0 until the gateway settles — see [depositRequiredAmount] for the figure
  /// to render before then.
  final double depositAmount;

  /// THE deposit figure to display, in any state: what was paid if paid, what
  /// the admin set if not — and `null` when no deposit has been set at all
  /// (Phase 1). Server-resolved per booking, so an admin retuning the platform
  /// default never re-prices a booking already in flight.
  ///
  /// Null is a real state, not missing data: it means the patient owes ৳0 and
  /// no payment CTA may render.
  final double? depositRequiredAmount;
  final String? depositTransactionId;
  final DateTime? depositPaidAt;

  /// Whether that deposit has actually been settled. The invoice surface
  /// branches on THIS, never on [status] alone: a booking can sit outside
  /// `awaitingDeposit` (legacy row, admin-created, status hand-edited) with
  /// the money never having arrived, and the "deposit confirmed" banner must
  /// not render for it.
  final DepositStatus depositStatus;

  /// Assigned by the admin after the manual phone review.
  final double? finalServiceFee;
  final double? adjustedDiscount;
  final String? adminNotes;

  /// The patient's upfront choice of how they'll settle the balance:
  /// `'CASH_ON_SERVICE'` / `'DIGITAL'` / null. Drives the invoice card's
  /// cash-arranged state.
  final String? paymentPreference;

  /// Whether the balance itself has been settled, by either channel.
  /// [paymentPreference] is an intention; this is the money. The ledger's
  /// "Fully Settled" state branches on this alone, so a patient who
  /// pre-committed to cash and then paid online sees the green banner rather
  /// than a stale "have ৳1,900 ready" instruction.
  final bool balanceSettled;

  /// Phase 4 verification state of the remaining balance:
  /// `PENDING` / `PENDING_ADMIN_VERIFICATION` / `VERIFIED`.
  ///
  /// Distinct from [balanceSettled], which only says the money arrived. An
  /// online payment sits in `PENDING_ADMIN_VERIFICATION` — settled but not yet
  /// reconciled — and the prescription stays locked throughout.
  final String remainingPaymentStatus;

  /// Whether this visit's prescription has been released. Server-held latch:
  /// it flips true only alongside a VERIFIED balance, through the clinician's
  /// cash confirmation or an admin's online verification.
  final bool prescriptionUnlocked;

  /// The gateway transaction reference an admin reconciles an online payment
  /// against before unlocking the prescription. Null for cash bookings, and
  /// for anything that has not been paid yet.
  final String? remainingPaymentReference;

  const BookingTransaction({
    required this.bookingId,
    required this.serviceName,
    required this.status,
    this.depositAmount = 0,
    this.depositRequiredAmount,
    this.depositTransactionId,
    this.depositPaidAt,
    this.depositStatus = DepositStatus.notRequired,
    this.finalServiceFee,
    this.adjustedDiscount,
    this.adminNotes,
    this.paymentPreference,
    this.balanceSettled = false,
    this.remainingPaymentStatus = 'PENDING',
    this.prescriptionUnlocked = false,
    this.remainingPaymentReference,
  });

  /// True once the patient has committed to paying in cash at the door AND
  /// that is still how the balance will arrive. A settled balance overrides
  /// the preference — the money has already been taken.
  bool get isCashChosen =>
      paymentPreference == 'CASH_ON_SERVICE' && !balanceSettled;

  /// The spec's STATE C: the fee is set, the deposit and the balance are both
  /// in, and there is nothing for the clinician to collect at the visit.
  bool get isFullySettled => balanceSettled && hasFinalPrice;

  /// What the patient has paid in total once everything is settled — the
  /// figure the "Fully Settled (৳2,000 Paid)" banner names.
  double get totalPaid => (finalServiceFee ?? 0) - (adjustedDiscount ?? 0);

  /// True once the deposit has actually cleared the gateway. Gates the
  /// green "deposit confirmed — we're reviewing your case" banner.
  bool get isDepositConfirmed => depositStatus.isConfirmed;

  /// True while the patient still owes the deposit — the amber pending card
  /// plus its "Pay ৳X Deposit to Confirm Booking" CTA.
  ///
  /// False through the whole of Phase 1: a booking the care team has not
  /// reviewed yet has no amount to ask for.
  bool get needsDeposit => depositStatus.isOutstanding;

  /// PHASE 1 — the request is placed and free, and the patient is waiting on
  /// the care team's call. Nothing is owed and nothing is actionable.
  bool get isAwaitingReviewCall => depositStatus.isAwaitingReview;

  /// The deposit to name in copy, or 0 when none has been set. Callers that
  /// render a price should gate on [needsDeposit] first — this exists so the
  /// string interpolation has a non-null number once they have.
  double get depositDue => depositRequiredAmount ?? 0;

  /// Outstanding balance = base fee − deposit − discount. Never negative, and
  /// always 0 once the balance has actually been settled.
  double get outstanding {
    if (balanceSettled) return 0;
    final fee = finalServiceFee ?? 0;
    final discount = adjustedDiscount ?? 0;
    final owed = fee - depositAmount - discount;
    return owed < 0 ? 0 : owed;
  }

  bool get hasFinalPrice => (finalServiceFee ?? 0) > 0;

  /// PHASE 4, CHANNEL B — the patient paid online and an admin has not yet
  /// confirmed receipt. Drives the "payment under verification" copy that
  /// explains why a paid-for prescription is still locked.
  bool get isAwaitingPaymentVerification =>
      remainingPaymentStatus == 'PENDING_ADMIN_VERIFICATION';

  /// Build from the patient's active-request view (the primary source, since
  /// the home feed already carries these fields).
  factory BookingTransaction.fromActiveRequest(PatientActiveRequest r) {
    return BookingTransaction(
      bookingId: r.id,
      serviceName: r.serviceTitleEn,
      status: BookingStatusX.fromWire(r.rawStatus),
      depositAmount: r.depositAmount,
      depositRequiredAmount: r.depositRequiredAmount,
      depositStatus: r.depositStatus,
      finalServiceFee: r.finalServiceFee,
      adjustedDiscount: r.adjustedDiscount,
      paymentPreference: r.paymentPreference,
      balanceSettled: r.balanceSettled,
      remainingPaymentStatus: r.remainingPaymentStatus,
      prescriptionUnlocked: r.prescriptionUnlocked,
    );
  }

  /// Build directly from a live snake_case `care_requests` document (e.g. a
  /// payment endpoint's response row).
  factory BookingTransaction.fromMongo(Map<String, dynamic> j) {
    double? money(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      final cleaned = v.toString().replaceAll(RegExp(r'[^0-9.]'), '');
      return cleaned.isEmpty ? null : double.tryParse(cleaned);
    }

    final rawId = j['id'] ?? j['_id'];
    final paidAt = j['deposit_paid_at'] == null
        ? null
        : DateTime.tryParse(j['deposit_paid_at'].toString());
    return BookingTransaction(
      bookingId: rawId?.toString() ?? '',
      serviceName: j['care_type']?.toString() ?? '',
      status: BookingStatusX.fromWire(j['status']?.toString()),
      depositAmount: money(j['deposit_amount']) ?? 0,
      depositRequiredAmount: resolveDepositRequired(
        money(j['deposit_required_amount']),
        money(j['deposit_amount']),
      ),
      depositTransactionId: j['deposit_transaction_id']?.toString(),
      depositPaidAt: paidAt,
      depositStatus: DepositStatusX.fromWire(
        j['deposit_status']?.toString(),
        // Pre-`deposit_status` payload. A paid deposit always stamped one of
        // the two settlement fields; otherwise infer from whether an amount
        // was ever set for this booking — with none set, the honest answer is
        // NOT_REQUIRED, which keeps the payment CTA off a free request.
        fallback: (paidAt != null || (money(j['deposit_amount']) ?? 0) > 0)
            ? DepositStatus.confirmed
            : ((money(j['required_deposit']) ??
                        money(j['deposit_required_amount'])) ??
                    0) >
                    0
                ? DepositStatus.pending
                : DepositStatus.notRequired,
      ),
      // `total_service_fee` is the spec name; `final_price` the storage name
      // the same number arrives under on older payloads.
      finalServiceFee: money(j['total_service_fee']) ?? money(j['final_price']),
      adjustedDiscount: money(j['adjusted_discount']),
      adminNotes: j['admin_note']?.toString(),
      paymentPreference: j['payment_preference']?.toString(),
      // Server-derived posture first, raw settlement stamps as the fallback.
      balanceSettled: j['payment_status']?.toString().toUpperCase() == 'PAID' ||
          j['final_paid_at'] != null ||
          (j['final_transaction_id']?.toString().isNotEmpty ?? false),
      remainingPaymentStatus:
          j['remaining_payment_status']?.toString() ?? 'PENDING',
      prescriptionUnlocked: j['prescription_unlocked'] == true,
      remainingPaymentReference:
          j['remaining_payment_reference']?.toString(),
    );
  }

  @override
  List<Object?> get props => [
        bookingId,
        serviceName,
        status,
        depositAmount,
        depositRequiredAmount,
        depositTransactionId,
        depositPaidAt,
        depositStatus,
        finalServiceFee,
        adjustedDiscount,
        adminNotes,
        paymentPreference,
        balanceSettled,
        remainingPaymentStatus,
        prescriptionUnlocked,
        remainingPaymentReference,
      ];
}
