import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/user.dart';
import '../../core/utils/slug.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/forced_password_reset_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/auth/screens/otp_verify_screen.dart';
import '../../features/auth/screens/sign_up_step1_screen.dart';
import '../../features/auth/screens/verify_success_screen.dart';
import '../../features/auth/screens/welcome_back_screen.dart';
import '../../features/patient/screens/patient_main_navigation_wrapper.dart';
import '../../features/doctor/presentation/doctor_main_shell.dart';
import '../../features/nurse/presentation/nurse_main_shell.dart';
import '../../features/admin/screens/admin_overview_screen.dart';
import '../../features/auth/auth_provider.dart';

/// Bridges Riverpod auth changes into GoRouter's own refresh channel.
///
/// This exists so [appRouterProvider] can stop *watching* the auth state.
/// It used to, and the cost was severe: every auth transition rebuilt the
/// provider, minting a brand-new [GoRouter] — which swaps the router
/// delegate, rebuilds the navigator from scratch, and disposes the State of
/// whatever screen is on top. A failed sign-in goes
/// `data → loading → error`, so the login screen was torn down and
/// recreated mid-submit: text controllers cleared, and the error banner the
/// screen had just set discarded before it could ever paint.
///
/// With a stable router + `refreshListenable`, an auth change re-runs
/// `redirect` only; screens keep their state.
class _AuthRefreshNotifier extends ChangeNotifier {
  ProviderSubscription<AsyncValue<AuthToken?>>? _sub;

  _AuthRefreshNotifier(Ref ref) {
    // Every derived provider the redirect reads (currentUserProvider,
    // requiresPasswordResetProvider) is computed from authTokenProvider,
    // so this single subscription covers all of them.
    _sub = ref.listen<AsyncValue<AuthToken?>>(
      authTokenProvider,
      (_, _) => notifyListeners(),
    );
  }

  @override
  void dispose() {
    _sub?.close();
    super.dispose();
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);

  /// Current session, read fresh. Everything the redirect needs is derived
  /// from this ONE read rather than from the convenience providers
  /// (`currentUserProvider`, `requiresPasswordResetProvider`).
  ///
  /// That is deliberate: those are derived providers, and at the instant
  /// the refresh listener fires they still hold their previous cached
  /// values. Reading them here produced `auth=true, user=null` on
  /// cold-start restore, so `routeForUser(null)` returned '/login' and a
  /// returning user was stranded on the sign-in screen.
  AuthToken? currentToken() =>
      ref.read(authTokenProvider).maybeWhen(data: (t) => t, orElse: () => null);

  bool resetLatched(AuthToken token) =>
      token.requiresReset || token.user.requiresPasswordReset;

  String initialLocation() {
    final token = currentToken();
    if (token == null) return '/login';
    if (resetLatched(token)) return '/forced-password-reset';
    return routeForUser(token.user);
  }

  return GoRouter(
    initialLocation: initialLocation(),
    refreshListenable: refresh,
    redirect: (context, state) {
      // Read (not watch) — the listenable above is what re-triggers this.
      final token = currentToken();
      final user = token?.user;
      final requiresReset = token != null && resetLatched(token);
      final isAuthenticated = token != null;

      // Routes that are reachable WITHOUT being signed in. The new
      // sign-up / OTP / success screens belong here so an anonymous
      // visitor can complete onboarding before the token exists.
      const publicRoutes = {
        '/login',
        '/legacy-login',
        '/welcome-back',
        '/sign-up',
        '/otp-verify',
        '/verify-success',
        '/forgot-password',
      };

      if (!isAuthenticated && !publicRoutes.contains(state.matchedLocation)) {
        return '/login';
      }

      // Forced-reset gate. An admin-provisioned doctor / nurse signed
      // in with a temporary password must clear the latch before they
      // can reach any other authenticated surface.
      if (isAuthenticated &&
          requiresReset &&
          state.matchedLocation != '/forced-password-reset') {
        return '/forced-password-reset';
      }
      // Conversely, once the latch is cleared the screen is no longer
      // reachable — bounce back to the role-specific home.
      if (isAuthenticated &&
          !requiresReset &&
          state.matchedLocation == '/forced-password-reset') {
        return routeForUser(user);
      }

      if (isAuthenticated && state.matchedLocation == '/login') {
        return routeForUser(user);
      }

      return null;
    },
    routes: [
      // `/login` now renders the new Welcome Back (phone + role-picker
      // + Sign Up button). Every existing redirect / bookmark / sign-out
      // path that points at /login keeps working without code changes.
      GoRoute(
        path: '/login',
        builder: (context, state) => const WelcomeBackScreen(),
      ),
      // Same screen reachable at its canonical path.
      GoRoute(
        path: '/welcome-back',
        builder: (context, state) => const WelcomeBackScreen(),
      ),
      // Legacy email + role-picker demo (seeded admin/doctor creds).
      // Kept for QA / back-office sign-in until phone-based equivalents
      // exist for the admin and doctor demo accounts.
      GoRoute(
        path: '/legacy-login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/sign-up',
        builder: (context, state) => const SignUpStep1Screen(),
      ),
      GoRoute(
        path: '/otp-verify',
        builder: (context, state) => const OtpVerifyScreen(),
      ),
      // Forgot password — single-screen reset that takes phone +
      // 6-digit OTP + new password. `extra` carries the phone the
      // user already typed on Welcome Back so they don't retype it.
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => ForgotPasswordScreen(
          initialPhone: state.extra is String ? state.extra as String : null,
        ),
      ),
      // Authenticated profile settings (doctor + patient). NOT in the
      // public-routes whitelist — anonymous visitors get bounced to
      // /login by the redirect.
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/verify-success',
        builder: (context, state) => const VerifySuccessScreen(),
      ),
      // Forced-reset gate for admin-provisioned doctors / nurses. The
      // redirect above ensures only sessions with the latch set can
      // reach this surface, and that they can't reach anything else.
      GoRoute(
        path: '/forced-password-reset',
        builder: (context, state) => const ForcedPasswordResetScreen(),
      ),
      GoRoute(
        path: '/patient/:name',
        builder: (context, state) => const PatientMainNavigationWrapper(),
      ),
      GoRoute(
        path: '/doctor/:name',
        builder: (context, state) => const DoctorMainShell(),
      ),
      GoRoute(
        path: '/nurse/:name',
        builder: (context, state) => const NurseMainShell(),
      ),
      GoRoute(
        path: '/admin/:name',
        builder: (context, state) => const AdminOverviewScreen(),
      ),
    ],
  );
});

/// Builds the canonical destination route for a signed-in user, e.g.
/// `/patient/rumi-ahmed`. Falls back to `/login` if no user is loaded yet.
String routeForUser(User? user) {
  if (user == null) return '/login';
  final slug = slugify(user.name);
  switch (user.role) {
    case UserRole.doctor:
      return '/doctor/$slug';
    case UserRole.nurse:
      return '/nurse/$slug';
    case UserRole.admin:
      return '/admin/$slug';
    case UserRole.patient:
      return '/patient/$slug';
  }
}
