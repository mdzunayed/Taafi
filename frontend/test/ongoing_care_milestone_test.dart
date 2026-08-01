import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taafi/core/models/assigned_provider.dart';
import 'package:taafi/core/models/booking_milestone.dart';
import 'package:taafi/core/models/provider_type.dart';
import 'package:taafi/core/models/patient_active_request.dart';
import 'package:taafi/core/models/patient_request_status.dart';
import 'package:taafi/core/models/snake_case_json.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taafi/features/patient/screens/booking_tracking_screen.dart';
import 'package:taafi/features/patient/screens/widgets/ongoing_care_card.dart';

/// Covers the Foodpanda-style ONGOING CARE tracker:
///   1. The backend's snake_case milestone block parses into the model, and a
///      backend that predates it still yields a correct step.
///   2. The card renders the status badge, step counter, headline, and the
///      admin-assigned appointment time.
///   3. The card lays out without overflow on a small phone.
///   4. Terminal bookings drop the live affordances.
void main() {
  // A realistic `GET /patient/home` active_request payload.
  Map<String, dynamic> payload({
    String status = 'assigned',
    String? milestone = 'SCHEDULED',
    String? scheduledLabel = 'Today, 04:00 PM',
    String? scheduledTime = '2026-08-02T16:00:00.000Z',
    List<dynamic>? timeline,
  }) {
    return {
      '_id': '507f1f77bcf86cd799439011',
      'care_type': 'Post-op wound care',
      'status': status,
      if (milestone != null) ...{
        'milestone': milestone,
        'milestone_step': 3,
        'milestone_total': 6,
        'milestone_label': 'Provider Assigned — Scheduled for Today, 04:00 PM',
        'scheduled_time_label': scheduledLabel,
      },
      'scheduled_time': scheduledTime,
      'assigned_provider_name': 'Dr. Ayesha Rahman',
      'location_text': 'Banani, Dhaka',
      // A backend that predates the tracker ships neither `milestone` nor
      // `milestone_timeline`, so the legacy fixture omits both together.
      if (milestone != null)
        'milestone_timeline': timeline ??
          [
            {
              'key': 'REQUESTED',
              'step': 1,
              'total': 6,
              'state': 'done',
              'label': 'Booking Received — Under Review',
              'timestamp': '2026-08-02T09:00:00.000Z',
              'note': 'Booking received',
            },
            {
              'key': 'CONFIRMED',
              'step': 2,
              'total': 6,
              'state': 'done',
              'label': 'Confirmed — Assigning Provider',
              'timestamp': '2026-08-02T10:00:00.000Z',
            },
            {
              'key': 'SCHEDULED',
              'step': 3,
              'total': 6,
              'state': 'current',
              'label': 'Provider Assigned — Scheduled for Today, 04:00 PM',
              'timestamp': '2026-08-02T11:00:00.000Z',
            },
            {
              'key': 'EN_ROUTE',
              'step': 4,
              'total': 6,
              'state': 'upcoming',
              'label': 'Healthcare Provider On the Way',
            },
            {
              'key': 'IN_SERVICE',
              'step': 5,
              'total': 6,
              'state': 'upcoming',
              'label': 'Care Session in Progress',
            },
            {
              'key': 'COMPLETED',
              'step': 6,
              'total': 6,
              'state': 'upcoming',
              'label': 'Service Complete',
            },
          ],
    };
  }

  Widget harness(PatientActiveRequest request, {Size? size}) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: OngoingCareCard(request: request, onTrackDetails: () {}),
        ),
      ),
    );
  }

  group('milestone parsing', () {
    test('reads the server milestone block', () {
      final r = patientActiveFromMongo(payload());
      expect(r.milestone, BookingMilestone.scheduled);
      expect(r.milestone.step, 3);
      expect(BookingMilestoneX.totalSteps, 6);
      expect(r.scheduledTimeLabel, 'Today, 04:00 PM');
      expect(r.scheduledTime, isNotNull);
      expect(r.assignedProviderName, 'Dr. Ayesha Rahman');
      expect(r.milestoneHeadline, contains('Today, 04:00 PM'));
      expect(r.resolvedTimeline, hasLength(6));
      expect(r.resolvedTimeline[2].isCurrent, isTrue);
      expect(r.resolvedTimeline[0].isDone, isTrue);
      expect(r.resolvedTimeline[5].state, MilestoneStepState.upcoming);
      // A future step must never carry a timestamp.
      expect(r.resolvedTimeline[5].timestamp, isNull);
    });

    test('derives the milestone when the backend predates the tracker', () {
      // No `milestone` / `milestone_timeline` keys at all.
      final r = patientActiveFromMongo(
        payload(status: 'enroute', milestone: null, scheduledLabel: null),
      );
      expect(r.milestone, BookingMilestone.enRoute);
      expect(r.milestone.step, 4);
      // Falls back to a locally-derived six-step timeline rather than blank.
      expect(r.resolvedTimeline, hasLength(6));
      expect(r.resolvedTimeline[3].isCurrent, isTrue);
      expect(r.resolvedTimeline[0].isDone, isTrue);
    });

    test('maps every canonical status onto a milestone', () {
      final cases = <String, BookingMilestone>{
        'awaiting_deposit': BookingMilestone.requested,
        'submitted': BookingMilestone.requested,
        'deposit_paid_admin_reviewing': BookingMilestone.requested,
        'approved': BookingMilestone.confirmed,
        'amount_assigned_awaiting_final_payment': BookingMilestone.confirmed,
        'assigned': BookingMilestone.scheduled,
        'enroute': BookingMilestone.enRoute,
        'arrived': BookingMilestone.enRoute,
        'in_service': BookingMilestone.inService,
        'nurse_completed': BookingMilestone.inService,
        'service_completed_awaiting_final_payment': BookingMilestone.completed,
        'completed': BookingMilestone.completed,
        'cancelled': BookingMilestone.cancelled,
        'rejected': BookingMilestone.cancelled,
      };
      cases.forEach((wire, expected) {
        final r = patientActiveFromMongo(payload(status: wire, milestone: null));
        expect(r.milestone, expected, reason: 'status "$wire"');
      });
    });

    test('keeps the legacy coarse status enum working alongside', () {
      final r = patientActiveFromMongo(payload(status: 'enroute'));
      expect(r.status, PatientRequestStatus.enRoute);
      expect(r.rawStatus, 'enroute');
    });
  });

  group('OngoingCareCard', () {
    testWidgets('renders status, step counter, headline and time pill',
        (tester) async {
      await tester.pumpWidget(harness(patientActiveFromMongo(payload())));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('SCHEDULED'), findsOneWidget);
      expect(find.text('Step 3 of 6'), findsOneWidget);
      expect(
        find.text('Provider Assigned — Scheduled for Today, 04:00 PM'),
        findsOneWidget,
      );
      expect(find.text('Scheduled: Today, 04:00 PM'), findsOneWidget);
      expect(find.text('Dr. Ayesha Rahman'), findsOneWidget);
      expect(find.text('Track Details'), findsOneWidget);
      expect(find.text('WhatsApp'), findsOneWidget);
    });

    testWidgets('Track Details fires the callback', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OngoingCareCard(
              request: patientActiveFromMongo(payload()),
              onTrackDetails: () => tapped++,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Track Details'));
      expect(tapped, 1);
    });

    testWidgets('explains itself when no time has been assigned yet',
        (tester) async {
      final r = patientActiveFromMongo(payload(
        status: 'submitted',
        milestone: 'REQUESTED',
        scheduledLabel: null,
        scheduledTime: null,
      ));
      await tester.pumpWidget(harness(r));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('UNDER REVIEW'), findsOneWidget);
      expect(find.text('Awaiting scheduled time'), findsOneWidget);
    });

    testWidgets('a cancelled booking drops the live step counter',
        (tester) async {
      final r = patientActiveFromMongo(
        payload(status: 'cancelled', milestone: 'CANCELLED'),
      );
      await tester.pumpWidget(harness(r));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('CANCELLED'), findsOneWidget);
      expect(find.textContaining('Step '), findsNothing);
    });

    testWidgets('fits a 320px-wide phone without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness(patientActiveFromMongo(payload())));
      await tester.pump(const Duration(milliseconds: 600));

      expect(tester.takeException(), isNull);
      expect(find.byType(OngoingCareCard), findsOneWidget);
    });
  });
  group('BookingTrackingScreen', () {
    Widget trackingHarness(PatientActiveRequest request) {
      // ProviderScope with no overrides: patientActiveRequestProvider resolves
      // to null (signed-out feed), which is exactly the case where the screen
      // must fall back to the request it was pushed with.
      return ProviderScope(
        child: MaterialApp(
          home: BookingTrackingScreen(initialRequest: request),
        ),
      );
    }

    testWidgets('renders all six steps with their states', (tester) async {
      // Tall viewport: the screen is a lazy ListView, so the care-team block
      // below the timeline is only built once it's inside the viewport.
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(trackingHarness(patientActiveFromMongo(payload())));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('BOOKING TIMELINE'), findsOneWidget);
      // Every milestone label is present in the vertical stepper.
      expect(find.text('Booking Received — Under Review'), findsOneWidget);
      expect(find.text('Confirmed — Assigning Provider'), findsOneWidget);
      expect(find.text('Healthcare Provider On the Way'), findsOneWidget);
      expect(find.text('Care Session in Progress'), findsOneWidget);
      expect(find.text('Service Complete'), findsOneWidget);
      // Completed steps are checked off.
      expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
      // Admin-set note from the timeline survives to the UI.
      expect(find.text('Booking received'), findsOneWidget);
      // Care-team roster (no direct-contact card on this fixture — it carries
      // no `assigned_provider` block) + the support desk fallback.
      expect(find.text('YOUR CARE TEAM'), findsOneWidget);
      expect(find.text('Dr. Ayesha Rahman'), findsOneWidget);
      expect(find.text('TAAFI SUPPORT DESK'), findsOneWidget);
      expect(find.text('Call support'), findsOneWidget);
      expect(find.text('WhatsApp'), findsOneWidget);
      expect(find.textContaining('Booking ID'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the scheduled window, and says so when unset',
        (tester) async {
      await tester.pumpWidget(trackingHarness(patientActiveFromMongo(payload())));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Scheduled appointment'), findsOneWidget);
      expect(find.text('Today, 04:00 PM'), findsOneWidget);

      await tester.pumpWidget(trackingHarness(patientActiveFromMongo(payload(
        status: 'submitted',
        milestone: 'REQUESTED',
        scheduledLabel: null,
        scheduledTime: null,
      ))));
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.text('Your care team will confirm this shortly'),
        findsOneWidget,
      );
    });
  });

  // ==========================================================================
  // Role-aware tracker: who is attending decides the wording of four of the
  // six steps, the provider card's badge/credential line, and the pre-arrival
  // preparation tip.
  // ==========================================================================

  /// Fixture for a dispatched booking, with the wire shape the backend ships
  /// once an admin assigns a provider.
  Map<String, dynamic> dispatched({
    String status = 'enroute',
    String milestone = 'EN_ROUTE',
    String providerType = 'NURSE',
    // Defaults to a snapshot whose role agrees with [providerType] — the
    // backend reconciles the two before it ships them (the dispatched
    // provider's own role is what `resolved_provider_type` reports).
    Map<String, dynamic>? provider,
    bool includeProvider = true,
  }) {
    provider ??= includeProvider
        ? {
            'provider_id': '507f191e810c19729de860ea',
            'provider_type': providerType,
            'name': 'Farhana Akter',
            'phone': '+8801711223344',
            'designation': 'Senior Staff Nurse',
            'registration_no': 'BNMC-4412',
          }
        : null;
    return {
      '_id': '507f1f77bcf86cd799439011',
      'care_type': 'Post-op wound care',
      'status': status,
      'milestone': milestone,
      'resolved_provider_type': providerType,
      'scheduled_time_label': 'Today, 04:00 PM',
      'location_text': 'Banani, Dhaka',
      'assigned_provider': ?provider,
    };
  }

  group('provider role resolution', () {
    test('takes the server-resolved role, not the stored column', () {
      final r = patientActiveFromMongo(dispatched(providerType: 'DOCTOR'));
      expect(r.providerType, ProviderType.doctor);
      expect(r.providerRoleLabel, 'Doctor');
    });

    test('falls back to the populated doctor block on a legacy payload', () {
      final r = patientActiveFromMongo({
        '_id': '1',
        'care_type': 'Home visit',
        'status': 'enroute',
        'doctor': {'id': 'd1', 'full_name': 'Dr. Ayesha Rahman'},
      });
      expect(r.providerType, ProviderType.doctor);
    });

    test('a payload naming nothing lands on the nursing default', () {
      final r = patientActiveFromMongo({
        '_id': '1',
        'care_type': 'Home visit',
        'status': 'submitted',
      });
      expect(r.providerType, ProviderTypeX.fallback);
      expect(r.providerType, ProviderType.nurse);
    });

    test('the local timeline fallback is worded for the role', () {
      // No `milestone_timeline` on the wire: the client derives one, and it
      // must still name the attending role rather than "Provider".
      final r = patientActiveFromMongo(dispatched(providerType: 'DOCTOR'));
      final labels = r.resolvedTimeline.map((e) => e.label).toList();
      expect(labels, contains('Confirmed — Assigning Doctor'));
      expect(labels, contains('Doctor Assigned — Scheduled'));
      expect(labels, contains('Doctor On the Way'));
      expect(labels, contains('Doctor Consultation in Progress'));
      // Steps 1 and 6 are role-neutral.
      expect(labels.first, 'Booking Received — Under Review');
      expect(labels.last, 'Service Complete');
    });

    test('physiotherapy and lab work get their own wording', () {
      expect(
        BookingMilestone.inService.labelFor(ProviderType.physiotherapist),
        'Therapy Session in Progress',
      );
      expect(
        BookingMilestone.enRoute.labelFor(ProviderType.labTech),
        'Lab Technician On the Way',
      );
    });
  });

  group('assigned provider contact', () {
    test('parses the dispatch snapshot', () {
      final p = patientActiveFromMongo(dispatched()).assignedProvider;
      expect(p, isNotNull);
      expect(p!.name, 'Farhana Akter');
      expect(p.isReachable, isTrue);
      expect(p.credentialLine, 'Senior Staff Nurse  •  BNMC #BNMC-4412');
    });

    test('an unnamed or absent block is no provider at all', () {
      expect(
        patientActiveFromMongo(dispatched(includeProvider: false))
            .assignedProvider,
        isNull,
      );
      expect(AssignedProvider.fromJson({'phone': '+880171'}), isNull);
    });

    test('a provider with no phone is not reachable', () {
      final p = patientActiveFromMongo(dispatched(provider: const {
        'name': 'Farhana Akter',
        'provider_type': 'NURSE',
      })).assignedProvider;
      expect(p!.isReachable, isFalse);
      // Nothing invented for the blank credential fields either.
      expect(p.credentialLine, isEmpty);
    });

    testWidgets('the card, its badge and both actions render', (tester) async {
      tester.view.physicalSize = const Size(400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: BookingTrackingScreen(
            initialRequest: patientActiveFromMongo(dispatched()),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('YOUR NURSE'), findsOneWidget);
      expect(find.text('Farhana Akter'), findsOneWidget);
      expect(find.text('Senior Staff Nurse  •  BNMC #BNMC-4412'), findsOneWidget);
      // Twice: the summary card's status chip and the provider card's badge.
      expect(find.text('ON THE WAY'), findsNWidgets(2));
      expect(find.text('Call Nurse'), findsOneWidget);
      // Pre-arrival guidance, role-specific, only in the EN_ROUTE window.
      expect(find.text('Before your Nurse arrives'), findsOneWidget);
      expect(
        find.textContaining('clean, well-lit space'),
        findsOneWidget,
      );
      // The support desk stays available as the separate, secondary channel.
      expect(find.text('TAAFI SUPPORT DESK'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a scheduled booking shows the committed time in the badge',
        (tester) async {
      tester.view.physicalSize = const Size(400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: BookingTrackingScreen(
            initialRequest: patientActiveFromMongo(
              dispatched(status: 'assigned', milestone: 'SCHEDULED'),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('SCHEDULED FOR 04:00 PM'), findsOneWidget);
      // The tip belongs to EN_ROUTE / IN_SERVICE only — too early here.
      expect(find.textContaining('Before your'), findsNothing);
    });

    testWidgets('no contact card before dispatch, and none after completion',
        (tester) async {
      tester.view.physicalSize = const Size(400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      for (final m in const [
        ('submitted', 'REQUESTED'),
        ('completed', 'COMPLETED'),
      ]) {
        await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
            home: BookingTrackingScreen(
              initialRequest: patientActiveFromMongo(
                dispatched(status: m.$1, milestone: m.$2),
              ),
            ),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('Call Nurse'), findsNothing);
        expect(find.text('TAAFI SUPPORT DESK'), findsOneWidget);
      }
    });
  });
}
