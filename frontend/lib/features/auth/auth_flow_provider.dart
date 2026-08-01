import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/dio_client.dart';
import '../../core/models/user.dart';
import 'auth_provider.dart';

/// In-progress signup draft + transient form errors carried across the
/// four auth screens (Welcome Back → Sign Up step 1 → OTP → Success).
///
/// One [Notifier] (vs per-screen controllers) means the OTP screen can
/// read the phone + password entered three screens earlier without
/// prop-drilling through GoRouter `extra` payloads.
class AuthFlowState extends Equatable {
  /// True while a network call (sign-in, register, verify-otp, resend)
  /// is in flight. Wired to the per-screen primary button so it shows a
  /// spinner without freezing the form.
  final bool isLoading;

  /// Last failure to surface in a SnackBar / inline banner. Cleared at
  /// the start of every submit.
  final String? error;

  /// Typed twin of [error], populated only when the failure came from a
  /// sign-in call that produced an [AuthException]. Lets the login screen
  /// branch on `error_code` (bad credentials vs. wrong tab vs. unverified
  /// phone) instead of pattern-matching [error]'s prose. Null for
  /// transport failures and for the non-sign-in calls below.
  final AuthException? authError;

  // --- Sign-up draft (carried between screens) ---
  final String fullName;
  final String phone;
  final String address;

  /// Held in memory only — never persisted — so the OTP screen can
  /// retry register on a re-send without forcing the user to type
  /// their password again. Dropped on [reset].
  final String password;

  /// Role chosen on the Welcome Back picker (sign-in) or hardcoded to
  /// `patient` on sign-up. Defaults to `patient` so the first paint of
  /// the Welcome Back screen has a sensible selection.
  final UserRole role;

  const AuthFlowState({
    this.isLoading = false,
    this.error,
    this.authError,
    this.fullName = '',
    this.phone = '',
    this.address = '',
    this.password = '',
    this.role = UserRole.patient,
  });

  AuthFlowState copyWith({
    bool? isLoading,
    Object? error = _sentinel,
    Object? authError = _sentinel,
    String? fullName,
    String? phone,
    String? address,
    String? password,
    UserRole? role,
  }) {
    return AuthFlowState(
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _sentinel) ? this.error : error as String?,
      authError: identical(authError, _sentinel)
          ? this.authError
          : authError as AuthException?,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      password: password ?? this.password,
      role: role ?? this.role,
    );
  }

  @override
  List<Object?> get props =>
      [isLoading, error, authError, fullName, phone, address, password, role];
}

const _sentinel = Object();

class AuthFlowNotifier extends Notifier<AuthFlowState> {
  @override
  AuthFlowState build() => const AuthFlowState();

  /// Phone-first sign-in. Hands off to [AuthNotifier.login] (which
  /// persists the session via DioClient + SharedPreferences) and
  /// mirrors its async state into this notifier so the screen's button
  /// spinner + SnackBar paths keep working unchanged.
  ///
  /// [identifier] may be a phone OR an email — the email path covers
  /// the legacy `/login` demo creds. The chosen [role] is sent to the
  /// backend so a wrong-role attempt fails with a clean 403.
  Future<bool> signIn({
    required String identifier,
    required String password,
    required UserRole role,
  }) async {
    state = state.copyWith(
        isLoading: true, error: null, authError: null, role: role);
    final auth = ref.read(authTokenProvider.notifier);
    await auth.login(identifier, password, role: role);
    final after = ref.read(authTokenProvider);
    final err = after.whenOrNull(error: (e, _) => e);
    if (err != null) {
      // Keep the flattened string for the screens that only render text,
      // and carry the typed exception alongside it for the login screen.
      state = state.copyWith(
        isLoading: false,
        error: _friendlyError(err),
        authError: err is AuthException ? err : null,
      );
      return false;
    }
    state = state.copyWith(isLoading: false, authError: null);
    return true;
  }

  /// Seeds the draft with just enough to enter the OTP screen from a
  /// *sign-in* attempt that hit `requires_verification` — the user
  /// registered earlier but never confirmed their phone, so there's no
  /// full sign-up draft in memory to reuse.
  ///
  /// Caveat: [requestOtp] only re-sends when [AuthFlowState.fullName] is
  /// populated, which it isn't on this path, so the OTP screen's "Resend"
  /// is a silent no-op here until the backend grows a dedicated
  /// `/auth/resend-otp` endpoint. The code the user was originally sent
  /// still works.
  void prepareVerification({required String phone, String password = ''}) {
    state = state.copyWith(
      phone: phone.trim(),
      password: password,
      error: null,
      authError: null,
    );
  }

  /// Captures Step 1 of the sign-up flow. Email is gone — phone is the
  /// new primary identifier — and address is now collected here.
  void saveStep1({
    required String fullName,
    required String phone,
    required String address,
    required String password,
  }) {
    state = state.copyWith(
      fullName: fullName.trim(),
      phone: phone.trim(),
      address: address.trim(),
      password: password,
      error: null,
      authError: null,
    );
  }

  /// `POST /api/auth/signup` — creates the account (is_verified: false)
  /// without issuing tokens. Returns true so the caller can navigate
  /// to the OTP screen; tokens only show up after [verifyOtp].
  /// Hardcoded to `UserRole.patient` per the product decision that
  /// admins / doctors are admin-created, not self-signed-up.
  Future<bool> register() async {
    if (state.fullName.isEmpty ||
        state.phone.isEmpty ||
        state.password.isEmpty) {
      state = state.copyWith(
          error: 'Complete the sign-up details before registering.');
      return false;
    }
    state = state.copyWith(isLoading: true, error: null, authError: null);
    try {
      await ref.read(dioClientProvider).register(
            fullName: state.fullName,
            phone: state.phone,
            address: state.address,
            password: state.password,
          );
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _friendlyError(e));
      return false;
    }
  }

  /// Resends the OTP. We don't have a dedicated /resend endpoint yet —
  /// re-hitting /signup is safe because the backend special-cases the
  /// "same phone, not yet verified" path and returns 200.
  Future<bool> requestOtp() async {
    if (state.phone.isEmpty) {
      state = state.copyWith(error: 'Enter your phone number first');
      return false;
    }
    state = state.copyWith(isLoading: true, error: null, authError: null);
    try {
      if (state.fullName.isNotEmpty && state.password.isNotEmpty) {
        await ref.read(dioClientProvider).register(
              fullName: state.fullName,
              phone: state.phone,
              address: state.address,
              password: state.password,
            );
      }
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _friendlyError(e));
      return false;
    }
  }

  /// `POST /api/auth/verify-otp` — submits the 6-digit code. On 200
  /// DioClient.verifyOtp has already persisted the session; we just
  /// push the resulting AuthToken into [authTokenProvider] so the
  /// router redirect lands the user on their role-specific home.
  Future<bool> verifyOtp(String code) async {
    if (state.phone.isEmpty) {
      state = state.copyWith(error: 'Phone number is missing from the draft');
      return false;
    }
    state = state.copyWith(isLoading: true, error: null, authError: null);
    try {
      final token = await ref
          .read(dioClientProvider)
          .verifyOtp(phone: state.phone, otp: code);
      ref.read(authTokenProvider.notifier).hydrate(token);
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _friendlyError(e));
      return false;
    }
  }

  /// Wipes any in-progress draft + error. Called from the Success
  /// screen's "Continue" button so the next sign-up starts clean.
  void reset() => state = const AuthFlowState();

  String _friendlyError(Object e) {
    final s = e.toString();
    // DioClient._handleError already produces decent messages — strip
    // the leading "Exception: " when present so the SnackBar reads clean.
    return s.startsWith('Exception: ') ? s.substring(11) : s;
  }
}

final authFlowProvider =
    NotifierProvider<AuthFlowNotifier, AuthFlowState>(AuthFlowNotifier.new);
