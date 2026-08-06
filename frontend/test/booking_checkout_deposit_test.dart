// Pins the deposit-first booking rules.
//
// The whole model rests on two invariants that are easy to break by
// accident: the checkout charges the CONFIGURED deposit and *never* quotes a
// service total, and the deposit is payable online only (cash belongs to the
// remaining balance, chosen later once Care Management sets the fee). A
// regression in either is a billing defect, not a cosmetic one.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taafi/core/api/platform_pricing_provider.dart';
import 'package:taafi/core/models/platform_pricing.dart';
import 'package:taafi/core/models/request_document.dart';
import 'package:taafi/core/storage/app_prefs.dart';
import 'package:taafi/core/models/service_catalog_item.dart';
import 'package:taafi/features/patient/checkout/booking_payment_method.dart';
import 'package:taafi/features/patient/checkout/booking_pricing.dart';
import 'package:taafi/features/patient/new_request/new_request_notifier.dart';
import 'package:taafi/features/patient/new_request/new_request_state.dart';

ServiceCatalogItem _service({
  String id = 'svc-1',
  String title = 'Doctor Home Visit',
  double price = 1000,
}) {
  final now = DateTime(2026, 1, 1);
  return ServiceCatalogItem(
    id: id,
    title: title,
    price: price,
    category: 'Consultation',
    createdAt: now,
    updatedAt: now,
  );
}

const _report = RequestDocument(
  name: 'discharge-summary.pdf',
  url: 'https://cdn.example/taafi/doc-1.pdf',
  mime: 'application/pdf',
  size: 240000,
);

// Deliberately NOT 100: a test that asserts the default proves nothing about
// whether the value is actually plumbed through from config.
const _configuredDeposit = 150.0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // Pin the config rather than letting the notifier reach for the network.
        platformPricingProvider.overrideWith(_FixedPricing.new),
      ],
    );
  });
  tearDown(() => container.dispose());

  NewRequestNotifier notifier() => container.read(newRequestProvider.notifier);
  NewRequestState read() => container.read(newRequestProvider);

  group('deposit-first pricing', () {
    test('checkout charges the admin-configured deposit', () {
      expect(
        container.read(bookingPricingProvider).dueNow,
        _configuredDeposit,
      );
    });

    test('the catalog price never becomes a quoted total', () {
      notifier().selectService(_service(price: 4800));
      // The service costs ৳4,800 in the catalog, but checkout still charges
      // only the deposit — the fee is set after the review call.
      expect(
        container.read(bookingPricingProvider).dueNow,
        _configuredDeposit,
      );
    });

    test('a config change re-prices the checkout without a release', () {
      final notifier = container.read(platformPricingProvider.notifier);
      notifier.state = const PlatformPricing(bookingDepositAmount: 300);
      expect(container.read(bookingPricingProvider).dueNow, 300);
    });

    test('the pending labels are what the bill shows for the fee', () {
      expect(BookingPriceBreakdown.pendingFeeLabel, 'Pending Admin Review');
      expect(
        BookingPriceBreakdown.pendingTotalLabel,
        'Pending Care Team Review',
      );
    });
  });

  group('deposit payment rails', () {
    test('cash is refused for the deposit', () {
      notifier().setPaymentMethod(BookingPaymentMethod.cashOnService);
      expect(read().paymentMethod, isNull);
    });

    test('online rails are accepted', () {
      for (final m in BookingPaymentMethod.values.where((m) => !m.isCash)) {
        notifier().setPaymentMethod(m);
        expect(read().paymentMethod, m, reason: m.name);
      }
    });

    test('deposit rails match the backend DEPOSIT_CHANNELS enum', () {
      final rails = BookingPaymentMethod.values
          .where((m) => !m.isCash)
          .map((m) => m.wireValue)
          .toSet();
      expect(rails, {'BKASH', 'NAGAD', 'ROCKET', 'UPAY', 'CARD'});
    });

    test('cash still maps to the remaining-balance preference', () {
      // The enum keeps cash for the balance choice made later on the invoice.
      expect(BookingPaymentMethod.cashOnService.paymentPreference,
          'CASH_ON_SERVICE');
      expect(BookingPaymentMethod.bkash.paymentPreference, 'DIGITAL');
    });
  });

  group('medical documents', () {
    test('attaching the same file twice keeps one entry', () {
      notifier().addDocument(_report);
      notifier().addDocument(_report);
      expect(read().documents, hasLength(1));
    });

    test('documents can be removed', () {
      notifier().addDocument(_report);
      notifier().removeDocument(_report);
      expect(read().documents, isEmpty);
    });

    test('a size is rendered readably, and an unknown size is blank', () {
      expect(_report.readableSize, '234 KB');
      expect(
        const RequestDocument(name: 'x.pdf', url: 'u').readableSize,
        isEmpty,
      );
    });

    test('the upload response parses without throwing on bad fields', () {
      final doc = RequestDocument.fromJson(const {
        'name': 'lab.png',
        'url': 'https://cdn.example/lab.png',
        'mime': 'image/png',
        'size': 'not-a-number',
      });
      expect(doc.size, 0);
      expect(doc.isPdf, isFalse);
    });
  });

  group('checkout validation', () {
    void completeThroughAddress() {
      notifier().selectService(_service());
      notifier().applyAddress(const RequestAddress(
        line1: 'Flat 4B',
        areaCityZip: 'Banani, Dhaka 1213',
        label: 'Home',
      ));
    }

    test('a booking without a deposit rail cannot be confirmed', () {
      completeThroughAddress();
      expect(notifier().validate(), contains('payment method'));
    });

    test('a scheduled visit needs a future time', () {
      completeThroughAddress();
      notifier().setPaymentMethod(BookingPaymentMethod.bkash);
      notifier().setScheduledAt(DateTime(2020, 1, 1));
      expect(notifier().validate(), contains('future'));
    });

    test('service, address and an online rail clear validation', () {
      completeThroughAddress();
      notifier().setPaymentMethod(BookingPaymentMethod.nagad);
      expect(notifier().validate(), isNull);
    });
  });
}

/// Stand-in for [PlatformPricingNotifier] that never touches Dio or disk.
class _FixedPricing extends PlatformPricingNotifier {
  @override
  PlatformPricing build() =>
      const PlatformPricing(bookingDepositAmount: _configuredDeposit);

  @override
  Future<void> refresh() async {}
}
