// Pins the rule behind the "deposit confirmed" bug: the green
// "your ৳100 deposit is confirmed" banner may render ONLY when the server
// says the money actually landed.
//
// The old surface inferred it from the lifecycle status, so any booking that
// reached the review state — including one whose status ran ahead of its
// payment — congratulated the patient for a deposit they had never paid.
// These tests cover the parsing (`deposit_status`, plus the fallback for a
// backend that predates the field) and the two widget states it drives.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taafi/core/models/active_care_step.dart';
import 'package:taafi/core/models/booking_milestone.dart';
import 'package:taafi/core/models/booking_transaction.dart';
import 'package:taafi/core/models/deposit_status.dart';
import 'package:taafi/core/models/patient_active_request.dart';
import 'package:taafi/core/models/snake_case_json.dart';
import 'package:taafi/features/patient/screens/booking_flow_pages.dart';
import 'package:taafi/features/patient/screens/widgets/active_care_timeline_stepper.dart';

/// A `GET /patient/home` active-request row, deposit state parameterised.
Map<String, dynamic> _payload({
  String status = 'deposit_paid_admin_reviewing',
  String? depositStatus = 'CONFIRMED',
  num depositAmount = 100,
  // Server-resolved display figure: what was paid if paid, what was quoted if
  // not. Defaults to the same 100 so the existing expectations hold.
  num depositRequiredAmount = 100,
  String? depositPaidAt = '2026-08-02T09:05:00.000Z',
  // Deposit-first pricing: null until the admin's review call commits a fee.
  num? finalPrice,
  // Balance settlement, for the priced states.
  String? paymentStatus,
  String? finalPaidAt,
  String? paymentPreference,
}) {
  return {
    '_id': '507f1f77bcf86cd799439011',
    'care_type': 'Post-op wound care',
    'status': status,
    'location_text': 'Banani, Dhaka',
    if (depositStatus != null) 'deposit_status': depositStatus,
    'deposit_amount': depositAmount,
    'deposit_required_amount': depositRequiredAmount,
    if (depositPaidAt != null) 'deposit_paid_at': depositPaidAt,
    if (finalPrice != null) 'final_price': finalPrice,
    if (paymentStatus != null) 'payment_status': paymentStatus,
    if (finalPaidAt != null) 'final_paid_at': finalPaidAt,
    if (paymentPreference != null) 'payment_preference': paymentPreference,
  };
}

Widget _host(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  group('deposit_status parsing', () {
    test('CONFIRMED / PENDING / FAILED round-trip off the wire', () {
      expect(
        patientActiveFromMongo(_payload()).depositStatus,
        DepositStatus.confirmed,
      );
      expect(
        patientActiveFromMongo(_payload(
          status: 'awaiting_deposit',
          depositStatus: 'PENDING',
          depositAmount: 0,
          depositPaidAt: null,
        )).depositStatus,
        DepositStatus.pending,
      );
      expect(
        patientActiveFromMongo(_payload(
          status: 'awaiting_deposit',
          depositStatus: 'FAILED',
          depositAmount: 0,
          depositPaidAt: null,
        )).depositStatus,
        DepositStatus.failed,
      );
    });

    test('a status ahead of the money still reports PENDING', () {
      // The exact shape that produced the bug: the booking sits in the review
      // state, but nothing was ever paid.
      final r = patientActiveFromMongo(_payload(
        depositStatus: 'PENDING',
        depositAmount: 0,
        depositPaidAt: null,
      ));
      expect(r.depositStatus, DepositStatus.pending);
      expect(BookingTransaction.fromActiveRequest(r).isDepositConfirmed, isFalse);
      expect(BookingTransaction.fromActiveRequest(r).needsDeposit, isTrue);
    });

    test('a backend without deposit_status falls back to the paid stamp', () {
      expect(
        patientActiveFromMongo(
          _payload(depositStatus: null),
        ).depositStatus,
        DepositStatus.confirmed,
      );
      expect(
        patientActiveFromMongo(_payload(
          status: 'awaiting_deposit',
          depositStatus: null,
          depositAmount: 0,
          depositPaidAt: null,
        )).depositStatus,
        DepositStatus.pending,
      );
    });
  });

  group('invoice surface', () {
    testWidgets('an unpaid deposit shows the pending prompt, not "confirmed"',
        (tester) async {
      final booking = BookingTransaction.fromActiveRequest(
        patientActiveFromMongo(_payload(
          depositStatus: 'PENDING',
          depositAmount: 0,
          depositPaidAt: null,
        )),
      );

      await tester.pumpWidget(_host(DynamicInvoiceCard(booking: booking)));
      await tester.pump();

      expect(find.textContaining('deposit is confirmed'), findsNothing);
      expect(find.text('Deposit Payment Pending'), findsOneWidget);
      expect(find.text('Pay ৳100 Deposit'), findsOneWidget);
    });

    testWidgets('a failed attempt is named and offers a retry', (tester) async {
      final booking = BookingTransaction.fromActiveRequest(
        patientActiveFromMongo(_payload(
          depositStatus: 'FAILED',
          depositAmount: 0,
          depositPaidAt: null,
        )),
      );

      await tester.pumpWidget(_host(DynamicInvoiceCard(booking: booking)));
      await tester.pump();

      expect(find.text('Deposit Payment Failed'), findsOneWidget);
      expect(find.text('Retry ৳100 Deposit'), findsOneWidget);
      expect(find.textContaining('deposit is confirmed'), findsNothing);
    });

    testWidgets('a settled deposit gets the confirmed review banner',
        (tester) async {
      final booking = BookingTransaction.fromActiveRequest(
        patientActiveFromMongo(_payload()),
      );

      await tester.pumpWidget(_host(DynamicInvoiceCard(booking: booking)));
      await tester.pump();

      // STATE A: the badge leads with the settled deposit, and the body
      // promises the pricing call that produces the fee.
      expect(find.textContaining('Deposit Paid · Case Under Review'),
          findsOneWidget);
      expect(find.textContaining('will call you shortly'), findsOneWidget);
      expect(find.text('Deposit Payment Pending'), findsNothing);
    });

    // --- STATE B: the admin has priced the booking ------------------------
    //
    // The ledger is the whole deliverable of the pricing call: three lines
    // that add up, and a choice of how to clear what is left.
    testWidgets('a priced booking shows the three-line ledger and the choice',
        (tester) async {
      final booking = BookingTransaction.fromActiveRequest(
        patientActiveFromMongo(_payload(finalPrice: 2000)),
      );

      await tester.pumpWidget(_host(DynamicInvoiceCard(booking: booking)));
      await tester.pump();

      // Total fee, the credited deposit, and the balance that follows from
      // them — ৳2,000 − ৳100 = ৳1,900.
      expect(find.text('৳2,000'), findsOneWidget);
      expect(find.text('- ৳100'), findsOneWidget);
      expect(find.text('৳1,900'), findsOneWidget);

      // Both settlement routes are offered, and neither is pre-selected.
      expect(find.text('Pay Cash on Service'), findsOneWidget);
      expect(find.text('Pay Balance Online Now'), findsOneWidget);

      // Nothing has been paid, so the settled banner must NOT appear.
      expect(find.textContaining('Fully Settled'), findsNothing);
    });

    testWidgets('choosing online reveals a pay-now action for the balance',
        (tester) async {
      final booking = BookingTransaction.fromActiveRequest(
        patientActiveFromMongo(
          _payload(finalPrice: 2000, paymentPreference: 'DIGITAL'),
        ),
      );

      await tester.pumpWidget(_host(DynamicInvoiceCard(booking: booking)));
      await tester.pump();

      // The point of the online option: the balance is payable immediately,
      // not only after the visit.
      expect(find.text('Pay ৳1,900 Now'), findsOneWidget);
    });

    testWidgets('cash on service offers no pay-now button', (tester) async {
      final booking = BookingTransaction.fromActiveRequest(
        patientActiveFromMongo(
          _payload(finalPrice: 2000, paymentPreference: 'CASH_ON_SERVICE'),
        ),
      );

      await tester.pumpWidget(_host(DynamicInvoiceCard(booking: booking)));
      await tester.pump();

      // Cash settles on the provider's device — there is nothing to tap here.
      expect(find.text('Pay ৳1,900 Now'), findsNothing);
      expect(find.textContaining('have ৳1,900 ready'), findsOneWidget);
    });

    // --- STATE C: the balance landed before the visit ---------------------
    testWidgets('a pre-paid balance collapses the ledger to a settled banner',
        (tester) async {
      final booking = BookingTransaction.fromActiveRequest(
        patientActiveFromMongo(_payload(
          finalPrice: 2000,
          paymentStatus: 'PAID',
          finalPaidAt: '2026-08-03T10:00:00.000Z',
          // Pre-committed to cash, then paid online anyway. The money must
          // win over the stated intention — this is the exact case that used
          // to leave a clinician expecting cash at the door.
          paymentPreference: 'CASH_ON_SERVICE',
        )),
      );

      expect(booking.isFullySettled, isTrue);
      expect(booking.outstanding, 0);
      expect(booking.isCashChosen, isFalse);

      await tester.pumpWidget(_host(DynamicInvoiceCard(booking: booking)));
      await tester.pump();

      expect(find.textContaining('Fully Settled'), findsOneWidget);
      expect(find.textContaining('৳2,000 Paid'), findsOneWidget);
      expect(find.textContaining('No cash collection is needed'), findsOneWidget);
      // No choice survives a settled balance.
      expect(find.text('Pay Cash on Service'), findsNothing);
    });
  });

  group('active care timeline stepper', () {
    Future<void> pumpTimeline(
      WidgetTester tester,
      PatientActiveRequest request,
    ) async {
      await tester
          .pumpWidget(_host(ActiveCareTimelineStepper(request: request)));
      await tester.pump();
    }

    testWidgets('renders the six steps with no map anywhere', (tester) async {
      await pumpTimeline(
        tester,
        patientActiveFromMongo(_payload(status: 'enroute')),
      );

      expect(find.text('Request Submitted'), findsOneWidget);
      expect(find.text('Admin Call & Fee Set'), findsOneWidget);
      expect(find.text('Care Session In Progress'), findsOneWidget);
      expect(find.text('Completed & Settled'), findsOneWidget);
      // Role-aware middle steps — this fixture resolves to a nurse booking.
      expect(find.textContaining('Assigned'), findsOneWidget);
      expect(find.textContaining('En Route'), findsOneWidget);
      // Exactly one step is badged, and it is the one the booking is on.
      expect(find.text('NOW'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the fee step tracks the real deposit state', (tester) async {
      await pumpTimeline(tester, patientActiveFromMongo(_payload()));
      expect(find.textContaining('Deposit ৳100 paid'), findsOneWidget);

      // Same booking, money never landed: the paid claim must not survive.
      await pumpTimeline(
        tester,
        patientActiveFromMongo(_payload(
          status: 'awaiting_deposit',
          depositStatus: 'PENDING',
          depositAmount: 0,
          depositPaidAt: null,
        )),
      );
      expect(find.textContaining('Pay the ৳100 deposit'), findsOneWidget);
      expect(find.textContaining('Deposit ৳100 paid'), findsNothing);
    });

    testWidgets('a step carries its inline action, and only when current',
        (tester) async {
      final request = patientActiveFromMongo(_payload(
        status: 'deposit_required',
        depositStatus: 'PENDING',
        depositAmount: 0,
        depositPaidAt: null,
      ));
      await tester.pumpWidget(_host(ActiveCareTimelineStepper(
        request: request,
        stepActions: const {
          ActiveCareStep.feeSet: Text('PAY-CTA'),
          // Attached to a step the booking has not reached — the stepper must
          // still render it where the caller put it, not reorder or drop it.
          ActiveCareStep.settled: Text('INVOICE'),
        },
      )));
      await tester.pump();

      expect(find.text('PAY-CTA'), findsOneWidget);
      expect(find.text('INVOICE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // The step model is where a wrong answer either hides money the patient
  // owes or claims a visit is booked while it waits on them, so it is pinned
  // separately from the widget that draws it.
  group('active care step resolution', () {
    ActiveCareTimeline timelineFor(Map<String, dynamic> payload) =>
        ActiveCareTimeline(patientActiveFromMongo(payload));

    test('phase 1 sits on Request Submitted — no fee step, no CTA', () {
      final t = timelineFor(_payload(
        status: 'submitted',
        depositStatus: 'NOT_REQUIRED',
        depositAmount: 0,
        depositRequiredAmount: 0,
        depositPaidAt: null,
      ));

      expect(t.currentStep, ActiveCareStep.submitted);
      expect(t.stateOf(ActiveCareStep.feeSet), MilestoneStepState.upcoming);
    });

    test('an outstanding deposit advances to the fee step, whatever the '
        'status says', () {
      // Status ran ahead of the money (admin-advanced row / declined gateway
      // attempt). The deposit is still owed, so the fee step is still current.
      final t = timelineFor(_payload(
        status: 'approved',
        depositStatus: 'PENDING',
        depositAmount: 0,
        depositPaidAt: null,
      ));

      expect(t.currentStep, ActiveCareStep.feeSet);
      expect(
        t.stateOf(ActiveCareStep.teamAssigned),
        MilestoneStepState.upcoming,
      );
    });

    test('a paid deposit hands off to the assignment step', () {
      final t = timelineFor(_payload()); // deposit_paid_admin_reviewing
      expect(t.currentStep, ActiveCareStep.teamAssigned);
      expect(t.stateOf(ActiveCareStep.feeSet), MilestoneStepState.done);
    });

    test('a completed visit with a balance due stays in active care', () {
      final t = timelineFor(_payload(
        status: 'service_completed_awaiting_final_payment',
        finalPrice: 2000,
      ));

      expect(t.currentStep, ActiveCareStep.settled);
      expect(t.stateOf(ActiveCareStep.settled), MilestoneStepState.current);
      expect(t.isSettledClosed, isFalse);
      expect(t.belongsInActiveCare, isTrue);
    });

    test('a completed and settled visit hands off to history', () {
      final t = timelineFor(_payload(
        status: 'completed',
        finalPrice: 2000,
        paymentStatus: 'PAID',
        finalPaidAt: '2026-08-03T10:00:00.000Z',
      ));

      expect(t.isSettledClosed, isTrue);
      expect(t.belongsInActiveCare, isFalse);
      expect(t.stateOf(ActiveCareStep.settled), MilestoneStepState.done);
    });

    test('money paid but not yet reconciled is not settled', () {
      final t = ActiveCareTimeline(
        patientActiveFromMongo(_payload(
          status: 'completed',
          finalPrice: 2000,
          paymentStatus: 'PAID',
          finalPaidAt: '2026-08-03T10:00:00.000Z',
        )).copyWith(remainingPaymentStatus: 'PENDING_ADMIN_VERIFICATION'),
      );

      expect(t.isSettledClosed, isFalse);
      expect(t.stateOf(ActiveCareStep.settled), MilestoneStepState.current);
    });

    test('a cancelled booking keeps the steps it genuinely reached', () {
      final t = timelineFor(_payload(status: 'cancelled'));

      expect(t.isCancelled, isTrue);
      // No step may claim to be happening on a booking that stopped.
      for (final step in ActiveCareStep.values) {
        expect(t.stateOf(step), isNot(MilestoneStepState.current));
      }
      expect(t.stateOf(ActiveCareStep.submitted), MilestoneStepState.done);
    });
  });
}
