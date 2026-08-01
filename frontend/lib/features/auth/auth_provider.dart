import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/dio_client.dart';
import '../../core/api/patient_home_repository.dart';
import '../../core/models/user.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/storage/app_prefs.dart';

final dioClientProvider = Provider<DioClient>((ref) {
  // Hand the provider ref to the client so its request interceptor can read
  // the live auth-state token (see DioClient's onRequest). The read is lazy
  // (at request time), so there's no build-time cycle with authTokenProvider.
  return DioClient(ref);
});

/// Single push-notification service instance for the app. Holds the current
/// FCM device token so registration is deduped across login/refresh. Its
/// [NotificationService.init] is a safe no-op until the Firebase packages +
/// platform config land (see the wiring checklist in NotificationService).
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(ref.read(dioClientProvider)),
);

final authTokenProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<AuthToken?>>((ref) {
  final dioClient = ref.watch(dioClientProvider);
  final notifier = AuthNotifier(dioClient);
  // Session-expiry bridge. The Dio interceptor can't touch this provider
  // (startup dependency cycle — see tokenProvider's doc), so on an
  // unrecoverable 401 it bumps the [sessionExpiredProvider] leaf instead.
  // Flushing the state here is what actually wakes the router redirect and
  // bounces the user to /login; tokens are already cleared by DioClient.
  ref.listen<int>(sessionExpiredProvider, (previous, next) {
    if (previous != null && next != previous) notifier.sessionExpired();
  });
  // Multi-tenant reset. When the JWT clears (logout or unrecoverable
  // session-expiry — DioClient pushes tokenProvider → null in both cases),
  // drop every patient-scoped cache so the next account to sign in on this
  // device can never observe the previous session's Ongoing Care card or
  // notifications. Every account switch in this app passes through a signed-out
  // (token == null) state first, so this covers A → B switches too. The feed /
  // notification controllers also re-scope per-user in their own build(); this
  // is the explicit, guaranteed teardown.
  ref.listen<String?>(tokenProvider, (previous, next) {
    if (next == null && previous != null) {
      ref.invalidate(patientHomeFeedProvider);
      ref.invalidate(patientNotificationsProvider);
    }
  });
  // Push-notification device registration, keyed off the session token so it
  // covers phone/email/Google/OTP login and cold-start hydration uniformly.
  // On sign-in we register this device for high-priority pushes (new-job
  // dispatches for doctors AND nurses); on sign-out we unregister so a
  // handed-off device stops receiving alerts. Both calls are safe no-ops
  // until FCM is enabled — see [notificationServiceProvider].
  ref.listen<String?>(tokenProvider, (previous, next) {
    if (next == previous) return;
    final push = ref.read(notificationServiceProvider);
    if (next != null) {
      push.init();
    } else if (previous != null) {
      push.unregisterToken();
    }
  });
  return notifier;
});

class AuthNotifier extends StateNotifier<AsyncValue<AuthToken?>> {
  final DioClient _dioClient;

  AuthNotifier(this._dioClient) : super(const AsyncValue.data(null)) {
    _loadStoredToken();
  }

  /// Cold-start hydration. Asks [DioClient] for the most recently saved
  /// `{token, refreshToken, user}` and pushes it into state so the
  /// router redirect picks the user's home immediately — no flash of
  /// the /login screen on a returning user.
  Future<void> _loadStoredToken() async {
    try {
      final restored = await _dioClient.restoreSession();
      if (restored != null) state = AsyncValue.data(restored);
    } catch (_) {
      // Failure to read prefs is fatal-er than a login miss: just stay
      // on the signed-out default so the user can sign in manually.
    }
  }

  /// Role-aware sign-in. [identifier] is interpreted as a phone when
  /// it contains no `@`, otherwise an email — the email path keeps
  /// the legacy `/login` screen's seeded admin/doctor demos working.
  /// [role] is mandatory now; the backend rejects role mismatches
  /// with a 403 (see DioClient._handleError for the message it
  /// surfaces).
  Future<void> login(
    String identifier,
    String password, {
    required UserRole role,
  }) async {
    state = const AsyncValue.loading();
    try {
      final isEmail = identifier.contains('@');
      final token = await _dioClient.login(
        phone: isEmail ? null : identifier,
        email: isEmail ? identifier : null,
        password: password,
        role: role,
      );
      state = AsyncValue.data(token);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  /// Promotes a freshly-issued [AuthToken] into the notifier state.
  /// Used by the OTP flow: `DioClient.verifyOtp` already persisted the
  /// session to SharedPreferences, this just wakes up the router
  /// redirect by pushing the token into Riverpod state.
  void hydrate(AuthToken token) {
    state = AsyncValue.data(token);
  }

  /// Google OAuth sign-in. Hands the profile lifted by `google_sign_in`
  /// (email, googleId, fullName, photoUrl) to the backend bridge at
  /// `/auth/google`, which find-or-creates an Account and returns a
  /// JWT. The session is then persisted via DioClient + SharedPreferences
  /// like any other login.
  Future<void> loginWithGoogle({
    required String email,
    required String googleId,
    required String fullName,
    String photoUrl = '',
    UserRole role = UserRole.patient,
  }) async {
    state = const AsyncValue.loading();
    try {
      final token = await _dioClient.loginWithGoogle(
        email: email,
        googleId: googleId,
        fullName: fullName,
        photoUrl: photoUrl,
        role: role,
      );
      state = AsyncValue.data(token);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  /// Submits the new password chosen on `ForcedPasswordResetScreen`.
  /// Mints a fresh session (the server clears the `requires_password_reset`
  /// latch + re-issues a clean token) and pushes it into state so the
  /// router redirect lands the user on their dashboard immediately.
  Future<void> completeForcedPasswordReset(String newPassword) async {
    state = const AsyncValue.loading();
    try {
      final token = await _dioClient.completePasswordReset(
        newPassword: newPassword,
      );
      state = AsyncValue.data(token);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<void> logout() async {
    await _dioClient.clearTokens();
    state = const AsyncValue.data(null);
  }

  /// Invoked (via the [sessionExpiredProvider] listener) when the Dio 401
  /// interceptor declared the session unrecoverable. DioClient has already
  /// cleared the persisted tokens — this only flushes the in-memory auth
  /// state so `currentUserProvider` goes null and the router redirects to
  /// /login.
  void sessionExpired() {
    state = const AsyncValue.data(null);
  }
}

// Helper providers
final currentUserProvider = Provider<User?>(
  (ref) {
    final authToken = ref.watch(authTokenProvider);
    return authToken.maybeWhen(
      data: (token) => token?.user,
      orElse: () => null,
    );
  },
);

final isAuthenticatedProvider = Provider<bool>(
  (ref) {
    final user = ref.watch(currentUserProvider);
    return user != null;
  },
);

final userRoleProvider = Provider<UserRole?>(
  (ref) {
    final user = ref.watch(currentUserProvider);
    return user?.role;
  },
);

/// True only when the signed-in account is admin-provisioned and is
/// still carrying a single-use temporary password. The router
/// redirect detours these sessions into `/forced-password-reset`
/// instead of the role-specific dashboard.
final requiresPasswordResetProvider = Provider<bool>(
  (ref) {
    final authToken = ref.watch(authTokenProvider);
    return authToken.maybeWhen(
      data: (token) {
        if (token == null) return false;
        return token.requiresReset || token.user.requiresPasswordReset;
      },
      orElse: () => false,
    );
  },
);
