import 'package:equatable/equatable.dart';

/// How the outstanding balance is (or will be) settled, normalized to the two
/// values every surface branches on. Mirrors the backend's
/// `utils/paymentPosture.js` channel: the stored `payment_method`
/// (DIGITAL / CASH_TO_PROVIDER) once the balance is settled, the patient's
/// `payment_preference` (DIGITAL / CASH_ON_SERVICE) before that.
enum PaymentChannel { online, cash }

/// Whether the outstanding balance itself has landed.
enum BalancePaymentStatus { pending, paid }

/// The live balance-payment posture of one booking.
///
/// This is the type the provider consoles render their payment card from and
/// gate the Collect Cash sheet on. It has exactly two sources — the booking
/// document a REST call returned, and a `booking:payment_updated` socket
/// event — and both produce the same shape, so a console that seeds from one
/// and updates from the other can never end up in a mixed state.
///
/// The bug this exists for: the consoles used to read `payment_preference`
/// straight off the appointment they were launched with. A patient who
/// switched to Online (or paid online) mid-visit changed nothing on the
/// doctor's screen, leaving a "Collect Cash · Required" sheet whose confirm
/// button the server then rejected with "this booking is not awaiting its
/// balance payment".
class BookingPaymentState extends Equatable {
  final String bookingId;
  final PaymentChannel channel;
  final BalancePaymentStatus status;

  /// What the patient still owes. `null` when the booking has not been priced
  /// yet — deliberately distinct from `0` ("nothing left to pay").
  final double? remainingBalance;

  /// The server's own verdict on whether a provider may collect cash for this
  /// booking (`cash_collection_required` / `cashCollectable`). Authoritative:
  /// it is computed by the same code that guards the collect-cash endpoint,
  /// so honouring it is what keeps the UI and the API from disagreeing.
  final bool cashCollectionRequired;

  /// Live `care_requests.status`, for wording that depends on the visit stage.
  final String bookingStatus;

  const BookingPaymentState({
    required this.bookingId,
    required this.channel,
    required this.status,
    required this.remainingBalance,
    required this.cashCollectionRequired,
    this.bookingStatus = '',
  });

  bool get isPaid => status == BalancePaymentStatus.paid;
  bool get isOnline => channel == PaymentChannel.online;
  bool get isCash => channel == PaymentChannel.cash;

  /// The one gate for the Collect Cash affordance — sheet, button and warning
  /// card alike. Cash channel, unpaid, and money actually left to hand over.
  bool get requiresCashCollection => cashCollectionRequired;

  @override
  List<Object?> get props => [
        bookingId,
        channel,
        status,
        remainingBalance,
        cashCollectionRequired,
        bookingStatus,
      ];

  /// Posture from a booking document — `GET /doctor/bookings/:id`, the
  /// completion responses, `GET /api/appointments/:id`, or a dashboard
  /// `upcoming_today` entry.
  ///
  /// Prefers the server-derived block (`payment_channel`, `payment_status`,
  /// `cash_collection_required`). Falls back to deriving the same answer from
  /// the raw fields for payloads that predate it, so a stale cached document
  /// degrades to the correct value rather than to "collect cash".
  static BookingPaymentState? fromBookingJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final id = (json['id'] ?? json['_id'] ?? json['bookingId'] ?? '').toString();
    if (id.isEmpty) return null;

    final settled = json['final_paid_at'] != null ||
        (json['final_transaction_id']?.toString().isNotEmpty ?? false) ||
        _statusOf(json['payment_status']) == BalancePaymentStatus.paid;

    final channel = _channelOf(json['payment_channel']) ??
        (settled
            // Settled: how it WAS paid.
            ? (json['payment_method']?.toString() == 'CASH_TO_PROVIDER'
                ? PaymentChannel.cash
                : PaymentChannel.online)
            // Open: how the patient said they will pay. Never chosen = online.
            : ((json['payment_preference'] ?? json['remaining_payment_method'])
                        ?.toString() ==
                    'CASH_ON_SERVICE'
                ? PaymentChannel.cash
                : PaymentChannel.online));

    final outstanding = _outstandingOf(json);
    final remaining = settled
        ? 0.0
        : (json.containsKey('remaining_balance')
            ? _money(json['remaining_balance'])
            : outstanding);

    final collectable = json['cash_collection_required'] is bool
        ? json['cash_collection_required'] as bool
        : (!settled &&
            channel == PaymentChannel.cash &&
            (outstanding ?? 0) > 0);

    return BookingPaymentState(
      bookingId: id,
      channel: channel,
      status:
          settled ? BalancePaymentStatus.paid : BalancePaymentStatus.pending,
      remainingBalance: remaining,
      cashCollectionRequired: collectable,
      bookingStatus: (json['status'] ?? '').toString(),
    );
  }

  /// Posture from a `booking:payment_updated` socket payload.
  static BookingPaymentState? fromSocketEvent(Map<String, dynamic>? json) {
    if (json == null) return null;
    final id = (json['bookingId'] ?? json['appointmentId'] ?? '').toString();
    if (id.isEmpty) return null;
    final status = _statusOf(json['paymentStatus']) ?? BalancePaymentStatus.pending;
    final channel = _channelOf(json['paymentMethod']) ?? PaymentChannel.online;
    return BookingPaymentState(
      bookingId: id,
      channel: channel,
      status: status,
      remainingBalance: _money(json['remainingBalance']),
      cashCollectionRequired: json['cashCollectable'] is bool
          ? json['cashCollectable'] as bool
          : (status == BalancePaymentStatus.pending &&
              channel == PaymentChannel.cash &&
              (_money(json['remainingBalance']) ?? 0) > 0),
      bookingStatus: (json['bookingStatus'] ?? '').toString(),
    );
  }

  static double? _money(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  /// Outstanding balance from the raw invoice fields — the client-side twin of
  /// the backend's `outstandingBalanceFor`, used only when a payload predates
  /// the server-derived block. Null when the booking carries no price yet.
  static double? _outstandingOf(Map<String, dynamic> json) {
    final fee = _money(json['final_price']) ?? 0;
    if (fee <= 0) return null;
    final deposit = _money(json['deposit_amount']) ?? 0;
    final discount = _money(json['adjusted_discount']) ?? 0;
    final due = fee - deposit - discount;
    return due > 0 ? due : 0.0;
  }

  static PaymentChannel? _channelOf(dynamic raw) {
    switch (raw?.toString().toUpperCase()) {
      case 'CASH':
      case 'CASH_ON_SERVICE':
      case 'CASH_TO_PROVIDER':
        return PaymentChannel.cash;
      case 'ONLINE':
      case 'DIGITAL':
        return PaymentChannel.online;
      default:
        return null;
    }
  }

  static BalancePaymentStatus? _statusOf(dynamic raw) {
    switch (raw?.toString().toUpperCase()) {
      case 'PAID':
        return BalancePaymentStatus.paid;
      case 'PENDING':
        return BalancePaymentStatus.pending;
      default:
        return null;
    }
  }
}
