import 'package:flutter/material.dart';

/// The payment rails offered on the Checkout step. Every digital rail routes
/// through the same SSLCommerz hosted session (the gateway page surfaces the
/// matching method); [cashOnService] takes no money now beyond the
/// confirmation deposit and pre-commits the patient to paying the balance in
/// cash at the door.
enum BookingPaymentMethod { bkash, nagad, rocket, upay, cashOnService, card }

extension BookingPaymentMethodX on BookingPaymentMethod {
  String get label {
    switch (this) {
      case BookingPaymentMethod.bkash:
        return 'bKash';
      case BookingPaymentMethod.nagad:
        return 'Nagad';
      case BookingPaymentMethod.rocket:
        return 'Rocket';
      case BookingPaymentMethod.upay:
        return 'upay';
      case BookingPaymentMethod.cashOnService:
        return 'Cash on Service';
      case BookingPaymentMethod.card:
        return 'Credit or Debit card';
    }
  }

  String get subtitle {
    switch (this) {
      case BookingPaymentMethod.bkash:
        return 'Pay from your bKash wallet';
      case BookingPaymentMethod.nagad:
        return 'Pay from your Nagad wallet';
      case BookingPaymentMethod.rocket:
        return 'Dutch-Bangla Rocket wallet';
      case BookingPaymentMethod.upay:
        return 'UCB upay wallet';
      case BookingPaymentMethod.cashOnService:
        return 'Hand cash to your clinician after the visit';
      case BookingPaymentMethod.card:
        return 'Visa, Mastercard, AMEX';
    }
  }

  /// Short glyph for the logo tile. The app ships no gateway trademarks in
  /// `assets/`, so each rail gets a tinted monogram tile instead of a logo
  /// bitmap — recognisable, and legally safe to ship.
  String get glyph {
    switch (this) {
      case BookingPaymentMethod.bkash:
        return 'bK';
      case BookingPaymentMethod.nagad:
        return 'N';
      case BookingPaymentMethod.rocket:
        return 'R';
      case BookingPaymentMethod.upay:
        return 'u';
      case BookingPaymentMethod.cashOnService:
        return '৳';
      case BookingPaymentMethod.card:
        return '💳';
    }
  }

  /// Brand tint of the rail. Fixed hexes rather than theme tokens — these are
  /// third-party identities and must read the same in light and dark.
  Color get tint {
    switch (this) {
      case BookingPaymentMethod.bkash:
        return const Color(0xFFE2136E);
      case BookingPaymentMethod.nagad:
        return const Color(0xFFF6821F);
      case BookingPaymentMethod.rocket:
        return const Color(0xFF8B1F8F);
      case BookingPaymentMethod.upay:
        return const Color(0xFFE8B800);
      case BookingPaymentMethod.cashOnService:
        return const Color(0xFF059669);
      case BookingPaymentMethod.card:
        return const Color(0xFF6366F1);
    }
  }

  IconData? get icon {
    switch (this) {
      case BookingPaymentMethod.cashOnService:
        return Icons.payments_rounded;
      case BookingPaymentMethod.card:
        return Icons.credit_card_rounded;
      default:
        return null;
    }
  }

  /// Value persisted on `care_requests.payment_channel`.
  String get wireValue {
    switch (this) {
      case BookingPaymentMethod.bkash:
        return 'BKASH';
      case BookingPaymentMethod.nagad:
        return 'NAGAD';
      case BookingPaymentMethod.rocket:
        return 'ROCKET';
      case BookingPaymentMethod.upay:
        return 'UPAY';
      case BookingPaymentMethod.cashOnService:
        return 'CASH_ON_SERVICE';
      case BookingPaymentMethod.card:
        return 'CARD';
    }
  }

  bool get isCash => this == BookingPaymentMethod.cashOnService;

  /// Collapsed to the two-value `care_requests.payment_preference` enum the
  /// provider console already reads (it decides whether the clinician's
  /// collect-cash step is mandatory at completion).
  String get paymentPreference => isCash ? 'CASH_ON_SERVICE' : 'DIGITAL';
}
