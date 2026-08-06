import 'package:equatable/equatable.dart';

/// Compiled-in fallback for the platform's SUGGESTED booking deposit.
///
/// **Not** the source of truth — that is `Settings.booking_deposit_amount` on
/// the backend, read through `GET /api/config/pricing`. This value is what the
/// app shows on a very first cold start with no network and no cached config.
///
/// Under the four-phase flow this charges nobody. It is the amount the admin
/// console PREFILLS the set-deposit field with; the number a patient actually
/// owes is set per booking on the review call and always arrives on the row
/// itself. Never render this on a patient-facing surface.
const double kDefaultBookingDeposit = 100;

/// Public platform pricing, from `GET /api/config/pricing`.
///
/// Only [bookingDepositAmount] for now — the default the admin console starts
/// its deposit field at. It is the wrong number for any booking that already
/// exists: those carry their own `requiredDeposit` off the wire, because the
/// deposit is a per-case decision and an admin retuning the platform default
/// must never re-price a booking already in flight.
class PlatformPricing extends Equatable {
  /// The admin console's default deposit suggestion for a new booking.
  final double bookingDepositAmount;

  const PlatformPricing({this.bookingDepositAmount = kDefaultBookingDeposit});

  /// What the app renders before the first successful config fetch.
  static const fallback = PlatformPricing();

  factory PlatformPricing.fromJson(Map<String, dynamic> json) {
    final raw = (json['bookingDepositAmount'] as num?)?.toDouble();
    // A missing or nonsensical value falls back rather than rendering "৳0" on
    // the checkout CTA — the server is authoritative at payment time either way.
    return PlatformPricing(
      bookingDepositAmount:
          (raw != null && raw > 0) ? raw : kDefaultBookingDeposit,
    );
  }

  @override
  List<Object?> get props => [bookingDepositAmount];
}

/// Parse a booking's deposit from a wire payload, or `null` when no deposit has
/// been set for it yet.
///
/// Prefers the server-resolved `deposit_required_amount` / `required_deposit`,
/// which already applies the paid → admin-set → quoted precedence. Falls back to
/// what the booking actually paid, so a NEW client replaying an OLD cached
/// payload still renders a real number.
///
/// **Returns null rather than the platform default.** Under the four-phase flow
/// a booking genuinely can owe nothing — that is all of Phase 1 — and
/// substituting a default here would put a "Pay ৳100" prompt on a free request.
/// Callers must handle null as "no deposit set yet", not as ৳0 owed.
///
/// Shared by [PatientActiveRequest], [BookingTransaction] and the snake_case
/// mapper so all three agree on the fallback chain.
double? resolveDepositRequired(dynamic required, dynamic paid) {
  final r = (required as num?)?.toDouble();
  if (r != null && r > 0) return r;
  final p = (paid as num?)?.toDouble();
  if (p != null && p > 0) return p;
  return null;
}
