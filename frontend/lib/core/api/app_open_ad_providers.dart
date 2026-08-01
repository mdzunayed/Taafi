import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_provider.dart';
import '../models/app_open_ad.dart';
import 'app_open_ad_repository.dart';

final appOpenAdRepositoryProvider = Provider<AppOpenAdRepository>((ref) {
  final client = ref.watch(dioClientProvider);
  return AppOpenAdRepository(client.authedDio);
});

/// The campaign as the admin management panel sees it (active or not).
/// Mutations invalidate this to refresh the panel.
final appOpenAdProvider = FutureProvider<AppOpenAd?>((ref) {
  return ref.watch(appOpenAdRepositoryProvider).fetch();
});

/// Launch-time check the patient shell runs once per app session. Bounded to
/// 3 s so a slow/unreachable backend can never hold the interstitial gate
/// shut — on timeout (or any error) the app proceeds straight to Home.
final launchAdProvider = FutureProvider<AppOpenAd?>((ref) async {
  try {
    return await ref
        .watch(appOpenAdRepositoryProvider)
        .fetch(activeOnly: true)
        .timeout(const Duration(seconds: 3));
  } catch (_) {
    return null;
  }
});

/// Latched once the interstitial has been shown (or skipped because no
/// campaign is active) so tab switches / re-navigations within the same
/// process never replay the ad.
final appOpenAdShownProvider = StateProvider<bool>((_) => false);
