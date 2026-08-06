/// Canonical wire values for `care_requests.status` as emitted by the
/// MongoDB-backed Node API. Centralizing them here keeps every screen,
/// notifier and DioClient call comparing against the *same* strings —
/// previous bugs (the Doctor's "Visit completed" fallback firing while
/// the status was actually `assigned`) came from ad-hoc string literals
/// drifting away from the backend enum.
///
/// Keep this in lockstep with `VALID_STATUSES` in `backend/src/routes/doctor.js`
/// and the `status` enum in `backend/src/models/CareRequest.js`.
class CareRequestStatus {
  CareRequestStatus._();

  /// LEGACY — booking created but a fixed deposit had not been paid yet.
  /// Retired by the zero-cost flow (new bookings are created [submitted]),
  /// but in-flight rows remain payable from here.
  static const String awaitingDeposit = 'awaiting_deposit';

  /// Phase 2 — the admin ran the review call and committed BOTH the total
  /// service fee and the deposit THIS booking must pay. The patient now owes
  /// that deposit; no provider is dispatched until it clears.
  static const String depositRequired = 'deposit_required';

  /// Phase 3 — the admin-set deposit is confirmed; the booking awaits
  /// deposit verification and team assignment.
  static const String depositPaidAdminReviewing = 'deposit_paid_admin_reviewing';

  /// LEGACY pay-before-service state — the admin set the fee and the
  /// patient had to clear the balance before dispatch. New bookings never
  /// enter this state (pricing is a silent invoice update now), but
  /// in-flight documents remain payable from here.
  static const String amountAssignedAwaitingFinalPayment =
      'amount_assigned_awaiting_final_payment';

  /// Service delivered at the patient's home; the outstanding balance is
  /// now due. Balance settlement completes the booking and hands the
  /// visit's prescriptions to the admin release queue.
  static const String serviceCompletedAwaitingFinalPayment =
      'service_completed_awaiting_final_payment';

  /// Phase 1 — just submitted by the patient, free of charge, awaiting the
  /// admin's review call. This is where every new booking starts.
  static const String submitted = 'submitted';

  /// Admin approved triage but no doctor matched yet.
  static const String approved = 'approved';

  /// Admin matched a doctor; doctor has NOT confirmed yet.
  /// Patient timeline: "Doctor assigned · Waiting for the doctor to confirm".
  static const String assigned = 'assigned';

  /// Doctor confirmed and is travelling. The backend canonical value is
  /// `enroute`; we accept `on_the_way` on the wire as an alias when the
  /// Doctor app advances the state machine, and the route normalises it.
  static const String onTheWay = 'on_the_way';
  static const String enroute = 'enroute';

  /// Doctor has reached the patient's location.
  static const String arrived = 'arrived';

  /// Service in progress.
  static const String inService = 'in_service';

  /// Service finished cleanly.
  static const String completed = 'completed';

  /// Terminal failure states.
  static const String rejected = 'rejected';
  static const String cancelled = 'cancelled';

  /// `enroute` and `on_the_way` mean the same thing to the UI — both
  /// represent "doctor is travelling". This helper hides that detail from
  /// callers so a single comparison covers both.
  static bool isOnTheWay(String s) => s == onTheWay || s == enroute;
}
