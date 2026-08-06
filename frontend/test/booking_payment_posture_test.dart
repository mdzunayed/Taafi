// Pins the rule behind the stale "Collect Cash · Required" bug: a provider
// surface may prompt for cash ONLY while the server still says the balance is
// cash-collectable.
//
// The consoles used to read `payment_preference` off the appointment they
// were launched with. A patient who switched their remaining-balance method
// to Online — or paid it online — changed nothing on the clinician's screen,
// so the doctor tapped Confirm Cash Received and got back "Cash cannot be
// collected — this booking is not awaiting its balance payment".
//
// `BookingPaymentState` is now the single posture both the REST documents and
// the `booking:payment_updated` socket events resolve to, and these tests are
// the contract the consoles, the banner and the cash sheet all inherit.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taafi/core/models/booking_payment_state.dart';
import 'package:taafi/core/models/doctor_dashboard.dart';
import 'package:taafi/core/models/snake_case_json.dart';
import 'package:taafi/features/provider/presentation/collect_cash_panel.dart';

/// A booking document as the provider endpoints return it.
Map<String, dynamic> _booking({
  String status = 'service_completed_awaiting_final_payment',
  String? paymentChannel,
  String? paymentStatus,
  bool? cashCollectionRequired,
  String? paymentPreference,
  String? paymentMethod,
  String? finalPaidAt,
  num? finalPrice = 1200,
  num depositAmount = 100,
  num adjustedDiscount = 0,
  num? remainingBalance,
}) {
  return {
    'id': '507f1f77bcf86cd799439011',
    'status': status,
    'final_price': finalPrice,
    'deposit_amount': depositAmount,
    'adjusted_discount': adjustedDiscount,
    if (remainingBalance != null) 'remaining_balance': remainingBalance,
    if (paymentChannel != null) 'payment_channel': paymentChannel,
    if (paymentStatus != null) 'payment_status': paymentStatus,
    if (cashCollectionRequired != null)
      'cash_collection_required': cashCollectionRequired,
    if (paymentPreference != null) 'payment_preference': paymentPreference,
    if (paymentMethod != null) 'payment_method': paymentMethod,
    if (finalPaidAt != null) 'final_paid_at': finalPaidAt,
  };
}

/// A `booking:payment_updated` payload.
Map<String, dynamic> _event({
  String method = 'ONLINE',
  String status = 'PENDING',
  num? remaining = 1100,
  bool? cashCollectable,
}) {
  return {
    'event': 'BOOKING_PAYMENT_UPDATED',
    'bookingId': '507f1f77bcf86cd799439011',
    'appointmentId': '507f1f77bcf86cd799439011',
    'paymentMethod': method,
    'paymentStatus': status,
    'remainingBalance': remaining,
    if (cashCollectable != null) 'cashCollectable': cashCollectable,
    'bookingStatus': 'service_completed_awaiting_final_payment',
  };
}

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('posture from a booking document', () {
    test('cash on service with an open balance is the collectable case', () {
      final s = BookingPaymentState.fromBookingJson(_booking(
        paymentChannel: 'CASH',
        paymentStatus: 'PENDING',
        cashCollectionRequired: true,
        paymentPreference: 'CASH_ON_SERVICE',
        remainingBalance: 1100,
      ))!;
      expect(s.isCash, isTrue);
      expect(s.isPaid, isFalse);
      expect(s.remainingBalance, 1100);
      expect(s.requiresCashCollection, isTrue);
    });

    test('switched to online mid-visit — balance open, cash NOT collectable',
        () {
      final s = BookingPaymentState.fromBookingJson(_booking(
        paymentChannel: 'ONLINE',
        paymentStatus: 'PENDING',
        cashCollectionRequired: false,
        paymentPreference: 'DIGITAL',
        remainingBalance: 1100,
      ))!;
      expect(s.isOnline, isTrue);
      expect(s.isPaid, isFalse);
      expect(s.requiresCashCollection, isFalse);
    });

    test('paid online after pre-committing to cash — settlement wins', () {
      final s = BookingPaymentState.fromBookingJson(_booking(
        status: 'completed',
        paymentChannel: 'ONLINE',
        paymentStatus: 'PAID',
        cashCollectionRequired: false,
        // The stale pre-commitment is still on the document…
        paymentPreference: 'CASH_ON_SERVICE',
        paymentMethod: 'DIGITAL',
        finalPaidAt: '2026-08-03T10:00:00.000Z',
        remainingBalance: 0,
      ))!;
      expect(s.isOnline, isTrue);
      expect(s.isPaid, isTrue);
      expect(s.remainingBalance, 0);
      expect(s.requiresCashCollection, isFalse);
    });

    test('a document without the server block derives the same answers', () {
      // Legacy / cached payload: no payment_channel, no payment_status, no
      // cash_collection_required. It must still refuse to claim cash is owed
      // once the balance is settled.
      final settled = BookingPaymentState.fromBookingJson(_booking(
        status: 'completed',
        paymentPreference: 'CASH_ON_SERVICE',
        paymentMethod: 'DIGITAL',
        finalPaidAt: '2026-08-03T10:00:00.000Z',
      ))!;
      expect(settled.isPaid, isTrue);
      expect(settled.isOnline, isTrue);
      expect(settled.requiresCashCollection, isFalse);

      final open = BookingPaymentState.fromBookingJson(
        _booking(paymentPreference: 'CASH_ON_SERVICE'),
      )!;
      expect(open.requiresCashCollection, isTrue);
      expect(open.remainingBalance, 1100);

      // Never chose a method → online, per the enum's documented default.
      final unset = BookingPaymentState.fromBookingJson(_booking())!;
      expect(unset.isOnline, isTrue);
      expect(unset.requiresCashCollection, isFalse);
    });

    test('an unpriced booking reports null — not a zero balance', () {
      final s = BookingPaymentState.fromBookingJson(_booking(
        status: 'deposit_paid_admin_reviewing',
        finalPrice: null,
        paymentPreference: 'CASH_ON_SERVICE',
      ))!;
      expect(s.remainingBalance, isNull);
      expect(s.requiresCashCollection, isFalse);
    });

    test('a document with no id is not a posture', () {
      expect(BookingPaymentState.fromBookingJson(const {}), isNull);
      expect(BookingPaymentState.fromBookingJson(null), isNull);
    });
  });

  group('posture from a socket event', () {
    test('the online-switch event drops the cash gate', () {
      final s = BookingPaymentState.fromSocketEvent(
        _event(method: 'ONLINE', status: 'PENDING', cashCollectable: false),
      )!;
      expect(s.bookingId, '507f1f77bcf86cd799439011');
      expect(s.isOnline, isTrue);
      expect(s.requiresCashCollection, isFalse);
    });

    test('the paid-online event reports PAID with nothing outstanding', () {
      final s = BookingPaymentState.fromSocketEvent(
        _event(
          method: 'ONLINE',
          status: 'PAID',
          remaining: 0,
          cashCollectable: false,
        ),
      )!;
      expect(s.isPaid, isTrue);
      expect(s.remainingBalance, 0);
      expect(s.requiresCashCollection, isFalse);
    });

    test('cash still pending keeps the gate open', () {
      final s = BookingPaymentState.fromSocketEvent(
        _event(method: 'CASH', status: 'PENDING', cashCollectable: true),
      )!;
      expect(s.requiresCashCollection, isTrue);
    });

    test('an event routed under appointmentId alone still resolves', () {
      final payload = _event()..remove('bookingId');
      expect(BookingPaymentState.fromSocketEvent(payload)?.bookingId,
          '507f1f77bcf86cd799439011');
    });
  });

  group('dashboard appointment', () {
    test('isCashOnService prefers the server gate over the preference', () {
      // The exact drift that produced the bug: the row still carries
      // CASH_ON_SERVICE, but the server has already ruled out collection.
      final appt = upcomingAppointmentFromMongo({
        'id': '507f1f77bcf86cd799439011',
        'patient_name': 'Rahim',
        'care_type': 'Post-op wound care',
        'status': 'completed',
        'payment_preference': 'CASH_ON_SERVICE',
        'cash_collection_required': false,
      });
      expect(appt.isCashOnService, isFalse);
    });

    test('falls back to the preference when the server omits the gate', () {
      final appt = upcomingAppointmentFromMongo({
        'id': '507f1f77bcf86cd799439011',
        'patient_name': 'Rahim',
        'care_type': 'Post-op wound care',
        'status': 'in_service',
        'payment_preference': 'CASH_ON_SERVICE',
      });
      expect(appt.isCashOnService, isTrue);
      expect(appt, isA<UpcomingAppointment>());
    });
  });

  group('console payment banner', () {
    testWidgets('an unpaid cash visit names the amount to collect',
        (tester) async {
      await tester.pumpWidget(_host(const CashOnServiceBadge(amountDue: 1100)));
      expect(find.textContaining('Cash on service'), findsOneWidget);
      expect(find.textContaining('৳1100'), findsOneWidget);
    });

    testWidgets('a settled online visit says so instead of prompting for cash',
        (tester) async {
      final posture = BookingPaymentState.fromSocketEvent(
        _event(method: 'ONLINE', status: 'PAID', remaining: 0),
      );
      await tester
          .pumpWidget(_host(OnlinePaymentStatusBanner(posture: posture)));
      expect(
        find.textContaining('Paid via Online Payment'),
        findsOneWidget,
      );
      expect(find.textContaining('No Cash Collection Needed'), findsOneWidget);
      // Never the cash prompt's wording.
      expect(find.textContaining('Cash on service'), findsNothing);
      expect(find.textContaining('collect'), findsNothing);
    });

    testWidgets('an unsettled online visit does not claim it was paid',
        (tester) async {
      final posture = BookingPaymentState.fromSocketEvent(_event());
      await tester
          .pumpWidget(_host(OnlinePaymentStatusBanner(posture: posture)));
      expect(find.textContaining('Paid via Online Payment'), findsNothing);
      expect(find.textContaining('No cash to collect'), findsOneWidget);
    });
  });
}
