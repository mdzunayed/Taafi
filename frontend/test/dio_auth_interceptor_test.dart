// Regression test for the startup CircularDependencyError in the Dio auth
// interceptor.
//
// The bug: `dioClientProvider` builds `DioClient(ref)`, and the request
// interceptor read `authTokenProvider` — but `authTokenProvider` watches
// `dioClientProvider`, so the first request at startup formed the cycle
// `dioClientProvider -> authTokenProvider -> dioClientProvider` and Riverpod
// threw `CircularDependencyError` inside onRequest.
//
// The fix routes the interceptor through the atomic, dependency-free
// `tokenProvider` (which reads only `sharedPreferencesProvider`). This test
// builds the real graph and fires a request through the interceptor — the exact
// crash path — asserting it injects the bearer and does NOT throw a
// circular-dependency error.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taafi/core/storage/app_prefs.dart';
import 'package:taafi/features/auth/auth_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('interceptor injects the bearer with no CircularDependencyError',
      () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'test-jwt-123'});
    final prefs = await SharedPreferences.getInstance();

    // Mirror main(): override sharedPreferencesProvider with a preloaded instance
    // so tokenProvider resolves synchronously.
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    // Build the full auth graph — the exact wiring that used to cycle:
    // authTokenProvider watches dioClientProvider, whose ref the interceptor uses.
    container.read(authTokenProvider);
    final client = container.read(dioClientProvider);

    // Capture the header the auth interceptor attaches, then short-circuit so
    // no real network call happens. Added after the auth interceptor, so it
    // runs second.
    String? captured;
    client.authedDio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options.headers['Authorization'] as String?;
          handler.reject(
            DioException(requestOptions: options, error: '__stop__'),
          );
        },
      ),
    );

    // Firing the request runs the auth interceptor's onRequest, which reads
    // tokenProvider via the dioClient ref. A cycle would surface here as a
    // StateError/CircularDependencyError rather than our sentinel DioException.
    Object? thrown;
    try {
      await client.authedDio.get<dynamic>('http://localhost:1/ping');
    } catch (e) {
      thrown = e;
    }

    expect(
      thrown,
      isA<DioException>(),
      reason: 'onRequest must not throw a circular-dependency error',
    );
    expect((thrown as DioException).error, '__stop__');
    // The token was read synchronously from SharedPreferences and attached.
    expect(captured, 'Bearer test-jwt-123');
  });
}
