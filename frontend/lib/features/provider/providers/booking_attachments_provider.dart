import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/booking_attachment.dart';
import '../../auth/auth_provider.dart';

/// Previous medical records (discharge summaries, old prescriptions, lab
/// reports) the patient attached when they booked, for the clinician assigned
/// to the visit.
///
/// Reads `GET /doctor/bookings/:id` — the same assignment-scoped call the
/// payment posture already uses. That endpoint 403s anyone who is not the
/// dispatched doctor or nurse, and it is where the presigned grants inside
/// each [BookingAttachment.fileUrl] are minted, so the fetch IS the access
/// check: there is no separate documents call that could be reached without
/// passing it.
///
/// Grants expire ~30 minutes after the response that carried them. This
/// provider is `autoDispose`, so leaving the console and coming back re-reads
/// and re-mints; what it does NOT do is refresh in place while the console
/// sits open, which is why the viewer's expired-link state names reopening the
/// booking as the fix rather than retrying.
///
/// Failure is deliberately not swallowed here — a 403 (someone else got
/// reassigned to this visit) and "the patient attached nothing" must not
/// render identically, and only the widget layer has the context to say so.
final bookingAttachmentsProvider = FutureProvider.autoDispose
    .family<List<BookingAttachment>, String>((ref, bookingId) async {
  if (bookingId.isEmpty) return const [];
  final json =
      await ref.read(dioClientProvider).getProviderBookingDetails(bookingId);
  return BookingAttachment.listFrom(json['attachments']);
});
