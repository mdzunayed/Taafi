import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/platform_pricing.dart';
import '../storage/app_prefs.dart';
import '../../features/auth/auth_provider.dart' show dioClientProvider;

/// Disk cache key for the last successfully-fetched deposit.
const _kDepositPrefsKey = 'cfg_booking_deposit_amount';

/// The platform's public pricing config, always synchronously readable.
///
/// Deliberately a plain [Notifier] and **not** an `AsyncNotifier`: eight widgets
/// want a `double` to interpolate into a label, and an `AsyncValue` would push a
/// spinner or a blank into every one of them — including the checkout CTA, where
/// a momentarily missing price is worse than a momentarily stale one.
///
/// A stale value here is cosmetic, never a billing defect. The server stamps the
/// authoritative amount onto the booking at creation and validates the gateway
/// payment against *that*, so the worst case is the patient briefly seeing an
/// old figure on a screen they haven't committed from yet.
///
/// Resolution order: last value fetched this session → last value cached on disk
/// → [kDefaultBookingDeposit].
class PlatformPricingNotifier extends Notifier<PlatformPricing> {
  @override
  PlatformPricing build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final cached = prefs.getDouble(_kDepositPrefsKey);
    // Kick off the refresh without blocking the first frame. `microtask` rather
    // than a bare call so `state` is never written during `build`.
    Future.microtask(refresh);
    return cached != null && cached > 0
        ? PlatformPricing(bookingDepositAmount: cached)
        : PlatformPricing.fallback;
  }

  /// The network read, isolated so tests can make it fail without stubbing the
  /// swallow logic in [refresh] — the part that actually needs proving.
  @protected
  @visibleForTesting
  Future<PlatformPricing> fetch() =>
      ref.read(dioClientProvider).getPlatformPricing();

  /// Re-read the config. Silently keeps the last known-good value on failure —
  /// a network blip must not reset a correct ৳250 back to the compiled ৳100.
  Future<void> refresh() async {
    try {
      final fresh = await fetch();
      state = fresh;
      await ref
          .read(sharedPreferencesProvider)
          .setDouble(_kDepositPrefsKey, fresh.bookingDepositAmount);
    } catch (_) {
      // Intentionally swallowed. See the class doc: there is no user-actionable
      // failure here, and the booking flow stays fully usable on the last value.
    }
  }
}

final platformPricingProvider =
    NotifierProvider<PlatformPricingNotifier, PlatformPricing>(
  PlatformPricingNotifier.new,
);
