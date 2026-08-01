import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The single, synchronously-available [SharedPreferences] instance.
///
/// It is **overridden in `main()`** with an instance loaded via
/// `await SharedPreferences.getInstance()` before `runApp`, so every read below
/// is synchronous from the first frame. The throwing default makes a missing
/// override a loud, obvious failure rather than a silent null-token bug.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main() with a preloaded '
    'SharedPreferences instance.',
  ),
);

/// The active JWT access token, read straight from local device caching.
///
/// This is an **atomic, leaf** data point: it depends only on
/// [sharedPreferencesProvider] and has **zero** dependency on
/// `authTokenProvider`, `currentUserProvider`, `dioClientProvider`, or any
/// repository. That isolation is load-bearing — the Dio request interceptor
/// reads this provider to attach the `Authorization` header, so if it touched
/// the network layer, Riverpod would form
/// `dioClientProvider → tokenProvider → dioClientProvider` and throw a
/// `CircularDependencyError` at startup. As a leaf, it can never point back.
///
/// Seeded synchronously from disk on first read; kept current on login /
/// logout / refresh by pushing `tokenProvider.notifier.state` (see DioClient).
final tokenProvider = StateProvider<String?>(
  (ref) => ref.watch(sharedPreferencesProvider).getString('auth_token'),
);

/// Monotonic bump counter fired by the Dio interceptor when a 401 proves
/// unrecoverable (refresh failed, or the one retry 401'd again). Another
/// atomic leaf for the same reason as [tokenProvider]: DioClient can't read
/// `authTokenProvider` without re-creating the startup dependency cycle, so
/// it bumps this instead and `authTokenProvider` listens (see
/// auth_provider.dart) to flush the session state and let the router bounce
/// to /login.
final sessionExpiredProvider = StateProvider<int>((ref) => 0);
