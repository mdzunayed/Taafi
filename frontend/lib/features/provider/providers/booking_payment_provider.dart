import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/booking_payment_state.dart';
import '../../../core/network/socket_manager.dart';
import '../../auth/auth_provider.dart';

/// Live balance-payment posture for one booking, shared by every provider
/// surface that renders or acts on it: the console's payment banner, the
/// Collect Cash sheet, and the completion flow's decision to offer cash at all.
///
/// Three inputs, one state:
///   • [seed] — the booking document the screen was launched with / just got
///     back from a completion call. Applied only while nothing fresher has
///     arrived, so a socket update is never overwritten by a stale document.
///   • `booking:payment_updated` — the patient switched their remaining
///     payment method, paid online, or a provider settled the cash.
///   • [refresh] — `GET /doctor/bookings/:id`, the authoritative re-read that
///     follows every event (and every resume) so the console converges on the
///     server's answer rather than on an event it may have missed.
///
/// Legacy `payment_preference_updated` and `payment_settled_cash` events are
/// also honoured, as a refetch trigger only — older backends emit those but
/// not the canonical posture event, and a refetch turns either into truth.
class BookingPaymentController extends StateNotifier<BookingPaymentState?> {
  BookingPaymentController(this._ref, this.bookingId) : super(null) {
    final socket = _ref.read(socketManagerProvider);
    if (socket != null) {
      _subs.add(socket.onBookingPaymentUpdated.listen(_onPostureEvent));
      _subs.add(socket.onPaymentPreferenceUpdated.listen(_onLegacyEvent));
      _subs.add(socket.onCashSettled.listen(_onLegacyEvent));
    }
  }

  final Ref _ref;
  final String bookingId;
  final List<StreamSubscription<Map<String, dynamic>>> _subs = [];

  /// True once anything authoritative (a socket event or a refresh) has
  /// landed — after which a seeded document can no longer move the state
  /// backwards.
  bool _live = false;

  bool _isMine(Map<String, dynamic> payload) {
    final id = (payload['bookingId'] ?? payload['appointmentId'] ?? '')
        .toString();
    return id.isNotEmpty && id == bookingId;
  }

  void _onPostureEvent(Map<String, dynamic> payload) {
    if (!mounted || !_isMine(payload)) return;
    final next = BookingPaymentState.fromSocketEvent(payload);
    if (next == null) return;
    _live = true;
    state = next;
    // The event carries everything the UI needs; the re-read is what
    // guarantees we agree with the server even if events were missed or
    // arrived out of order.
    unawaited(refresh());
  }

  void _onLegacyEvent(Map<String, dynamic> payload) {
    if (!mounted || !_isMine(payload)) return;
    unawaited(refresh());
  }

  /// Adopt the payment block of a booking document already in hand. Ignored
  /// once live data has arrived, and ignored for documents belonging to
  /// another booking.
  void seed(Map<String, dynamic>? bookingJson) {
    if (!mounted || _live) return;
    final next = BookingPaymentState.fromBookingJson(bookingJson);
    if (next == null || next.bookingId != bookingId) return;
    state = next;
  }

  /// Re-read the booking from the server — the console's `fetchBookingDetails`.
  /// Best-effort: a failed refresh leaves the last known posture in place
  /// rather than blanking the payment card.
  Future<void> refresh() async {
    if (bookingId.isEmpty) return;
    try {
      final json =
          await _ref.read(dioClientProvider).getProviderBookingDetails(bookingId);
      final next = BookingPaymentState.fromBookingJson(json);
      if (!mounted || next == null) return;
      _live = true;
      state = next;
    } catch (_) {
      // Offline / 403 / transient — keep what we have.
    }
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }
}

/// The live posture for `bookingId`, or null until something has been seeded
/// or fetched. Keyed by booking so two consoles open on different visits never
/// share state.
final bookingPaymentProvider = StateNotifierProvider.autoDispose
    .family<BookingPaymentController, BookingPaymentState?, String>(
  (ref, bookingId) {
    // Keep the shared socket alive for as long as a console is watching.
    ref.watch(socketManagerProvider);
    return BookingPaymentController(ref, bookingId);
  },
);
