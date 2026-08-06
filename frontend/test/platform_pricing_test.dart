// Pins the admin-configurable booking deposit.
//
// The deposit used to be a compiled-in ৳100 in three separate Dart constants.
// It is now admin-editable, which introduces two failure modes that are worse
// than a wrong number: rendering "৳0" where a price belongs, and silently
// re-pricing a booking the patient is already paying for. Both are asserted
// here.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taafi/core/api/platform_pricing_provider.dart';
import 'package:taafi/core/models/deposit_status.dart';
import 'package:taafi/core/models/platform_pricing.dart';
import 'package:taafi/core/models/snake_case_json.dart';
import 'package:taafi/core/storage/app_prefs.dart';
import 'package:taafi/features/patient/screens/booking_flow_pages.dart';

/// Real notifier, failing network. Only [fetch] is stubbed, so the swallow
/// logic in the production `refresh()` is what actually runs.
class _FailingPricing extends PlatformPricingNotifier {
  @override
  Future<PlatformPricing> fetch() async => throw Exception('network down');
}

Widget _host(Widget child) => ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlatformPricing.fromJson', () {
    test('reads the configured amount', () {
      expect(
        PlatformPricing.fromJson(const {'bookingDepositAmount': 250})
            .bookingDepositAmount,
        250,
      );
    });

    test('a missing or zero amount falls back rather than rendering ৳0', () {
      // "Pay ৳0 Deposit" on the checkout CTA is worse than a stale figure —
      // the server re-resolves the real amount at payment time anyway.
      expect(PlatformPricing.fromJson(const {}).bookingDepositAmount,
          kDefaultBookingDeposit);
      expect(
        PlatformPricing.fromJson(const {'bookingDepositAmount': 0})
            .bookingDepositAmount,
        kDefaultBookingDeposit,
      );
      expect(
        PlatformPricing.fromJson(const {'bookingDepositAmount': null})
            .bookingDepositAmount,
        kDefaultBookingDeposit,
      );
    });
  });

  group('the config provider', () {
    late ProviderContainer container;

    Future<ProviderContainer> build(
      Map<String, Object> prefsSeed, {
      bool failing = true,
    }) async {
      SharedPreferences.setMockInitialValues(prefsSeed);
      final prefs = await SharedPreferences.getInstance();
      return ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          if (failing) platformPricingProvider.overrideWith(_FailingPricing.new),
        ],
      );
    }

    tearDown(() => container.dispose());

    test('seeds synchronously from the disk cache', () async {
      container = await build({'cfg_booking_deposit_amount': 250.0});
      // Synchronous on the very first read — no loading state, because the
      // checkout CTA cannot show a spinner where the price goes.
      expect(container.read(platformPricingProvider).bookingDepositAmount, 250);
    });

    test('falls back to the compiled default on a cold cache', () async {
      container = await build({});
      expect(
        container.read(platformPricingProvider).bookingDepositAmount,
        kDefaultBookingDeposit,
      );
    });

    test('a failed fetch keeps the cached value, not the default', () async {
      // The regression this guards: a network blip resetting a correct ৳250
      // back to the compiled ৳100 and under-charging every new booking.
      container = await build({'cfg_booking_deposit_amount': 250.0});
      await container.read(platformPricingProvider.notifier).refresh();
      expect(container.read(platformPricingProvider).bookingDepositAmount, 250);
    });
  });

  group('an existing booking keeps the amount it was quoted', () {
    test('the wire figure wins over the platform default', () {
      // Admin has since moved the platform fee; this booking was quoted 150
      // and must keep asking for exactly that.
      final r = patientActiveFromMongo({
        '_id': '507f1f77bcf86cd799439011',
        'care_type': 'Post-op wound care',
        'status': 'awaiting_deposit',
        'deposit_status': 'PENDING',
        'deposit_amount': 0,
        'deposit_required_amount': 150,
      });
      expect(r.depositAmount, 0, reason: 'nothing has been paid yet');
      expect(r.depositRequiredAmount, 150);
    });

    test('a paid booking reports what it paid', () {
      final r = patientActiveFromMongo({
        '_id': '507f1f77bcf86cd799439011',
        'care_type': 'Post-op wound care',
        'status': 'deposit_paid_admin_reviewing',
        'deposit_status': 'CONFIRMED',
        'deposit_amount': 100,
        'deposit_required_amount': 100,
      });
      expect(r.depositRequiredAmount, 100);
    });

    test('an old backend omitting the field still yields a real number', () {
      final r = patientActiveFromMongo({
        '_id': '507f1f77bcf86cd799439011',
        'care_type': 'Post-op wound care',
        'status': 'awaiting_deposit',
        'deposit_amount': 0,
      });
      expect(r.depositRequiredAmount, kDefaultBookingDeposit);
    });
  });

  group('the deposit CTA renders the booking\'s own amount', () {
    // The CTA only renders with a non-null `onPay` — a null one means the
    // surrounding surface owns the button.
    testWidgets('pending shows "Pay ৳X Deposit"', (tester) async {
      await tester.pumpWidget(_host(
        DepositPendingNotice(onPay: () {}, amount: 250),
      ));
      expect(find.text('Pay ৳250 Deposit'), findsOneWidget);
    });

    testWidgets('failed shows "Retry ৳X Deposit"', (tester) async {
      await tester.pumpWidget(_host(
        DepositPendingNotice(onPay: () {}, amount: 250, failed: true),
      ));
      expect(find.text('Retry ৳250 Deposit'), findsOneWidget);
    });

    testWidgets('no ৳100 leaks through when the fee is 250', (tester) async {
      await tester.pumpWidget(_host(
        DepositPendingNotice(onPay: () {}, amount: 250),
      ));
      expect(find.textContaining('৳100'), findsNothing);
    });
  });

  group('the timeline renders the same figure in every deposit state', () {
    // The pending/failed branches are the interesting ones: `deposit_amount` is
    // still 0 there, so a widget reading it would print "Deposit ৳0 pending".
    for (final (label, status, paid) in [
      ('paid', 'CONFIRMED', 250),
      ('pending', 'PENDING', 0),
      ('failed', 'FAILED', 0),
    ]) {
      test('$label reads depositRequiredAmount', () {
        final r = patientActiveFromMongo({
          '_id': '507f1f77bcf86cd799439011',
          'care_type': 'Post-op wound care',
          'status': 'awaiting_deposit',
          'deposit_status': status,
          'deposit_amount': paid,
          'deposit_required_amount': 250,
        });
        expect(r.depositRequiredAmount, 250, reason: label);
        expect(r.depositStatus, DepositStatusX.fromWire(status));
      });
    }
  });
}
