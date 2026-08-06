import 'package:flutter/foundation.dart';

/// The checkout bill under zero-upfront booking.
///
/// Taafi charges nothing to place a care request. The patient submits for free;
/// Care Management then reviews the case, calls the patient, and commits BOTH
/// the total service fee and the advance deposit that confirms the visit
/// (`PATCH /api/admin/bookings/:id/set-deposit`). Only then does the patient
/// owe anything, and they are prompted for it from Activities.
///
/// So there is exactly one number to show at checkout — [dueNow], which is
/// always ৳0 — and every other line is explicitly *pending*. This class
/// deliberately has no subtotal, service-fee, deposit or VAT arithmetic:
/// showing a computed figure here would quote the patient a price the platform
/// has not set and will not honour.
@immutable
class BookingPriceBreakdown {
  /// Charged at Confirm. Always zero — the constant exists so the action bar
  /// and the bill card read the same number from one place rather than each
  /// hardcoding a literal.
  static const double dueNow = 0;

  const BookingPriceBreakdown._();

  /// Copy for the "Service Fee" line, wherever the bill is shown.
  static const String pendingFeeLabel = 'Pending Admin Review';

  /// Copy for the advance-deposit line. Names *when* the number arrives, so
  /// "pending" doesn't read as "hidden".
  static const String pendingDepositLabel = 'To be set after Admin call';

  /// Copy for the equivalent line on the checkout order summary.
  static const String pendingTotalLabel = 'Pending Care Team Review';

  /// The notice the patient must not be able to miss: nothing is charged
  /// today, and here is what happens instead.
  static const String freeSubmissionNotice =
      'Free Request Submission: Place your request without paying anything '
      'today. Our care team will call you to discuss your medical needs and '
      'set the required advance deposit to confirm your visit.';

  /// The action-bar CTA. Says the two things that matter before the tap: it
  /// places the request, and it is free.
  static const String ctaLabel = 'Confirm & Place Free Request';
}
