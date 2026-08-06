/// Where the booking-confirmation deposit actually stands.
///
/// Server-derived (`care_requests.deposit_status`, projected in
/// `backend/src/models/CareRequest.js`) so the app never has to infer "did the
/// money land?" from an amount or a lifecycle status again — the inference is
/// exactly what let the "deposit confirmed" banner render on bookings that had
/// never been paid for.
enum DepositStatus {
  /// PHASE 1. No deposit has been set for this booking at all: the patient
  /// placed a free request and the care team has not yet run the review call
  /// that produces an amount. Nothing is owed and NO payment CTA may render.
  ///
  /// Distinct from [pending] on purpose. Collapsing the two is what would put
  /// a "Pay ৳100 Deposit" button on a booking nobody has priced — the exact
  /// charge the zero-cost booking flow exists to remove.
  notRequired,

  /// PHASE 2. The admin set an amount and the patient owes it. Shows the
  /// pending card and the "Pay ৳X Deposit to Confirm Booking" CTA.
  pending,

  /// The gateway settled it. This — and only this — unlocks the green
  /// "your deposit is confirmed, we're reviewing your case" banner.
  confirmed,

  /// The last attempt was declined. Still owed, still payable; worth saying
  /// out loud rather than showing the neutral "not paid yet" copy.
  failed,
}

extension DepositStatusX on DepositStatus {
  bool get isConfirmed => this == DepositStatus.confirmed;

  /// True while the patient still has to pay — the states that show the amber
  /// pending card and the "Pay ৳X Deposit" CTA.
  ///
  /// [DepositStatus.notRequired] is deliberately NOT outstanding: there is no
  /// amount to pay, so prompting for one would be asking the patient for money
  /// no admin has asked for.
  bool get isOutstanding =>
      this == DepositStatus.pending || this == DepositStatus.failed;

  /// True while the booking is still waiting on the admin's review call, i.e.
  /// the patient owes nothing and there is nothing for them to do yet.
  bool get isAwaitingReview => this == DepositStatus.notRequired;

  String toWire() {
    switch (this) {
      case DepositStatus.notRequired:
        return 'NOT_REQUIRED';
      case DepositStatus.pending:
        return 'PENDING';
      case DepositStatus.confirmed:
        return 'CONFIRMED';
      case DepositStatus.failed:
        return 'FAILED';
    }
  }

  /// Parses the server value. [fallback] carries the legacy inference (a
  /// non-zero `deposit_amount` / a status past the deposit gate) for payloads
  /// from a backend that predates the field, so an older API still renders a
  /// paid booking as paid.
  static DepositStatus fromWire(
    String? raw, {
    DepositStatus fallback = DepositStatus.pending,
  }) {
    switch (raw?.toUpperCase().trim()) {
      case 'CONFIRMED':
      case 'PAID':
        return DepositStatus.confirmed;
      case 'FAILED':
        return DepositStatus.failed;
      case 'PENDING':
        return DepositStatus.pending;
      case 'NOT_REQUIRED':
      case 'NOT_SET':
        return DepositStatus.notRequired;
      default:
        return fallback;
    }
  }
}
