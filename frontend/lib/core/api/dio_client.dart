import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../storage/app_prefs.dart';
import '../models/admin_chart_data.dart';
import '../models/admin_models.dart';
import '../models/admin_patient_detail.dart';
import '../models/admin_settings.dart';
import '../models/appointment.dart';
import '../models/service.dart';
import '../models/doctor_dashboard.dart';
import '../models/doctor_patient.dart';
import '../models/doctor_profile.dart';
import '../models/doctor_profile_status.dart';
import '../models/doctor_review.dart';
import '../models/doctor_stats.dart';
import '../models/patient_history_item.dart';
import '../models/nurse_profile.dart';
import '../models/provider_earnings.dart';
import '../models/provider_wallet.dart';
import '../models/saved_address.dart';
import '../models/dependent.dart';
import '../models/patient_medical_vault.dart';
import '../models/patient_profile.dart';
import '../models/snake_case_json.dart';
import '../models/patient_active_request.dart';
import '../models/patient_home_feed.dart';
import '../models/patient_notification.dart';
import '../models/patient_request_status.dart';
import '../models/recent_provider.dart';
import '../models/admin_provision_result.dart';
import '../models/prescription.dart';
import '../models/provider_cash_ledger.dart';
import '../models/provider_update_otp_dispatch.dart';
import '../models/user.dart';

/// Typed sign-in failure. Carries the backend's `error_code` and the HTTP
/// status alongside the human message so the login screen can branch on
/// structured data instead of pattern-matching the prose — the old approach
/// mistranslated any message containing the word "password" into a
/// credentials error.
///
/// Codes are minted by `POST /api/auth/login` (see backend/src/routes/auth.js):
/// `bad_request`, `invalid_credentials`, `role_mismatch`, `account_inactive`,
/// `requires_verification`.
class AuthException implements Exception {
  /// Server-authored, user-facing copy. Shown verbatim — the client no
  /// longer rewrites it.
  final String message;
  final int? statusCode;
  final String? errorCode;

  /// Canonical (server-normalised) phone, populated only on
  /// `requires_verification` so the caller can jump into the OTP screen
  /// with the number the backend actually stored.
  final String? phone;

  const AuthException(
    this.message, {
    this.statusCode,
    this.errorCode,
    this.phone,
  });

  /// Wrong phone or wrong password. The status fallback covers a backend
  /// that predates `error_code`.
  bool get isCredentialFailure =>
      errorCode == 'invalid_credentials' ||
      (errorCode == null && statusCode == 401);

  /// Right credentials, wrong login tab.
  bool get isRoleMismatch => errorCode == 'role_mismatch';

  /// Patient signed up but never completed OTP.
  bool get requiresVerification => errorCode == 'requires_verification';

  /// Message-only so call sites still doing `e.toString()` (the auth flow
  /// notifier's `_friendlyError`, the legacy LoginScreen) keep reading clean.
  @override
  String toString() => message;
}

class DioClient {
  // Live backend base URL. Defaults to the deployed Render host so a plain
  // `flutter run` / release build talks to production with no flags. Override
  // per environment without code edits:
  //   deployed (default): https://taafi-backend.onrender.com
  //   local web/desktop:  --dart-define=API_BASE_URL=http://localhost:5000
  //   Android emulator:   --dart-define=API_BASE_URL=http://10.0.2.2:5000
  // NOTE: origin only — no `/api` suffix. The backend mounts some routers at
  // the root (`/patient`, `/doctor`, `/admin`, `/provider`) and others under
  // `/api/*`, and call sites below already spell out the full path.
  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://taafi-backend.onrender.com',
  );

  /// Public read-only view of [_baseUrl], for consumers that need the API
  /// origin without going through Dio — chiefly `resolveImageUrl()` in
  /// core/utils/image_url.dart, which absolutizes relative `/uploads/...`
  /// paths. Origin only, no `/api` suffix.
  static const String baseUrl = _baseUrl;
  static const String _tokenKey = 'auth_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _userKey = 'auth_user';
  static const String _availabilityKey = 'doctor_availability';

  // LIVE backend is the default. Every read/write hits the real
  // MongoDB-backed API (`GET /admin/requests`, `GET /doctor/dashboard`,
  // `POST /patient/requests`, …). The hardcoded mock seed arrays further
  // down (MT-4827, MT-4830, …) are NEVER rendered in a normal run — they
  // are strictly an opt-in offline-demo fallback, reachable ONLY with:
  //
  //   flutter run --dart-define=USE_MOCK=true
  //
  // Default `false` means a plain `flutter run` shows live data — no dummy
  // rows, no per-launch flag ritual. Requires the backend at
  // [_baseUrl] (default http://localhost:5000) + MongoDB to be running.
  static const bool _useMockMode = bool.fromEnvironment(
    'USE_MOCK',
    defaultValue: false,
  );

  late final Dio _dio;
  SharedPreferences? _prefs;

  // Provider ref, so the request interceptor can read the atomic [tokenProvider]
  // and the write methods can push the live token into it. Nullable to keep
  // non-Riverpod construction (tests / tooling) compiling.
  final Ref? _ref;

  DioClient([this._ref]) {
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        contentType: 'application/json',
      ),
    );

    // Unified auth injection — the single place every outgoing request gets
    // its bearer. The token is read SYNCHRONOUSLY, on-demand, from the atomic
    // [tokenProvider] (a graph leaf that reads SharedPreferences and depends on
    // nothing else), NOT from the auth-state notifier. Reading `authTokenProvider`
    // here created a `dioClientProvider → authTokenProvider → dioClientProvider`
    // cycle that threw `CircularDependencyError` at startup; `tokenProvider` can
    // never point back. SharedPreferences is preloaded in main(), so the token
    // is available on the very first request — no async gap, no cold-start race.
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _ref?.read(tokenProvider);
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (error, handler) async {
          // Refresh-and-retry applies ONLY to expired sessions on protected
          // endpoints. A 401 from the auth surface itself (/auth/login,
          // /auth/verify-otp, …) means BAD CREDENTIALS — refreshing and
          // retrying there swallowed the failure entirely: the stub
          // /auth/refresh "succeeded", the retry was re-issued as a GET
          // (method was dropped), and the resulting throw inside this
          // callback left the handler unresolved — the login Future never
          // completed and the UI froze silently. Let auth 401s propagate so
          // _handleError can surface the backend's message.
          final status = error.response?.statusCode;
          final isAuthEndpoint =
              error.requestOptions.path.contains('/auth/');
          final alreadyRetried =
              error.requestOptions.extra['authRetried'] == true;
          if (status == 401 && !isAuthEndpoint && !alreadyRetried) {
            final refreshed = await _refreshToken();
            if (refreshed) {
              try {
                // fetch() re-runs the full pipeline (method + headers
                // preserved; onRequest injects the fresh bearer). The
                // extra flag caps this at one retry per request.
                error.requestOptions.extra['authRetried'] = true;
                return handler.resolve(
                  await _dio.fetch(error.requestOptions),
                );
              } on DioException catch (retryError) {
                // Retry failed too — reject with the newer error so the
                // caller's Future always completes. (If the retry itself
                // 401'd, its own pass through this interceptor — with
                // authRetried already set — flushed the session.)
                return handler.next(retryError);
              }
            }
            // Refresh failed: the session is unrecoverable. Flush it so
            // the router bounces to /login instead of leaving the app
            // "signed in" while every protected request keeps 401ing.
            await _flushExpiredSession();
          } else if (status == 401 && !isAuthEndpoint && alreadyRetried) {
            // Second 401 on the already-retried request — unrecoverable.
            await _flushExpiredSession();
          }
          return handler.next(error);
        },
      ),
    );
  }

  /// The configured, authenticated [Dio] instance (JWT injection + 401
  /// refresh-and-retry interceptor). Exposed so repositories that own their
  /// own request/caching logic — e.g. the promo-banner repository — can reuse
  /// the auth pipeline instead of building a second, token-less client.
  Dio get authedDio => _dio;

  /// `GET /api/prescriptions/:id/download` — streams the server-rendered
  /// A4 prescription PDF straight to [savePath]. Bearer injection and the
  /// 401 refresh-retry ride the existing interceptor pipeline; Dio writes
  /// to a temp file and renames on success, so an aborted download never
  /// leaves a corrupt file at [savePath]. The receive timeout is raised
  /// because a cold Chromium launch server-side can push past the default
  /// 30s budget.
  Future<void> downloadPrescriptionPdf(
    String prescriptionId,
    String savePath, {
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      await _dio.download(
        '/api/prescriptions/$prescriptionId/download',
        savePath,
        onReceiveProgress: onProgress,
        options: Options(receiveTimeout: const Duration(minutes: 2)),
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> _ensurePrefsInitialized() async {
    // Same cached instance held by [sharedPreferencesProvider] (preloaded in
    // main()); used here for the refresh-token + user keys DioClient owns.
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> init() async {
    await _ensurePrefsInitialized();
  }

  Future<void> saveTokens(String token, String refreshToken) async {
    await _ensurePrefsInitialized();
    await _prefs?.setString(_tokenKey, token);
    await _prefs?.setString(_refreshTokenKey, refreshToken);
    // Push the live token so the interceptor's [tokenProvider] read reflects a
    // fresh login on the very next request (persisted above for cold starts).
    _ref?.read(tokenProvider.notifier).state = token;
  }

  /// Persists the freshly-signed-in [User] alongside the token so a cold
  /// start can rehydrate the session without a follow-up `GET /me`.
  Future<void> _saveUser(User user) async {
    await _ensurePrefsInitialized();
    await _prefs?.setString(_userKey, jsonEncode(user.toJson()));
  }

  /// Cold-start hydration. Reads any token + user previously written by
  /// [_saveUser] / [saveTokens] and returns a stitched [AuthToken] so the
  /// AuthNotifier can skip the login screen entirely on a returning user.
  /// Returns `null` when there's nothing on disk (first launch / signed out).
  Future<AuthToken?> restoreSession() async {
    await _ensurePrefsInitialized();
    final token = _prefs?.getString(_tokenKey);
    final refresh = _prefs?.getString(_refreshTokenKey);
    final userRaw = _prefs?.getString(_userKey);
    if (token == null || token.isEmpty || userRaw == null || userRaw.isEmpty) {
      return null;
    }
    try {
      final user = User.fromJson(jsonDecode(userRaw) as Map<String, dynamic>);
      // [tokenProvider] already initialised from the same `auth_token` key at
      // boot, so the interceptor is already carrying this token — nothing to
      // push here.
      return AuthToken(
        token: token,
        refreshToken: refresh ?? '',
        user: user,
      );
    } catch (e) {
      // Disk write from an older app version with an incompatible shape
      // — drop it rather than crashing the boot.
      assert(() {
        debugPrint('[auth] dropped corrupt stored session: $e');
        return true;
      }());
      await clearTokens();
      return null;
    }
  }

  Future<bool> _refreshToken() async {
    try {
      await _ensurePrefsInitialized();
      final refreshToken = _prefs?.getString(_refreshTokenKey);
      if (refreshToken == null) return false;

      final response = await _dio.post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );

      if (response.statusCode == 200) {
        final newToken = response.data['token'];
        await _prefs?.setString(_tokenKey, newToken);
        // Persist the rotated refresh token too — the backend re-issues
        // one on every refresh, and holding on to the old (consumed) one
        // would strand the session at the next expiry.
        final newRefresh = response.data['refreshToken'];
        if (newRefresh is String && newRefresh.isNotEmpty) {
          await _prefs?.setString(_refreshTokenKey, newRefresh);
        }
        _ref?.read(tokenProvider.notifier).state = newToken;
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> clearTokens() async {
    await _ensurePrefsInitialized();
    await _prefs?.remove(_tokenKey);
    await _prefs?.remove(_refreshTokenKey);
    await _prefs?.remove(_userKey);
    _ref?.read(tokenProvider.notifier).state = null;
  }

  /// Session-expiry flush, invoked by the 401 interceptor when the refresh
  /// (or the post-refresh retry) fails. Clears the persisted session and
  /// bumps the [sessionExpiredProvider] leaf; authTokenProvider listens for
  /// that bump and nulls its state, which the router redirect turns into an
  /// automatic bounce to /login. DioClient can't touch authTokenProvider
  /// directly — that's the startup dependency cycle the tokenProvider leaf
  /// exists to avoid. Best-effort: a flush failure must never mask the
  /// original 401 flowing back to the caller.
  Future<void> _flushExpiredSession() async {
    try {
      await clearTokens();
      final notifier = _ref?.read(sessionExpiredProvider.notifier);
      if (notifier != null) notifier.state++;
    } catch (_) {
      // Swallow: the caller still receives the original DioException.
    }
  }

  // Auth endpoints
  //
  // Phone-first login with optional email fallback for the legacy
  // LoginScreen demo creds. Role is sent in every request so the
  // backend can reject a patient credential trying to reach the
  // admin console with a clean 403.
  Future<AuthToken> login({
    String? phone,
    String? email,
    required String password,
    required UserRole role,
  }) async {
    final cleanPhone = (phone ?? '').trim();
    final cleanEmail = (email ?? '').trim();
    final identifierForMock =
        cleanPhone.isNotEmpty ? cleanPhone : cleanEmail;
    if (_useMockMode) {
      return _mockLogin(identifierForMock, password);
    }
    if (cleanPhone.isEmpty && cleanEmail.isEmpty) {
      throw Exception('Provide a phone or an email');
    }
    try {
      final response = await _dio.post(
        '/api/auth/login',
        data: {
          'role': _roleToWire(role),
          if (cleanPhone.isNotEmpty) 'phone': cleanPhone,
          if (cleanEmail.isNotEmpty) 'email': cleanEmail,
          'password': password,
        },
      );
      final authToken = AuthToken.fromJson(response.data);
      await saveTokens(authToken.token, authToken.refreshToken);
      await _saveUser(authToken.user);
      return authToken;
    } on DioException catch (e) {
      // Typed so the login screen can tell a bad password from a
      // wrong-tab 403 from an unverified phone without reading the prose.
      throw _authError(e);
    }
  }

  /// `POST /api/users/:id/upload-avatar` — multipart upload of the
  /// signed-in user's profile photo. Reads the file as bytes (so it
  /// works on Flutter web where `dart:io File` is unusable) and
  /// returns the public URL the backend persists.
  ///
  /// Caller is expected to invalidate any provider that reads the
  /// profile (e.g. `doctorProfileProvider`) so the new image lands on
  /// screen on the next frame.
  Future<String> uploadProfilePicture({
    required String userId,
    required Uint8List bytes,
    String filename = 'avatar.jpg',
    String mimeType = 'image/jpeg',
  }) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 400));
      return 'https://placehold.co/256x256?text=Mock';
    }
    try {
      final form = FormData.fromMap({
        'avatar': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: DioMediaType.parse(mimeType),
        ),
      });
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/users/$userId/upload-avatar',
        data: form,
      );
      final url = (res.data ?? const {})['profile_picture']?.toString();
      if (url == null || url.isEmpty) {
        throw Exception('Upload succeeded but no URL was returned.');
      }
      return url;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `POST /api/auth/google` — Google OAuth bridge. The Flutter side
  /// runs the native consent dialog via `google_sign_in`, extracts
  /// `{email, googleId, fullName, photoUrl}` from the returned account,
  /// and forwards it here. Server find-or-creates an Account, links by
  /// `googleId` (or `email` for legacy accounts), and returns the same
  /// `{token, refreshToken, user}` shape as a regular login.
  Future<AuthToken> loginWithGoogle({
    required String email,
    required String googleId,
    required String fullName,
    String photoUrl = '',
    UserRole role = UserRole.patient,
  }) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 350));
      return _mockLogin(email, 'google-bypass');
    }
    try {
      final response = await _dio.post(
        '/api/auth/google',
        data: {
          'email': email.trim(),
          'googleId': googleId.trim(),
          'fullName': fullName.trim(),
          if (photoUrl.isNotEmpty) 'photoUrl': photoUrl.trim(),
          'role': _roleToWire(role),
        },
      );
      final authToken = AuthToken.fromJson(response.data);
      await saveTokens(authToken.token, authToken.refreshToken);
      await _saveUser(authToken.user);
      return authToken;
    } on DioException catch (e) {
      throw _authError(e);
    }
  }

  /// `POST /api/auth/signup` — creates a new account
  /// (`is_verified: false`) and returns the User row **without
  /// issuing auth tokens**. The Flutter side routes to the OTP screen;
  /// tokens only show up after [verifyOtp] accepts the code, so an
  /// unverified phone can never be used as a logged-in identity.
  /// Public self-registration — patient only.
  ///
  /// The backend (`POST /api/auth/register`) rejects any privileged
  /// role with a 403, so the Flutter client deliberately doesn't send
  /// a `role` field at all. Doctors / nurses are minted via the
  /// admin `createProvider` rail instead.
  Future<User> register({
    required String fullName,
    required String phone,
    required String password,
    required String address,
  }) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 400));
      return _createMockUser(phone);
    }
    try {
      final response = await _dio.post(
        '/api/auth/signup',
        data: {
          'fullName': fullName.trim(),
          'phone': phone.trim(),
          'address': address.trim(),
          'password': password,
          // `role` is intentionally omitted — the server stamps the
          // new row as `user` (patient) regardless. Sending a
          // privileged role here would 403.
        },
      );
      final body = (response.data as Map<String, dynamic>?) ?? const {};
      final userRaw = body['user'] as Map<String, dynamic>?;
      if (userRaw == null) {
        throw Exception('Signup succeeded but no user was returned.');
      }
      return User.fromJson(userRaw);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `POST /api/admin/create-provider` — admin-only provisioning of a
  /// new doctor / nurse account. Returns the freshly-minted user PLUS
  /// the one-shot temporary password the admin hands to the hire.
  /// The endpoint is bearer-guarded — call sites must already be in
  /// an admin session for this to succeed.
  Future<AdminProvisionResult> createProvider({
    required String fullName,
    required String email,
    required String phone,
    required UserRole role,
  }) async {
    if (role != UserRole.doctor && role != UserRole.nurse) {
      throw Exception('createProvider: role must be doctor or nurse');
    }
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/admin/create-provider',
        data: {
          'name': fullName.trim(),
          'email': email.trim(),
          'phone': phone.trim(),
          'role': _roleToWire(role),
        },
      );
      final body = response.data ?? const <String, dynamic>{};
      final accountRaw = body['account'] as Map<String, dynamic>?;
      final tempPassword = body['temporaryPassword']?.toString() ?? '';
      if (accountRaw == null || tempPassword.isEmpty) {
        throw Exception('Provisioning succeeded but no credentials returned.');
      }
      return AdminProvisionResult(
        account: User.fromJson(accountRaw),
        temporaryPassword: tempPassword,
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `POST /api/auth/complete-password-reset` — single-use endpoint
  /// invoked from the [ForcedPasswordResetScreen] after an
  /// admin-provisioned provider signs in with their temporary
  /// credential. On success the server clears the latch, flips the
  /// account to verified, and re-issues a clean session (same wire
  /// shape as a fresh login).
  Future<AuthToken> completePasswordReset({
    required String newPassword,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/auth/complete-password-reset',
        data: {'newPassword': newPassword},
      );
      final authToken = AuthToken.fromJson(response.data ?? const {});
      await saveTokens(authToken.token, authToken.refreshToken);
      await _saveUser(authToken.user);
      return authToken;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Stage 1 of the admin-edits-provider OTP gate.
  /// `POST /api/admin/providers/:id/request-update-otp` — generates
  /// a 6-digit code on the server, persists it with a 5-minute
  /// expiry on the target provider doc, and (in dev mode) returns
  /// the code so QA can drive the dialog without watching the
  /// server console. Production strips `dev_otp` from the response.
  Future<ProviderUpdateOtpDispatch> requestProviderUpdateOtp(
    String providerId,
  ) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/admin/providers/$providerId/request-update-otp',
      );
      final body = response.data ?? const <String, dynamic>{};
      return ProviderUpdateOtpDispatch.fromJson(body);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Stage 2 of the OTP gate.
  /// `PATCH /api/admin/providers/:id/update-profile` — submits the
  /// admin's field edits plus the typed OTP. The server validates
  /// the code, applies the changes, clears the latch, and returns
  /// the refreshed provider row. 401s on a bad / expired code.
  Future<Map<String, dynamic>> commitProviderUpdate({
    required String providerId,
    required String otp,
    required Map<String, dynamic> updates,
  }) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/api/admin/providers/$providerId/update-profile',
        data: {
          ...updates,
          'otp': otp,
        },
      );
      final body = response.data ?? const <String, dynamic>{};
      final providerJson = body['provider'];
      if (providerJson is Map) {
        return Map<String, dynamic>.from(providerJson);
      }
      return Map<String, dynamic>.from(body);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // Maps the Flutter UserRole enum to the wire vocabulary the backend
  // alias table understands. UserRole.admin maps to 'admin' even though
  // the seeded admin row is stored as 'support_member' — the backend
  // alias accepts either.
  String _roleToWire(UserRole role) {
    switch (role) {
      case UserRole.patient:
        return 'patient';
      case UserRole.doctor:
        return 'doctor';
      case UserRole.nurse:
        return 'nurse';
      case UserRole.admin:
        return 'admin';
    }
  }

  // --- Appointments ---------------------------------------------------------

  /// `GET /api/appointments/latest-completed?account_id=` — the most
  /// recent completed visit for the signed-in patient. Backs the
  /// Rating tab's "your last visit" surface. Returns null when there's
  /// nothing to rate yet (404 from the server) so the screen can render
  /// an empty state instead of an error.
  Future<Appointment?> getLatestCompletedAppointment({
    String? accountId,
  }) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      return _mockLatestAppointment();
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/appointments/latest-completed',
        queryParameters: {
          if (accountId != null && accountId.isNotEmpty) 'account_id': accountId,
        },
      );
      return Appointment.fromJson(res.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      // 404 here means "no completed appointments yet" — that's a
      // legitimate empty state, not an error.
      if (e.response?.statusCode == 404) return null;
      throw _handleError(e);
    }
  }

  /// `GET /api/appointments/patient/history?account_id=` — past
  /// appointments (completed + cancelled) for the patient, newest
  /// first. Returns an empty list when the backend has no rows
  /// rather than throwing — the History tab handles the empty state
  /// on its own.
  ///
  /// Note: distinct from the legacy [getPatientHistory] which returns
  /// `PatientHistoryItem` rows from the `/patient/requests/history`
  /// surface. This is the canonical `Appointment` shape the new
  /// `patientHistoryProvider` consumes.
  Future<List<Appointment>> getPatientAppointmentHistory({
    required String accountId,
    int limit = 50,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/appointments/patient/history',
        queryParameters: {
          'account_id': accountId,
          'limit': limit,
        },
      );
      final body = res.data ?? const <String, dynamic>{};
      final raw = body['appointments'];
      if (raw is! List) return const [];
      final out = <Appointment>[];
      for (final row in raw) {
        if (row is Map) {
          try {
            out.add(Appointment.fromJson(Map<String, dynamic>.from(row)));
          } catch (_) {
            // Skip a malformed row, keep the rest of the list.
          }
        }
      }
      return out;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `GET /api/appointments/:id/messages` — read-only chat transcript
  /// scoped to a single past appointment. Used by the archived chat
  /// screen so the patient can scroll back through the conversation
  /// they had with the provider during that specific visit.
  Future<List<Map<String, dynamic>>> getAppointmentMessages(
    String appointmentId,
  ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/appointments/$appointmentId/messages',
      );
      final body = res.data ?? const <String, dynamic>{};
      final raw = body['messages'];
      if (raw is! List) return const [];
      return [
        for (final m in raw)
          if (m is Map) Map<String, dynamic>.from(m),
      ];
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `GET /api/appointments/:id` — fetch a single appointment by id.
  Future<Appointment> getAppointment(String id) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      return _mockLatestAppointment()!;
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/appointments/$id',
      );
      return Appointment.fromJson(res.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `GET /api/notifications` — every notification for the signed-in
  /// user, newest first. The backend already filters by `recipientId`
  /// via the bearer/JWT or `account_id` fallback, so this surface
  /// only needs the network call.
  Future<Map<String, dynamic>> getNotifications({String? accountId}) async {
    try {
      final res = await _dio.get<dynamic>(
        '/api/notifications',
        queryParameters: {
          if (accountId != null && accountId.isNotEmpty) 'account_id': accountId,
        },
      );
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return const {};
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `PATCH /api/notifications/:id/read` — flip one notification to read.
  Future<void> markHubNotificationRead(
    String id, {
    String? accountId,
  }) async {
    try {
      await _dio.patch<dynamic>(
        '/api/notifications/$id/read',
        queryParameters: {
          if (accountId != null && accountId.isNotEmpty) 'account_id': accountId,
        },
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `PATCH /api/notifications/read-all` — bulk mark.
  Future<int> markAllHubNotificationsRead({String? accountId}) async {
    try {
      final res = await _dio.patch<dynamic>(
        '/api/notifications/read-all',
        queryParameters: {
          if (accountId != null && accountId.isNotEmpty) 'account_id': accountId,
        },
      );
      final data = res.data;
      if (data is Map && data['updated'] is num) {
        return (data['updated'] as num).toInt();
      }
      return 0;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `GET /api/chat/:appointmentId` — historical message log for a
  /// chat thread, oldest-first. Returns the raw maps so the
  /// [MessageModel] parser owns the wire-shape mapping; here we only
  /// guarantee the network call succeeded and unwrap the `messages`
  /// envelope the backend uses.
  Future<List<Map<String, dynamic>>> getChatHistory(String appointmentId) async {
    try {
      final res = await _dio.get<dynamic>('/api/chat/$appointmentId');
      final data = res.data;
      final List rawList;
      if (data is Map && data['messages'] is List) {
        rawList = data['messages'] as List;
      } else if (data is List) {
        rawList = data;
      } else {
        rawList = const [];
      }
      return [
        for (final raw in rawList)
          if (raw is Map) Map<String, dynamic>.from(raw),
      ];
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `POST /api/chat/:appointmentId/attachment` (multipart, field `file`) —
  /// uploads an image for a chat message and returns the permanent
  /// `mediaUrl`. The caller then sends a normal IMAGE `send_message` over the
  /// socket carrying this url. Mirrors [uploadProfilePicture].
  Future<String> uploadChatAttachment({
    required String appointmentId,
    required Uint8List bytes,
    String filename = 'attachment.jpg',
    String mimeType = 'image/jpeg',
  }) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 400));
      return 'https://placehold.co/600x400?text=Mock';
    }
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: DioMediaType.parse(mimeType),
        ),
      });
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/chat/$appointmentId/attachment',
        data: form,
      );
      final url = (res.data ?? const {})['mediaUrl']?.toString();
      if (url == null || url.isEmpty) {
        throw Exception('Upload succeeded but no mediaUrl was returned.');
      }
      return url;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `POST /api/telephony/initiate-masked-call` — bridges the caller and the
  /// other booking party on a masked proxy voice line (neither sees the
  /// other's real number). Returns the raw response map
  /// (`{ success, status, callId, proxyDisplay, message }`).
  Future<Map<String, dynamic>> initiateMaskedCall(String appointmentId) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 500));
      return {
        'success': true,
        'status': 'connecting',
        'proxyDisplay': '+880 9600 TAAFI',
        'message': 'Connecting via secure proxy line…',
      };
    }
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/telephony/initiate-masked-call',
        data: {'appointmentId': appointmentId},
      );
      return Map<String, dynamic>.from(res.data ?? const {});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // ── Multi-role conversation engine ────────────────────────────────────────

  /// `GET /api/conversations` — the signed-in user's inbox: every thread
  /// they participate in, newest-activity first, each carrying their own
  /// unread count. Returns the raw maps for the [Conversation] parser.
  Future<List<Map<String, dynamic>>> getConversations() async {
    try {
      final res = await _dio.get<dynamic>('/api/conversations');
      final data = res.data;
      final List rawList;
      if (data is Map && data['conversations'] is List) {
        rawList = data['conversations'] as List;
      } else if (data is List) {
        rawList = data;
      } else {
        rawList = const [];
      }
      return [
        for (final raw in rawList)
          if (raw is Map) Map<String, dynamic>.from(raw),
      ];
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `POST /api/conversations` — find-or-create a thread for the given
  /// participant account ids (the caller is always included server-side),
  /// optionally anchored to a booking (`contextRequestId`). Returns the
  /// conversation map so the caller can open it.
  Future<Map<String, dynamic>> openConversation({
    required List<String> participantIds,
    String? contextRequestId,
  }) async {
    try {
      final res = await _dio.post<dynamic>(
        '/api/conversations',
        data: {
          'participantIds': participantIds,
          'contextRequestId': ?contextRequestId,
        },
      );
      final data = res.data;
      if (data is Map && data['conversation'] is Map) {
        return Map<String, dynamic>.from(data['conversation'] as Map);
      }
      if (data is Map) return Map<String, dynamic>.from(data);
      throw Exception('Unexpected openConversation response');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `GET /api/conversations/:id/messages` — paginated history, oldest-first.
  /// Pass [before] (an ISO-8601 timestamp) to page backwards through older
  /// messages.
  Future<List<Map<String, dynamic>>> getConversationMessages(
    String conversationId, {
    String? before,
    int limit = 50,
  }) async {
    try {
      final res = await _dio.get<dynamic>(
        '/api/conversations/$conversationId/messages',
        queryParameters: {
          'limit': limit,
          'before': ?before,
        },
      );
      final data = res.data;
      final List rawList;
      if (data is Map && data['messages'] is List) {
        rawList = data['messages'] as List;
      } else if (data is List) {
        rawList = data;
      } else {
        rawList = const [];
      }
      return [
        for (final raw in rawList)
          if (raw is Map) Map<String, dynamic>.from(raw),
      ];
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `POST /api/conversations/:id/read` — HTTP fallback that resets the
  /// caller's unread tally for a thread. The socket `conversation:read`
  /// event is the primary path; this covers clients without a live socket.
  Future<void> markConversationRead(String conversationId) async {
    try {
      await _dio.post<dynamic>('/api/conversations/$conversationId/read');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `POST /api/appointments/:id/feedback` — submits a rating + tags
  /// for a completed visit. Server validates the tag allow-list and
  /// rejects double-submissions; both surface as Exceptions here so
  /// the Riverpod notifier can land them in the Rating screen's
  /// SnackBar path.
  Future<Appointment> submitAppointmentFeedback({
    required String appointmentId,
    required int rating,
    required List<String> tags,
    String? comment,
    String? accountId,
  }) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 300));
      return _mockLatestAppointment()!;
    }
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/appointments/$appointmentId/feedback',
        data: {
          'rating': rating,
          'tags': tags,
          if (comment != null && comment.isNotEmpty) 'comment': comment,
          if (accountId != null && accountId.isNotEmpty)
            'account_id': accountId,
        },
      );
      final body = res.data ?? const <String, dynamic>{};
      final appt = body['appointment'] as Map<String, dynamic>?;
      if (appt == null) {
        throw Exception('Feedback saved but no appointment returned.');
      }
      return Appointment.fromJson(appt);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // Mock-mode-only stub so the offline-demo Rating screen still has
  // something to render. Mirrors the backend's `completed` shape.
  Appointment? _mockLatestAppointment() {
    final now = DateTime.now();
    return Appointment.fromJson({
      'id': 'MT-MOCK-LATEST',
      'care_type': 'Post-surgery home care',
      'status': 'completed',
      'assigned_doctor_name': 'Dr. Nafisa Rahman',
      'assigned_helper_name': 'Shahana Begum',
      'location_text': 'House 42, Road 11A, Dhanmondi',
      'created_at': now.subtract(const Duration(hours: 2)).toIso8601String(),
      'updated_at': now.toIso8601String(),
      'vitals': {
        'blood_pressure': '128/82',
        'temperature': '99.1',
        'spo2': '97',
        'pulse': '78',
        'pain_score': '3/10',
        'wound_status': 'Clean',
      },
      'payment': {
        'doctor_fee': 2400,
        'helper_fee': 900,
        'platform_fee': 200,
        'total': 3500,
        'released_at': now.toIso8601String(),
      },
      'feedback': {'is_reviewed': false},
    });
  }

  /// `POST /auth/reset-password` — Forgot Password flow. Verifies the
  /// dev OTP, bcrypts the new password server-side, and auto-signs the
  /// user in (same JWT/refresh shape as login). On success the
  /// session is persisted so the user skips the login screen.
  Future<AuthToken> resetPassword({
    required String phone,
    required String otp,
    required String newPassword,
  }) async {
    if (_useMockMode) {
      if (otp.trim() != '222222') {
        throw Exception('Invalid OTP — please try again');
      }
      await Future.delayed(const Duration(milliseconds: 350));
      return _mockLogin(phone, newPassword);
    }
    try {
      final response = await _dio.post(
        '/api/auth/reset-password',
        data: {
          'phone': phone.trim(),
          'otp': otp.trim(),
          'newPassword': newPassword,
        },
      );
      final authToken = AuthToken.fromJson(response.data);
      await saveTokens(authToken.token, authToken.refreshToken);
      await _saveUser(authToken.user);
      return authToken;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `POST /auth/verify-otp` — submits the 4/6-digit code captured on
  /// the OTP screen. On 200 the backend flips `is_verified: true` and
  /// issues `{token, refreshToken, user}` — same shape as login — so
  /// this method saves the session and returns the [AuthToken]. On
  /// 400 the code was wrong (or the dev pin '222222' didn't match)
  /// and the caller surfaces the error in a SnackBar.
  Future<AuthToken> verifyOtp({
    required String phone,
    required String otp,
  }) async {
    if (_useMockMode) {
      // Mock branch: accept '222222' so the offline-demo loop runs the
      // same gate the backend uses. Anything else throws like a 400.
      if (otp.trim() != '222222') {
        throw Exception('Invalid OTP — please try again');
      }
      await Future.delayed(const Duration(milliseconds: 350));
      return _mockLogin(phone, 'password');
    }
    try {
      final response = await _dio.post(
        '/api/auth/verify-otp',
        data: {'phone': phone.trim(), 'otp': otp.trim()},
      );
      final authToken = AuthToken.fromJson(response.data);
      await saveTokens(authToken.token, authToken.refreshToken);
      await _saveUser(authToken.user);
      return authToken;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // Mock login - demo data
  Future<AuthToken> _mockLogin(String email, String password) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));

    // Create user based on email
    final user = _createMockUser(email);

    // Create mock token (JWT-like format)
    const mockToken = 'mock_jwt_eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U';
    const mockRefreshToken = 'mock_refresh_token_abcdefg123456';

    final authToken = AuthToken(
      token: mockToken,
      refreshToken: mockRefreshToken,
      user: user,
    );

    await saveTokens(mockToken, mockRefreshToken);
    return authToken;
  }

  // Create mock user based on email
  User _createMockUser(String email) {
    final e = email.trim().toLowerCase();
    if (e.contains('doctor')) {
      return User(
        id: 'doctor_001',
        name: 'Dr. Nafisa Rahman',
        email: 'doctor@taafi.app',
        phone: '+880 1700 000001',
        role: UserRole.doctor,
        avatar: 'NR',
        specialization: 'General Surgery',
        rating: 4.93,
        reviewCount: 127,
      );
    } else if (e.contains('admin')) {
      return User(
        id: 'admin_001',
        name: 'Admin User',
        email: 'admin@taafi.app',
        phone: '+880 1700 000002',
        role: UserRole.admin,
        avatar: 'AU',
      );
    } else {
      // Patient (default)
      return User(
        id: 'patient_001',
        name: 'Rumi Ahmed',
        email: 'patient@taafi.app',
        phone: '+880 1700 000003',
        role: UserRole.patient,
        avatar: 'RA',
      );
    }
  }

  // Patient endpoints
  Future<List<dynamic>> getPatientRequests() async {
    try {
      final response = await _dio.get('/patient/requests');
      return response.data as List;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<PatientHomeFeed> getPatientHomeFeed() async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 350));
      _ensurePatientMockSeeded();
      return PatientHomeFeed(
        activeRequest: _mockPatientActiveRequest,
        recentProviders: List.unmodifiable(_mockRecentProviders),
        unreadNotificationCount:
            _mockPatientNotifications.where((n) => !n.read).length,
        fetchedAt: DateTime.now(),
      );
    }
    try {
      final response = await _dio.get<Map<String, dynamic>>('/patient/home');
      // Live Mongo documents are snake_case; route through the dedicated
      // parser rather than the camelCase PatientHomeFeed.fromJson.
      return patientHomeFeedFromMongo(response.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<PatientNotification>> getPatientNotifications() async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 300));
      _ensurePatientMockSeeded();
      return List.unmodifiable(_mockPatientNotifications);
    }
    try {
      final response = await _dio.get('/patient/notifications');
      final list = response.data as List;
      return list
          .map((e) => PatientNotification.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> markPatientNotificationRead(String id) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      _ensurePatientMockSeeded();
      final idx = _mockPatientNotifications.indexWhere((n) => n.id == id);
      if (idx != -1) {
        _mockPatientNotifications[idx] =
            _mockPatientNotifications[idx].copyWith(read: true);
      }
      return;
    }
    try {
      await _dio.patch('/patient/notifications/$id/read');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> markAllPatientNotificationsRead() async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 250));
      _ensurePatientMockSeeded();
      for (var i = 0; i < _mockPatientNotifications.length; i++) {
        if (!_mockPatientNotifications[i].read) {
          _mockPatientNotifications[i] =
              _mockPatientNotifications[i].copyWith(read: true);
        }
      }
      return;
    }
    try {
      await _dio.post('/patient/notifications/mark-all-read');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<dynamic> createRequest(Map<String, dynamic> requestData) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 700));
      _ensurePatientMockSeeded();
      final now = DateTime.now();
      final id = 'MT-${(now.millisecondsSinceEpoch % 9000) + 1000}';

      final address =
          (requestData['address'] as Map?)?.cast<String, dynamic>() ?? const {};
      final locationParts = <String>[
        if ((address['line1'] as String?)?.isNotEmpty == true)
          address['line1'] as String,
        if ((address['areaCityZip'] as String?)?.isNotEmpty == true)
          address['areaCityZip'] as String,
      ];
      final locationLabel = locationParts.isEmpty
          ? 'Patient address on file'
          : locationParts.join(', ');
      final scheduledAtRaw = requestData['scheduledAt'] as String?;
      final scheduledAt =
          scheduledAtRaw != null ? DateTime.tryParse(scheduledAtRaw) : null;

      _mockPatientActiveRequest = PatientActiveRequest(
        id: id,
        serviceTitleEn: (requestData['serviceTitle'] as String?) ?? 'New visit',
        serviceTitleBn:
            (requestData['serviceTitleBn'] as String?) ?? '',
        status: PatientRequestStatus.pendingReview,
        locationLabel: locationLabel,
        requestedAt: now,
        scheduledAt: scheduledAt,
        reviewEtaMinutes: 5,
        durationHours: (requestData['durationHours'] as num?)?.toInt(),
        offer: (requestData['offer'] as num?)?.toInt(),
        updatedAt: now,
      );

      // Surface a "request received" notification so the bell on Home blinks.
      _mockPatientNotifications.insert(
        0,
        PatientNotification(
          id: 'ntf_${now.millisecondsSinceEpoch}',
          kind: PatientNotificationKind.request,
          titleEn: 'Request received',
          titleBn: 'আবেদন গৃহীত',
          bodyEn:
              'Our medical admin is matching you with a qualified doctor. We will notify you once accepted.',
          createdAt: now,
          read: false,
          payload: {'requestId': id},
        ),
      );

      // ── Cross-role fan-out (Patient → Admin) ────────────────────────────
      // The admin's Review Queue reads from `_mockAdminRequests`; without
      // this insert the new submission would never surface there.
      _ensureAdminMockSeeded();
      final patientName =
          (requestData['patientName'] as String?)?.trim().isNotEmpty == true
              ? requestData['patientName'] as String
              : 'New Patient';
      final serviceTitle =
          (requestData['serviceTitle'] as String?) ?? 'New visit';
      final area = (address['areaCityZip'] as String?) ?? '';
      final adminRequest = AdminCareRequest(
        id: id,
        patientId: (requestData['patientId'] as String?) ?? 'p_pending',
        patientName: patientName,
        patientAge: 0,
        serviceType: _inferServiceTypeFromTitle(serviceTitle),
        serviceName: serviceTitle,
        location: locationLabel,
        area: area.split(',').first.trim(),
        durationHours:
            (requestData['durationHours'] as num?)?.toInt() ?? 2,
        asap: scheduledAt == null,
        scheduledTime: scheduledAt,
        status: 'pending',
        createdAt: now,
        urgencyLevel: scheduledAt == null
            ? UrgencyLevel.high
            : UrgencyLevel.medium,
        patientOffer: ((requestData['offer'] as num?) ?? 0).toDouble(),
        adjustedPrice: ((requestData['offer'] as num?) ?? 0).toDouble(),
        notes: (requestData['notes'] as String?),
      );
      _mockAdminRequests.insert(0, adminRequest);

      // Light up the admin activity feed so the notification dot reacts.
      _mockActivityFeed.insert(
        0,
        ActivityEvent(
          id: 'ev_${now.millisecondsSinceEpoch}',
          message: 'New request $id from $patientName — $serviceTitle',
          timestamp: now,
          eventType: ActivityEventType.system,
          requestId: id,
        ),
      );

      return {
        'id': id,
        'status': PatientRequestStatus.pendingReview.toWire(),
        'createdAt': now.toIso8601String(),
      };
    }
    // Real backend: `POST /patient/requests` against the live Mongo-
    // backed API. We accept ONLY 201 Created as success — any other
    // 2xx (e.g. 200 = duplicate idempotency hit, 202 = queued but not
    // yet inserted) should NOT trigger the cross-role fan-out because
    // the row may not be readable from `/admin/requests` yet.
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/patient/requests',
        data: requestData,
        options: Options(
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (res.statusCode != 201) {
        throw DioException(
          requestOptions: res.requestOptions,
          response: res,
          error: 'Expected 201 Created, got ${res.statusCode}',
        );
      }
      return res.data ?? const <String, dynamic>{};
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> cancelPatientRequest(String requestId, {String? reason}) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 450));
      _ensurePatientMockSeeded();
      // If the in-memory active request matches, clear it so subsequent feed
      // fetches return null. Real backend will own this state of course.
      if (_mockPatientActiveRequest?.id == requestId) {
        _mockPatientActiveRequest = null;
      }
      _mockPatientNotifications.insert(
        0,
        PatientNotification(
          id: 'ntf_${DateTime.now().millisecondsSinceEpoch}',
          kind: PatientNotificationKind.system,
          titleEn: 'Request cancelled',
          titleBn: 'আবেদন বাতিল',
          bodyEn:
              'Your request $requestId has been cancelled. Any escrowed payment will be refunded within 24 hrs.',
          createdAt: DateTime.now(),
          read: false,
        ),
      );
      return;
    }
    try {
      await _dio.post(
        '/patient/requests/$requestId/cancel',
        data: {'reason': ?reason},
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // ------------------------------------------------------------------
  // Two-phase booking confirmation payments (SSLCommerz + simulated
  // fallback). `init*` opens a gateway session (returns `{simulated,
  // gatewayUrl, tranId, amount}`); `confirm*` settles a payment and
  // returns the updated care-request row.
  // ------------------------------------------------------------------

  Future<Map<String, dynamic>> initBookingDeposit(String requestId) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 300));
      return {
        'simulated': true,
        'amount': 100,
        'tranId': 'MOCK-DEP-${DateTime.now().millisecondsSinceEpoch}',
        'gatewayUrl': null,
      };
    }
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/patient/requests/$requestId/deposit/init',
      );
      return res.data ?? const <String, dynamic>{};
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> confirmBookingDeposit(
    String requestId, {
    String? tranId,
    String? valId,
  }) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 400));
      return {'id': requestId, 'status': 'deposit_paid_admin_reviewing'};
    }
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/patient/requests/$requestId/deposit/confirm',
        data: {'tranId': tranId, 'valId': valId},
      );
      return res.data ?? const <String, dynamic>{};
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> initBookingBalance(String requestId) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 300));
      return {
        'simulated': true,
        'amount': 0,
        'tranId': 'MOCK-BAL-${DateTime.now().millisecondsSinceEpoch}',
        'gatewayUrl': null,
      };
    }
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/patient/requests/$requestId/balance/init',
      );
      return res.data ?? const <String, dynamic>{};
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> confirmBookingBalance(
    String requestId, {
    String? tranId,
    String? valId,
  }) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 400));
      return {'id': requestId, 'status': 'approved'};
    }
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/patient/requests/$requestId/balance/confirm',
        data: {'tranId': tranId, 'valId': valId},
      );
      return res.data ?? const <String, dynamic>{};
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `PATCH /patient/requests/:id/payment-preference` — the patient
  /// pre-commits to how they'll settle the outstanding balance:
  /// `'CASH_ON_SERVICE'` (pay the provider in cash at the door — makes the
  /// provider's collect-cash step mandatory) or `'DIGITAL'` (pay via the
  /// gateway). Records intent only; it moves no money and does not change
  /// the booking status. Returns the updated booking document.
  Future<Map<String, dynamic>> setPaymentPreference(
    String requestId,
    String preference,
  ) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 250));
      return {'id': requestId, 'payment_preference': preference};
    }
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/patient/requests/$requestId/payment-preference',
        data: {'preference': preference},
      );
      return res.data ?? const <String, dynamic>{};
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Admin pricing gateway. Assigns the base service fee (and an optional
  /// discount / call note) to a booking under review. A SILENT invoice
  /// update — the status does not change and the patient is not prompted
  /// to pay; the balance becomes payable only after the service completes.
  Future<Map<String, dynamic>> adminSetBookingPrice(
    String requestId, {
    required double finalServiceFee,
    double adjustedDiscount = 0,
    String? adminNote,
  }) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 400));
      return {
        'id': requestId,
        'status': 'deposit_paid_admin_reviewing',
        'final_price': finalServiceFee,
        'adjusted_discount': adjustedDiscount,
      };
    }
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/admin/requests/$requestId/set-price',
        data: {
          'final_service_fee': finalServiceFee,
          'adjusted_discount': adjustedDiscount,
          'admin_note': ?adminNote,
        },
      );
      return res.data ?? const <String, dynamic>{};
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // ------------------------------------------------------------------
  // Prescription release gate (admin approval). A script is paid for by
  // settling the booking's outstanding balance (initBookingBalance /
  // confirmBookingBalance above) — there is no per-prescription fee.
  // ------------------------------------------------------------------

  /// `GET /admin/prescriptions/review-queue` — PAID scripts awaiting an
  /// admin decision (default), or the decided sets via [status]
  /// ('approved' | 'rejected'). Rows arrive unredacted with a
  /// `patient` contact block.
  Future<List<Prescription>> adminGetPrescriptionReviewQueue(
      {String? status}) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 300));
      return const <Prescription>[];
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/admin/prescriptions/review-queue',
        queryParameters: {'status': ?status},
      );
      final body = res.data ?? const <String, dynamic>{};
      final raw = body['prescriptions'];
      if (raw is! List) return const [];
      final out = <Prescription>[];
      for (final p in raw) {
        if (p is Map) {
          try {
            out.add(Prescription.fromJson(Map<String, dynamic>.from(p)));
          } catch (_) {
            // skip malformed row
          }
        }
      }
      return out;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `PATCH /admin/prescriptions/:id/approval` — the explicit admin
  /// gate. Approve unlocks the script for the patient; reject keeps it
  /// redacted with a support-facing reason.
  Future<Prescription> adminSetPrescriptionApproval(
    String prescriptionId, {
    required bool approve,
    String? reason,
  }) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/admin/prescriptions/$prescriptionId/approval',
        data: {
          'action': approve ? 'approve' : 'reject',
          'reason': ?reason,
        },
      );
      final body = res.data ?? const <String, dynamic>{};
      final raw = body['prescription'];
      if (raw is Map) {
        return Prescription.fromJson(Map<String, dynamic>.from(raw));
      }
      return Prescription.fromJson(body);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // Administrative cancellation. Admin-only (guarded server-side by
  // requireRole('admin')); the dedicated endpoint also releases the assigned
  // provider/team and notifies the patient + providers — which the generic
  // bulk-status path does not — so cancels must route through here.
  Future<Map<String, dynamic>> adminCancelBooking(
    String requestId, {
    String? reason,
  }) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 400));
      return {
        'id': requestId,
        'status': 'cancelled',
      };
    }
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/admin/requests/$requestId/cancel',
        data: {
          'reason': ?reason,
        },
      );
      return res.data ?? const <String, dynamic>{};
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<dynamic> getService(String serviceId) async {
    try {
      final response = await _dio.get('/patient/services/$serviceId');
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> submitRating(String serviceId, Map<String, dynamic> rating) async {
    try {
      await _dio.post('/patient/services/$serviceId/rating', data: rating);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // Doctor endpoints
  Future<DoctorDashboard> getDoctorDashboard() async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 350));
      return _mockDoctorDashboard();
    }
    try {
      final response =
          await _dio.get<Map<String, dynamic>>('/doctor/dashboard');
      // Live MongoDB documents are snake_case; route through the
      // dedicated parser instead of the camelCase `DoctorDashboard.fromJson`
      // (which stays in place for any internal mock callers).
      return doctorDashboardFromMongo(
        response.data ?? const <String, dynamic>{},
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> acceptAssignment(String assignmentId) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 300));
      _mockPendingAssignment = null;
      return;
    }
    try {
      await _dio.post('/doctor/assignments/$assignmentId/accept');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> declineAssignment(String assignmentId) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 300));
      _mockPendingAssignment = null;
      return;
    }
    try {
      await _dio.post('/doctor/assignments/$assignmentId/decline');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Drives the doctor-side state machine on the Active Service screen:
  ///   assigned → on_the_way → arrived → in_service → completed
  ///
  /// The backend normalizes `on_the_way` to the canonical schema enum
  /// `enroute`, so the wire vocabulary works either way. Returns the full
  /// updated `care_requests` document.
  /// `POST /api/auth/fcm-token` — register / unregister an FCM device
  /// token for the signed-in account. Called on login + after every
  /// token refresh from the notification bootstrap layer. Idempotent
  /// (the backend dedupes appends in a pre-save hook). Returns the
  /// account's total registered device count for observability.
  Future<int> registerFcmToken(String token, {bool unregister = false}) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/auth/fcm-token',
        data: {'token': token, 'unregister': unregister},
      );
      final body = res.data ?? const <String, dynamic>{};
      final count = body['tokenCount'];
      if (count is num) return count.toInt();
      return 0;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `POST /api/prescriptions` — issue a digital prescription from
  /// the doctor's care-completion form. Returns the persisted row.
  Future<Prescription> createPrescription({
    required String appointmentId,
    required List<PrescriptionItem> items,
    String? patientAccountId,
    String? doctorName,
    String? diagnosis,
    double? weightKg,
    double? heightCm,
    String? advice,
    DateTime? followUpDate,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/prescriptions',
        data: {
          'appointmentId': appointmentId,
          if (patientAccountId != null && patientAccountId.isNotEmpty)
            'patientAccountId': patientAccountId,
          if (doctorName != null && doctorName.isNotEmpty)
            'doctorName': doctorName,
          if (diagnosis != null && diagnosis.isNotEmpty) 'diagnosis': diagnosis,
          // Pad extras — the server snapshots BP from the visit's
          // vitals itself; weight/height/advice/follow-up ride along
          // only when the doctor filled them.
          'weight_kg': ?weightKg,
          'height_cm': ?heightCm,
          if (advice != null && advice.isNotEmpty) 'advice': advice,
          if (followUpDate != null)
            'follow_up_date': followUpDate.toIso8601String(),
          'items': items.map((i) => i.toJson()).toList(),
        },
      );
      final body = res.data ?? const <String, dynamic>{};
      final raw = body['prescription'];
      if (raw is Map) {
        return Prescription.fromJson(Map<String, dynamic>.from(raw));
      }
      return Prescription.fromJson(body);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `GET /api/prescriptions/my-active` — every prescription for the
  /// signed-in patient whose calendar window overlaps today.
  Future<List<Prescription>> getMyActivePrescriptions() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/prescriptions/my-active',
      );
      final body = res.data ?? const <String, dynamic>{};
      final raw = body['prescriptions'];
      if (raw is! List) return const [];
      final out = <Prescription>[];
      for (final p in raw) {
        if (p is Map) {
          try {
            out.add(Prescription.fromJson(Map<String, dynamic>.from(p)));
          } catch (_) {
            // skip malformed row
          }
        }
      }
      return out;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `PATCH /api/prescriptions/:id/dose` — toggle the Mark-as-Taken
  /// state for one (itemId, slot, dayKey) triple. Returns the
  /// refreshed prescription so the timeline's optimistic update can
  /// reconcile against the canonical server state.
  Future<Prescription> setDoseTaken({
    required String prescriptionId,
    required String itemId,
    required DoseSlot slot,
    required String dayKey,
    required bool taken,
  }) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/api/prescriptions/$prescriptionId/dose',
        data: {
          'itemId': itemId,
          'slot': slot.wire,
          'dayKey': dayKey,
          'taken': taken,
        },
      );
      final body = res.data ?? const <String, dynamic>{};
      final raw = body['prescription'];
      if (raw is Map) {
        return Prescription.fromJson(Map<String, dynamic>.from(raw));
      }
      return Prescription.fromJson(body);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `PATCH /api/appointments/:id/update-status` — canonical
  /// provider-driven transition for the active visit
  /// (`accepted` → `on-the-way` → `arrived` → `completed`). Hardened
  /// server-side: 403s when the caller isn't the assigned provider,
  /// broadcasts an `appointment_status_change` event to the room so
  /// the patient chat + tracking screens flip without a manual
  /// refresh. Returns the refreshed appointment JSON.
  Future<Map<String, dynamic>> updateAppointmentStatus({
    required String appointmentId,
    required String status,
  }) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/api/appointments/$appointmentId/update-status',
        data: {'status': status},
      );
      final body = res.data ?? const <String, dynamic>{};
      final appt = body['appointment'];
      if (appt is Map) return Map<String, dynamic>.from(appt);
      return body;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> updateVisitStatus(
    String requestId,
    String newStatus,
  ) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 250));
      // Mock branch: best-effort in-memory mutation so the dev loop
      // reflects the transition without a backend.
      final idx = _mockAdminRequests.indexWhere((r) => r.id == requestId);
      if (idx != -1) {
        _mockAdminRequests[idx] =
            _mockAdminRequests[idx].copyWith(status: newStatus);
      }
      return {'id': requestId, 'status': newStatus};
    }
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/doctor/visits/$requestId/status',
        data: {'status': newStatus},
      );
      return res.data ?? const <String, dynamic>{};
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Posts a doctor's current GPS coordinates. Called periodically by
  /// `LocationTrackingService` whenever the doctor is ONLINE. The
  /// backend handler (POST /doctor/location) requires `doctor_id` so it
  /// knows which Account/Provider row to upsert the GeoJSON Point onto;
  /// the tracker resolves it from the auth session at call time.
  /// Silently no-ops in mock mode so the dev loop doesn't hit a backend.
  Future<void> postDoctorLocation({
    required String doctorId,
    required double latitude,
    required double longitude,
    double? accuracyMeters,
    double? speedMps,
  }) async {
    if (_useMockMode) {
      return;
    }
    try {
      await _dio.post('/doctor/location', data: {
        'doctor_id': doctorId,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy_meters': ?accuracyMeters,
        'speed_mps': ?speedMps,
        'reported_at': DateTime.now().toIso8601String(),
      });
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> setAvailability(bool online, {String? doctorId}) async {
    await _ensurePrefsInitialized();
    await _prefs?.setBool(_availabilityKey, online);
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      return;
    }
    try {
      // Backend requires `doctor_id` to know which Provider row to flip.
      // Without it the route returns 400 and the toggle stays out of sync
      // with the admin's match queue.
      await _dio.patch('/doctor/availability', data: {
        'doctor_id': ?doctorId,
        'online': online,
      });
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Session-resolved on/off-duty flip for the signed-in provider
  /// (doctor / nurse). Unlike [setAvailability], the backend resolves the
  /// Provider row from the bearer session, so no id is needed — fixing the
  /// nurse duty toggle that previously sent no `doctor_id` and 400'd.
  Future<void> setProviderAvailability(bool online) async {
    await _ensurePrefsInitialized();
    await _prefs?.setBool(_availabilityKey, online);
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      return;
    }
    try {
      await _dio.patch('/api/provider/availability', data: {'online': online});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Updates the provider's default visit fee / base charge via
  /// PATCH /api/provider/profile-settings (session-resolved).
  Future<void> updateProviderFee(int fee) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 250));
      return;
    }
    try {
      await _dio.patch('/api/provider/profile-settings', data: {'fee': fee});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Settled-vs-pending payout ledger for the signed-in provider.
  Future<ProviderEarnings> getProviderEarnings() async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 250));
      return ProviderEarnings.empty;
    }
    try {
      final res =
          await _dio.get<Map<String, dynamic>>('/api/provider/earnings');
      return ProviderEarnings.fromJson(res.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // --- Provider wallet (`/api/provider/wallet`) ----------------------------
  // The commission-split ledger: balances, history, and withdrawals. Backed by
  // controllers/providerWalletController.js.

  /// `GET /api/provider/wallet` — balances, platform limits, the saved
  /// (masked) payout destination, and any in-flight withdrawal. One round
  /// trip backs the whole overview section of the Wallet page.
  Future<ProviderWalletSnapshot> getProviderWallet() async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      return const ProviderWalletSnapshot(
        wallet: ProviderWallet(
          digitalBalance: 4800,
          cashInHand: 1200,
          totalEarned: 18400,
          totalWithdrawn: 12400,
        ),
      );
    }
    try {
      final res =
          await _dio.get<Map<String, dynamic>>('/api/provider/wallet');
      return ProviderWalletSnapshot.fromJson(
        res.data ?? const <String, dynamic>{},
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `GET /api/provider/wallet/transactions` — the chronological ledger
  /// behind the history list.
  Future<List<WalletTransaction>> getWalletTransactions({
    int page = 1,
    int limit = 30,
  }) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      return const <WalletTransaction>[];
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/provider/wallet/transactions',
        queryParameters: {'page': page, 'limit': limit},
      );
      final raw = (res.data ?? const {})['items'];
      if (raw is! List) return const <WalletTransaction>[];
      return raw
          .whereType<Map>()
          .map((e) => WalletTransaction.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `POST /api/provider/wallet/withdraw` — request a payout. Throws on any
  /// non-2xx (409 for insufficient balance, a payout lock, or an existing
  /// pending request) so the sheet surfaces the server's message verbatim.
  Future<PayoutRequestModel> requestWithdrawal({
    required num amount,
    required String method,
    String? accountNumber,
    String? accountName,
    String? bankName,
    String? branch,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/provider/wallet/withdraw',
        data: {
          'amount': amount,
          'method': method,
          if (accountNumber != null && accountNumber.isNotEmpty)
            'accountNumber': accountNumber,
          if (accountName != null && accountName.isNotEmpty)
            'accountName': accountName,
          if (bankName != null && bankName.isNotEmpty) 'bankName': bankName,
          if (branch != null && branch.isNotEmpty) 'branch': branch,
        },
      );
      final raw = (res.data ?? const {})['payoutRequest'];
      return PayoutRequestModel.fromJson(
        raw is Map ? Map<String, dynamic>.from(raw) : const {},
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `GET /api/provider/wallet/payouts` — the provider's own withdrawal
  /// history across all statuses.
  Future<List<PayoutRequestModel>> getMyPayouts() async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 150));
      return const <PayoutRequestModel>[];
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/provider/wallet/payouts',
      );
      final raw = (res.data ?? const {})['items'];
      if (raw is! List) return const <PayoutRequestModel>[];
      return raw
          .whereType<Map>()
          .map(
              (e) => PayoutRequestModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // --- Saved-address ledger (`/api/addresses`) -----------------------------

  Future<List<SavedAddress>> listAddresses() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/api/addresses');
      final raw = (res.data ?? const {})['addresses'];
      if (raw is! List) return const [];
      return [
        for (final a in raw)
          if (a is Map) SavedAddress.fromJson(Map<String, dynamic>.from(a)),
      ];
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<SavedAddress> saveAddress({
    String? id,
    required String label,
    required String fullAddressText,
    required String flatFloorHolding,
    required String landmarkInstructions,
    double? latitude,
    double? longitude,
    bool? isDefault,
  }) async {
    final data = <String, dynamic>{
      'label': label,
      'full_address_text': fullAddressText,
      'flat_floor_holding': flatFloorHolding,
      'landmark_instructions': landmarkInstructions,
      'latitude': latitude,
      'longitude': longitude,
      'is_default': ?isDefault,
    };
    try {
      final res = id == null
          ? await _dio.post<Map<String, dynamic>>('/api/addresses', data: data)
          : await _dio.patch<Map<String, dynamic>>('/api/addresses/$id',
              data: data);
      final body = res.data ?? const <String, dynamic>{};
      return SavedAddress.fromJson(
          Map<String, dynamic>.from(body['address'] as Map? ?? body));
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<SavedAddress> setDefaultAddress(String id) async {
    try {
      final res = await _dio
          .patch<Map<String, dynamic>>('/api/addresses/$id/default');
      final body = res.data ?? const <String, dynamic>{};
      return SavedAddress.fromJson(
          Map<String, dynamic>.from(body['address'] as Map? ?? body));
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> deleteAddress(String id) async {
    try {
      await _dio.delete('/api/addresses/$id');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // --- Dependents / family profiles (`/api/dependents`) --------------------

  Future<List<Dependent>> listDependents() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/api/dependents');
      final raw = (res.data ?? const {})['dependents'];
      if (raw is! List) return const [];
      return [
        for (final d in raw)
          if (d is Map) Dependent.fromJson(Map<String, dynamic>.from(d)),
      ];
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Dependent> saveDependent({
    String? id,
    required String fullName,
    required String dateOfBirth,
    required String gender,
    required String relationshipTag,
    required String criticalAllergiesMedicalHistory,
    String bloodGroup = 'unknown',
    List<String> knownMedicalConditions = const [],
    List<String> allergies = const [],
  }) async {
    final data = <String, dynamic>{
      'full_name': fullName,
      'date_of_birth': dateOfBirth,
      'gender': gender,
      'relationship_tag': relationshipTag,
      'blood_group': bloodGroup,
      'known_medical_conditions': knownMedicalConditions,
      'allergies': allergies,
      'critical_allergies_medical_history': criticalAllergiesMedicalHistory,
    };
    try {
      final res = id == null
          ? await _dio.post<Map<String, dynamic>>('/api/dependents', data: data)
          : await _dio.patch<Map<String, dynamic>>('/api/dependents/$id',
              data: data);
      final body = res.data ?? const <String, dynamic>{};
      return Dependent.fromJson(
          Map<String, dynamic>.from(body['dependent'] as Map? ?? body));
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> deleteDependent(String id) async {
    try {
      await _dio.delete('/api/dependents/$id');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // --- Profile endpoints ---------------------------------------------------

  /// `GET /patient/profile?account_id=...` — reads the `accounts` document
  /// for the signed-in patient. Backend strips `password_hash` server-side
  /// via the Account model's toJSON transform, so the wire shape is
  /// already safe to render directly.
  Future<PatientProfile> getPatientProfile(String accountId) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 250));
      return PatientProfile(
        id: accountId,
        fullName: 'Rumi Ahmed',
        email: 'patient@taafi.app',
        phone: '+8801710000001',
        status: 'active',
        createdAt: DateTime.now().subtract(const Duration(days: 120)),
      );
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/patient/profile',
        queryParameters: {'account_id': accountId},
      );
      return PatientProfile.fromJson(res.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `PATCH /patient/profile` — partial update via Mongoose
  /// `findByIdAndUpdate`. The backend whitelist (`pickPatientFields`)
  /// drops anything outside {full_name, email, phone}, so callers can
  /// safely pass a sparse map of only the fields the user actually
  /// edited. Returns the freshly saved row so the notifier can swap in
  /// the canonical server copy.
  Future<PatientProfile> updatePatientProfile(
    String accountId,
    Map<String, dynamic> updates,
  ) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 300));
      return PatientProfile(
        id: accountId,
        fullName: (updates['full_name'] ?? 'Rumi Ahmed').toString(),
        email: (updates['email'] ?? 'patient@taafi.app').toString(),
        phone: (updates['phone'] ?? '+8801710000001').toString(),
      );
    }
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/patient/profile',
        data: {'account_id': accountId, ...updates},
      );
      return PatientProfile.fromJson(res.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `GET /doctor/profile?doctor_id=...` — reads the `providers` row.
  Future<DoctorProfile> getDoctorProfile(String doctorId) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 250));
      return DoctorProfile(
        id: doctorId,
        fullName: 'Dr. Nafisa Rahman',
        email: 'doctor@taafi.app',
        phone: '+8801710000002',
        specialization: 'Internal medicine',
        specialty: 'Family medicine',
        yearsExperience: 8,
        fee: 1200,
        serviceRadiusKm: 7,
        rating: 4.8,
        reviewCount: 132,
        verificationStatus: 'verified',
        availabilityStatus: 'online',
      );
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/doctor/profile',
        queryParameters: {'doctor_id': doctorId},
      );
      return DoctorProfile.fromJson(res.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `GET /doctor/:id/stats` — earnings + visit rollup. Returned shape
  /// matches the Mongoose aggregation in `backend/src/routes/doctor.js`.
  /// Polled every 15 s by the Dashboard tab and invalidated immediately
  /// after the "Complete Visit" button fires so the money tile reflects
  /// the new earning without waiting for the next poll tick.
  Future<DoctorStats> getDoctorStats(String doctorId) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      // Mock branch returns the same numbers we paint elsewhere so the
      // offline-demo dashboard tells a consistent story.
      return const DoctorStats(
        todayEarnings: 1200,
        todayVisits: 1,
        weekEarnings: 8400,
        weekVisits: 7,
        rating: 4.8,
        reviewCount: 132,
      );
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/doctor/$doctorId/stats',
      );
      return DoctorStats.fromJson(res.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `GET /patient/requests/history?account_id=` — terminal-status
  /// requests (completed / cancelled / rejected), newest first. Backs
  /// the "Past requests" screen reached from the Patient Profile.
  Future<List<PatientHistoryItem>> getPatientHistory(String accountId) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 250));
      final now = DateTime.now();
      return [
        PatientHistoryItem(
          id: 'MT-9001',
          serviceName: 'Lab sample collection',
          doctorName: 'Dr. Nafisa Rahman',
          offeredBudget: 500,
          finalPrice: 600,
          status: 'completed',
          createdAt: now.subtract(const Duration(days: 3)),
          updatedAt: now.subtract(const Duration(days: 3)),
          locationText: 'House 42, Road 11A, Dhanmondi',
        ),
        PatientHistoryItem(
          id: 'MT-9000',
          serviceName: 'Post-surgery care',
          doctorName: 'Dr. Imran Hossain',
          offeredBudget: 1500,
          finalPrice: 1800,
          status: 'completed',
          createdAt: now.subtract(const Duration(days: 21)),
          updatedAt: now.subtract(const Duration(days: 20)),
          locationText: 'House 7, Banani',
        ),
      ];
    }
    try {
      final res = await _dio.get<List<dynamic>>(
        '/patient/requests/history',
        queryParameters: {'account_id': accountId},
      );
      final list = res.data ?? const [];
      final out = <PatientHistoryItem>[];
      for (final e in list) {
        try {
          out.add(PatientHistoryItem.fromJson(
              Map<String, dynamic>.from(e as Map)));
        } catch (err) {
          // Skip malformed rows; never blank the whole list over one bad doc.
          assert(() {
            debugPrint('[patient] skipped unparseable history row: $err');
            return true;
          }());
        }
      }
      return out;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // --- Doctor Operations Hub: patient records + medical vault --------------

  /// `GET /doctor/:doctorId/patients?search=` — patients this provider
  /// has treated, deduped from completed visits. Backs the Patient
  /// Records tab. `search` filters server-side by patient name.
  Future<List<DoctorPatient>> getDoctorPatients(
    String doctorId, {
    String? search,
  }) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 250));
      final now = DateTime.now();
      final all = [
        DoctorPatient(
          patientAccountId: 'mock-p1',
          name: 'Rumi Ahmed',
          phone: '+880 17XX-XXXX21',
          locationText: 'House 42, Road 11A, Dhanmondi',
          lastCareType: 'Post-surgery care',
          lastVisitAt: now.subtract(const Duration(days: 2)),
          visitCount: 3,
        ),
        DoctorPatient(
          patientAccountId: 'mock-p2',
          name: 'Hasan Ali',
          phone: '+880 18XX-XXXX05',
          locationText: 'Apt 8C, Gulshan 2',
          lastCareType: 'Wound dressing',
          lastVisitAt: now.subtract(const Duration(days: 9)),
          visitCount: 1,
        ),
      ];
      final q = (search ?? '').trim().toLowerCase();
      return q.isEmpty
          ? all
          : all.where((p) => p.name.toLowerCase().contains(q)).toList();
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/doctor/$doctorId/patients',
        queryParameters: {
          if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        },
      );
      final raw = (res.data ?? const {})['patients'];
      if (raw is! List) return const [];
      final out = <DoctorPatient>[];
      for (final p in raw) {
        if (p is Map) {
          out.add(DoctorPatient.fromJson(Map<String, dynamic>.from(p)));
        }
      }
      return out;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `GET /doctor/patients/:accountId/vault` — read a patient's medical
  /// vault for the Active Care Console grid.
  Future<PatientMedicalVault> getPatientMedicalVault(String accountId) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      return PatientMedicalVault(
        allergies: const ['Penicillin'],
        chronicConditions: const ['Type 2 diabetes', 'Hypertension'],
        bloodType: 'B+',
        emergencyNotes: 'Lives alone; notify daughter (+880 17XX-XXXX90).',
        updatedAt: DateTime.now().subtract(const Duration(days: 1)),
      );
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/doctor/patients/$accountId/vault',
      );
      final raw = (res.data ?? const {})['medical_vault'];
      if (raw is Map) {
        return PatientMedicalVault.fromJson(Map<String, dynamic>.from(raw));
      }
      return PatientMedicalVault.empty;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `PATCH /doctor/patients/:accountId/vault` — upsert vault fields.
  /// Only the provided keys are written; omitted keys are left intact.
  Future<PatientMedicalVault> updatePatientMedicalVault(
    String accountId, {
    List<String>? allergies,
    List<String>? chronicConditions,
    String? bloodType,
    String? emergencyNotes,
    String? updatedBy,
  }) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      return PatientMedicalVault(
        allergies: allergies ?? const [],
        chronicConditions: chronicConditions ?? const [],
        bloodType: bloodType ?? 'Unknown',
        emergencyNotes: emergencyNotes ?? '',
        updatedAt: DateTime.now(),
      );
    }
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/doctor/patients/$accountId/vault',
        data: {
          'allergies': ?allergies,
          'chronic_conditions': ?chronicConditions,
          'blood_type': ?bloodType,
          'emergency_notes': ?emergencyNotes,
          if (updatedBy != null && updatedBy.isNotEmpty) 'updated_by': updatedBy,
        },
      );
      final raw = (res.data ?? const {})['medical_vault'];
      if (raw is Map) {
        return PatientMedicalVault.fromJson(Map<String, dynamic>.from(raw));
      }
      return PatientMedicalVault.empty;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `GET /api/prescriptions/by-patient/:accountId` — every script issued
  /// to a patient, newest-first. Backs the Patient Records detail and the
  /// console's "past prescription history" disclosure.
  Future<List<Prescription>> getPrescriptionsForPatient(
    String accountId,
  ) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      return const [];
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/prescriptions/by-patient/$accountId',
      );
      final raw = (res.data ?? const {})['prescriptions'];
      if (raw is! List) return const [];
      final out = <Prescription>[];
      for (final p in raw) {
        if (p is Map) {
          try {
            out.add(Prescription.fromJson(Map<String, dynamic>.from(p)));
          } catch (_) {
            // Skip a malformed row rather than blanking the whole list.
          }
        }
      }
      return out;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `GET /api/prescriptions/:id` — single prescription, enriched with the
  /// issuing doctor's verified credentials (`doctor` block) + the originating
  /// visit's `symptoms`. Backs the patient prescription-vault detail card.
  Future<Prescription> getPrescriptionById(String id) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      throw Exception('Prescription unavailable in offline mode');
    }
    try {
      final res =
          await _dio.get<Map<String, dynamic>>('/api/prescriptions/$id');
      final body = res.data ?? const <String, dynamic>{};
      final raw = body['prescription'];
      if (raw is Map) {
        return Prescription.fromJson(Map<String, dynamic>.from(raw));
      }
      return Prescription.fromJson(body);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // --- Nurse/Doctor Operations Hub: history + vitals + completion ----------

  /// `GET /doctor/:providerId/history` — completed/terminal sessions this
  /// provider has delivered, newest-first. Backs the "Task History" tab.
  /// Full care_request docs are parsed by [PatientHistoryItem.fromJson].
  Future<List<PatientHistoryItem>> getProviderHistory(String providerId) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 250));
      final now = DateTime.now();
      return [
        PatientHistoryItem(
          id: 'mock-h1',
          serviceName: 'Nurse on call',
          doctorName: null,
          offeredBudget: 900,
          finalPrice: 1000,
          status: 'completed',
          createdAt: now.subtract(const Duration(days: 1)),
          updatedAt: now.subtract(const Duration(days: 1)),
          locationText: 'House 42, Dhanmondi',
        ),
        PatientHistoryItem(
          id: 'mock-h2',
          serviceName: 'Lab sample collection',
          doctorName: null,
          offeredBudget: 600,
          finalPrice: 600,
          status: 'completed',
          createdAt: now.subtract(const Duration(days: 5)),
          updatedAt: now.subtract(const Duration(days: 5)),
          locationText: 'Apt 8C, Gulshan 2',
        ),
      ];
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/doctor/$providerId/history',
      );
      final raw = (res.data ?? const {})['history'];
      if (raw is! List) return const [];
      final out = <PatientHistoryItem>[];
      for (final r in raw) {
        if (r is Map) {
          try {
            out.add(PatientHistoryItem.fromJson(Map<String, dynamic>.from(r)));
          } catch (_) {
            // Skip a malformed row rather than blanking the whole list.
          }
        }
      }
      return out;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `PATCH /api/appointments/:id/vitals` — mid-visit vitals save from the
  /// Nurse Procedural Terminal. Writes the readings without closing the
  /// visit so admin + future doctor consults see them immediately.
  Future<void> saveAppointmentVitals(
    String appointmentId, {
    String? bloodPressure,
    String? pulse,
    String? spo2,
    String? temperature,
    String? bloodSugar,
    List<String>? procedures,
  }) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      return;
    }
    try {
      await _dio.patch<Map<String, dynamic>>(
        '/api/appointments/$appointmentId/vitals',
        data: {
          'vitals': {
            'blood_pressure': ?bloodPressure,
            'pulse': ?pulse,
            'spo2': ?spo2,
            'temperature': ?temperature,
            'blood_sugar': ?bloodSugar,
          },
          'procedures': ?procedures,
        },
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `POST /api/appointments/:id/complete` — the Complete Care Session
  /// engine: persists the final vitals matrix + free-text summary,
  /// finishes the visit (parking it in the payment-due state unless the
  /// balance was already settled), and (server-side) emits the socket
  /// event that locks the live chat room. Returns the updated
  /// appointment document so the console can decide whether to offer
  /// cash collection (`status`, `final_price`, `deposit_amount`,
  /// `adjusted_discount`).
  Future<Map<String, dynamic>> completeAppointment(
    String appointmentId, {
    String? bloodPressure,
    String? pulse,
    String? spo2,
    String? temperature,
    String? bloodSugar,
    List<String>? procedures,
    String? summary,
  }) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 250));
      return {'id': appointmentId, 'status': 'completed'};
    }
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/appointments/$appointmentId/complete',
        data: {
          'vitals': {
            'blood_pressure': ?bloodPressure,
            'pulse': ?pulse,
            'spo2': ?spo2,
            'temperature': ?temperature,
            'blood_sugar': ?bloodSugar,
          },
          'procedures': ?procedures,
          'summary': ?summary,
        },
      );
      final body = res.data ?? const <String, dynamic>{};
      final appt = body['appointment'];
      if (appt is Map) return Map<String, dynamic>.from(appt);
      return body;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `POST /api/appointments/:id/collect-cash` — the assigned provider
  /// confirms receiving the outstanding balance in physical cash. The
  /// backend computes the amount server-side, closes the booking, flips
  /// the visit's prescriptions to PAID (admin release queue), and $incs
  /// the collector's `financial_ledger.cash_in_hand`. Response:
  /// `{success, amount, cashInHand, appointment}`.
  Future<Map<String, dynamic>> collectCashPayment(String appointmentId) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 300));
      return {'success': true, 'amount': 0, 'cashInHand': 0};
    }
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/appointments/$appointmentId/collect-cash',
      );
      return res.data ?? const <String, dynamic>{};
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `PATCH /api/appointments/:id/accept` — provider accepts an incoming
  /// dispatch; the visit shifts straight to `enroute` (On the Way).
  Future<void> acceptDispatch(String appointmentId) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      return;
    }
    try {
      await _dio.patch<Map<String, dynamic>>(
        '/api/appointments/$appointmentId/accept',
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `PATCH /api/appointments/:id/reject` — provider declines an incoming
  /// dispatch; it unassigns the caller and drops back to `approved`.
  Future<void> rejectDispatch(String appointmentId) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      return;
    }
    try {
      await _dio.patch<Map<String, dynamic>>(
        '/api/appointments/$appointmentId/reject',
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `GET /doctor/nurse-profile?account_id=` — the signed-in nurse's
  /// professional registry (identity + Provider fields).
  Future<NurseProfile> getNurseProfile(String accountId) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      return NurseProfile(
        id: accountId,
        fullName: 'Nurse Demo',
        nursingLicense: 'BNMC-00000',
        specialization: 'General Nursing',
        yearsExperience: 3,
        hospitalAffiliation: 'Dhaka Medical College Hospital',
        bio: 'Home-care nurse focused on post-surgical recovery.',
      );
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/doctor/nurse-profile',
        queryParameters: {'account_id': accountId},
      );
      return NurseProfile.fromJson(res.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `PATCH /doctor/nurse-profile` — save the nurse's professional
  /// credentials. Only the supplied fields are written.
  Future<NurseProfile> updateNurseProfile(
    String accountId, {
    String? nursingLicense,
    String? specialization,
    String? qualifications,
    int? yearsExperience,
    String? hospitalAffiliation,
    String? bio,
  }) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 250));
      return NurseProfile(
        id: accountId,
        fullName: 'Nurse Demo',
        nursingLicense: nursingLicense ?? '',
        specialization: specialization ?? '',
        qualifications: qualifications ?? '',
        yearsExperience: yearsExperience ?? 0,
        hospitalAffiliation: hospitalAffiliation ?? '',
        bio: bio ?? '',
      );
    }
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/doctor/nurse-profile',
        data: {
          'account_id': accountId,
          'nursing_license': ?nursingLicense,
          'specialization': ?specialization,
          'qualifications': ?qualifications,
          'years_experience': ?yearsExperience,
          'hospital_affiliation': ?hospitalAffiliation,
          'bio': ?bio,
        },
      );
      return NurseProfile.fromJson(res.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `PUT /api/users/:id/profile` — canonical "update my profile"
  /// surface. Accepts both camelCase and snake_case keys; the backend
  /// normalises in one pass. Response includes the updated `provider`
  /// (and `user`) row, so we re-parse from `provider` for the doctor
  /// case. Sends camelCase per the production spec.
  /// `GET /api/doctor/profile-status?doctor_id=` — drives the
  /// Complete-your-profile sheet. Returns the 5 booleans + percentage
  /// plus the underlying experience list and (masked) payout block.
  Future<ProfileCompletionStatus> getProfileStatus(String doctorId) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      return const ProfileCompletionStatus(
        hasPhoto: true,
        hasLicense: true,
        hasSpecialty: true,
        completionPercent: 60,
        itemsRemaining: 2,
      );
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/doctor/profile-status',
        queryParameters: {'doctor_id': doctorId},
      );
      return ProfileCompletionStatus.fromResponse(
          res.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `PUT /api/doctor/work-experience` — replaces the doctor's
  /// experience list with [entries]. The backend always returns the
  /// fresh status so we re-parse it in one round trip.
  Future<ProfileCompletionStatus> updateWorkExperience(
    String doctorId,
    List<DoctorExperience> entries,
  ) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 250));
      return ProfileCompletionStatus(
        hasPhoto: true,
        hasLicense: true,
        hasSpecialty: true,
        hasExperience: entries.isNotEmpty,
        completionPercent: entries.isNotEmpty ? 80 : 60,
        itemsRemaining: entries.isNotEmpty ? 1 : 2,
        experience: entries,
      );
    }
    try {
      final res = await _dio.put<Map<String, dynamic>>(
        '/api/doctor/work-experience',
        data: {
          'doctor_id': doctorId,
          'experience': entries.map((e) => e.toJson()).toList(),
        },
      );
      return ProfileCompletionStatus.fromResponse(
          res.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `PUT /api/doctor/payout-details` — upserts the bKash / Bank
  /// payout sub-doc. Sends the **plaintext** account number; the
  /// backend stores it and returns it masked in subsequent reads.
  Future<ProfileCompletionStatus> updatePayoutDetails({
    required String doctorId,
    required String method, // 'bKash' | 'Bank'
    required String accountNumber,
    String? accountName,
    String? bankName,
    String? branch,
  }) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 250));
      return ProfileCompletionStatus(
        hasPhoto: true,
        hasLicense: true,
        hasSpecialty: true,
        hasExperience: true,
        hasPayout: true,
        completionPercent: 100,
        itemsRemaining: 0,
        payout: DoctorPayoutDetails(
          method: method,
          accountNumberLast4: accountNumber.length <= 4
              ? accountNumber
              : accountNumber.substring(accountNumber.length - 4),
          accountName: accountName ?? '',
          bankName: bankName ?? '',
          branch: branch ?? '',
        ),
      );
    }
    try {
      final res = await _dio.put<Map<String, dynamic>>(
        '/api/doctor/payout-details',
        data: {
          'doctor_id': doctorId,
          'method': method,
          'accountNumber': accountNumber,
          if (accountName != null && accountName.isNotEmpty)
            'accountName': accountName,
          if (bankName != null && bankName.isNotEmpty) 'bankName': bankName,
          if (branch != null && branch.isNotEmpty) 'branch': branch,
        },
      );
      return ProfileCompletionStatus.fromResponse(
          res.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<DoctorProfile> updateProfessionalDetails(
    String userId,
    Map<String, dynamic> updates,
  ) async {
    if (_useMockMode) {
      return updateDoctorProfile(userId, updates);
    }
    try {
      final res = await _dio.put<Map<String, dynamic>>(
        '/api/users/$userId/profile',
        data: updates,
      );
      final body = res.data ?? const <String, dynamic>{};
      // Prefer the provider row (carries the professional fields).
      // Fall back to user (identity-only fields) so the caller still
      // gets a sensible Profile object even on an identity-only edit.
      final providerRaw = body['provider'] as Map<String, dynamic>?;
      final userRaw = body['user'] as Map<String, dynamic>?;
      return DoctorProfile.fromJson(providerRaw ?? userRaw ?? const {});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `PATCH /doctor/profile` — kept for back-compat with the existing
  /// `_EditDoctorSheet` call site. Same payload contract as the old
  /// endpoint (snake_case body, doctor_id in the body). New call sites
  /// should prefer [updateProfessionalDetails].
  Future<DoctorProfile> updateDoctorProfile(
    String doctorId,
    Map<String, dynamic> updates,
  ) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 300));
      // Mock branch echoes the patch on top of a baseline so the dev loop
      // sees the update without a backend round trip.
      final base = await getDoctorProfile(doctorId);
      return base.copyWith(
        fullName: updates['full_name']?.toString(),
        email: updates['email']?.toString(),
        phone: updates['phone']?.toString(),
        specialization: updates['specialization']?.toString(),
        specialty: updates['specialty']?.toString(),
        yearsExperience: (updates['years_experience'] as num?)?.toInt(),
        fee: updates['fee'] as num?,
        serviceRadiusKm: updates['service_radius_km'] as num?,
        bio: updates['bio']?.toString(),
        hospitalAffiliation: updates['hospital_affiliation']?.toString(),
        isVerifiedDoctor: updates['is_verified_doctor'] as bool?,
      );
    }
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/doctor/profile',
        data: {'doctor_id': doctorId, ...updates},
      );
      return DoctorProfile.fromJson(res.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> markNotificationRead(String notificationId) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      return;
    }
    try {
      await _dio.patch('/doctor/notifications/$notificationId/read');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> updateServiceStatus(String serviceId, String status) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      return;
    }
    try {
      await _dio.patch('/doctor/services/$serviceId/status',
          data: {'status': status});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // Mock dashboard state ------------------------------------------------------
  PendingAssignment? _mockPendingAssignment = PendingAssignment(
    id: 'assign_001',
    serviceNameEn: 'Post-surgery care',
    serviceNameBn: 'অস্ত্রোপচার পরবর্তী সেবা',
    fee: 2400,
    duration: '2 hr',
    patientName: 'Rumi Ahmed',
    patientAgeSex: '62F',
    patientCondition: 'Gallbladder post-op',
    address: 'House 42, Road 11A, Dhanmondi',
    distanceKm: 3.4,
    driveMinutes: 12,
    expiresAt: DateTime.now().add(const Duration(seconds: 47)),
    tags: ['With helper Shahana', 'Wound dressing', 'Discharge attached'],
  );

  DoctorDashboard _mockDoctorDashboard() {
    final online = _prefs?.getBool(_availabilityKey) ?? true;
    final now = DateTime.now();
    final base = DateTime(now.year, now.month, now.day);
    return DoctorDashboard(
      todayEarnings: 4800,
      todayVisits: 3,
      weekEarnings: 24600,
      weekVisits: 14,
      rating: 4.93,
      reviewCount: 127,
      unreadCount: 3,
      profileCompleteness: 80,
      availability: online,
      latestReview: const LatestReview(
        rating: 5,
        text: 'Very caring and professional. Followed up on my recovery daily.',
        patientName: 'Sadia K.',
      ),
      reviews: [
        DoctorReview(
          id: 'rev_001',
          rating: 5,
          text:
              'Very caring and professional. Followed up on my recovery daily.',
          patientName: 'Sadia K.',
          createdAt: now.subtract(const Duration(days: 2)),
          serviceTag: 'Post-surgery care',
        ),
        DoctorReview(
          id: 'rev_002',
          rating: 5,
          text:
              'Arrived on time and explained every step. Made my mother feel at ease.',
          patientName: 'Rumi A.',
          createdAt: now.subtract(const Duration(days: 5)),
          serviceTag: 'Wound dressing',
        ),
        DoctorReview(
          id: 'rev_003',
          rating: 4,
          text:
              'Helpful and patient. Will book again for our regular check-ins.',
          patientName: 'Hasan M.',
          createdAt: now.subtract(const Duration(days: 9)),
          serviceTag: 'Post-op vitals',
        ),
        DoctorReview(
          id: 'rev_004',
          rating: 5,
          text:
              'Highly recommend — bedside manner is excellent and clinically sharp.',
          patientName: 'Tania K.',
          createdAt: now.subtract(const Duration(days: 14)),
          serviceTag: 'Elderly care',
        ),
      ],
      pendingAssignment: _mockPendingAssignment,
      // Seeded "today" plus any visits the admin has assigned this session.
      // Sorted ascending so the next-up visit is always on top.
      upcomingToday: [
        UpcomingAppointment(
          id: 'apt_001',
          startTime: base.add(const Duration(hours: 17)),
          patientName: 'Mr. Hasan Ali, 68M',
          serviceName: 'Wound dressing',
          fee: 1200,
          distanceKm: 1.2,
        ),
        UpcomingAppointment(
          id: 'apt_002',
          startTime: base.add(const Duration(hours: 19, minutes: 30)),
          patientName: 'Ms. Tania, 34F',
          serviceName: 'Post-op vitals',
          fee: 900,
          distanceKm: 4.8,
        ),
        ..._mockExtraUpcoming,
      ]..sort((a, b) => a.startTime.compareTo(b.startTime)),
    );
  }

  /// Visits appended via [assignTeam] this session. Merged into the
  /// `upcomingToday` list returned by [_mockDoctorDashboard] so the doctor
  /// dashboard renders newly-assigned work the next time it refetches.
  final List<UpcomingAppointment> _mockExtraUpcoming = [];

  // Mock patient state -------------------------------------------------------
  bool _patientMockSeeded = false;
  PatientActiveRequest? _mockPatientActiveRequest;
  final List<RecentProvider> _mockRecentProviders = [];
  final List<PatientNotification> _mockPatientNotifications = [];

  void _ensurePatientMockSeeded() {
    if (_patientMockSeeded) return;
    _patientMockSeeded = true;

    final now = DateTime.now();

    _mockPatientActiveRequest = PatientActiveRequest(
      id: 'MT-4827',
      serviceTitleEn: 'Post-surgery care',
      serviceTitleBn: 'অস্ত্রোপচার পরবর্তী সেবা',
      status: PatientRequestStatus.pendingReview,
      locationLabel: 'House 42, Road 11A, Dhanmondi',
      requestedAt: now.subtract(const Duration(minutes: 6)),
      scheduledAt: now.add(const Duration(hours: 1)),
      reviewEtaMinutes: 5,
      durationHours: 2,
      offer: 3500,
      updatedAt: now.subtract(const Duration(minutes: 2)),
    );

    _mockRecentProviders.addAll([
      RecentProvider(
        id: 'doc_001',
        name: 'Dr. Nafisa Rahman',
        specialization: 'General Surgery',
        yearsExperience: 8,
        rating: 4.9,
        reviewCount: 127,
        avatarUrl: null,
        lastVisitAt: now.subtract(const Duration(days: 12)),
      ),
      RecentProvider(
        id: 'doc_002',
        name: 'Dr. Kamrul Hasan',
        specialization: 'Orthopedics',
        yearsExperience: 12,
        rating: 4.8,
        reviewCount: 184,
        avatarUrl: null,
        lastVisitAt: now.subtract(const Duration(days: 34)),
      ),
      RecentProvider(
        id: 'doc_003',
        name: 'Dr. Sumaiya Akter',
        specialization: 'Internal Medicine',
        yearsExperience: 6,
        rating: 4.7,
        reviewCount: 92,
        avatarUrl: null,
        lastVisitAt: now.subtract(const Duration(days: 58)),
      ),
    ]);

    _mockPatientNotifications.addAll([
      PatientNotification(
        id: 'ntf_001',
        kind: PatientNotificationKind.request,
        titleEn: 'Request received',
        titleBn: 'আবেদন গৃহীত',
        bodyEn: 'Our medical admin is matching you with a qualified doctor.',
        bodyBn: 'একজন উপযুক্ত ডাক্তারের সাথে আপনাকে যুক্ত করা হচ্ছে।',
        createdAt: now.subtract(const Duration(minutes: 4)),
        read: false,
        payload: const {'requestId': 'MT-4827'},
      ),
      PatientNotification(
        id: 'ntf_002',
        kind: PatientNotificationKind.system,
        titleEn: 'New service available',
        titleBn: 'নতুন সেবা',
        bodyEn: 'Home physiotherapy is now available in your area.',
        createdAt: now.subtract(const Duration(hours: 5)),
        read: false,
      ),
      PatientNotification(
        id: 'ntf_003',
        kind: PatientNotificationKind.provider,
        titleEn: 'Dr. Nafisa shared a follow-up note',
        bodyEn:
            'Continue the prescribed antibiotics and keep the wound dry for 48 hours.',
        createdAt: now.subtract(const Duration(days: 2, hours: 3)),
        read: true,
        payload: const {'providerId': 'doc_001'},
      ),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Admin endpoints
  // ═══════════════════════════════════════════════════════════════════════════

  bool _adminMockSeeded = false;
  AdminKpi? _mockAdminKpi;
  List<ActivityEvent> _mockActivityFeed = [];
  List<AdminCareRequest> _mockAdminRequests = [];
  List<AvailableDoctor> _mockDoctors = [];
  List<AvailableHelper> _mockHelpers = [];
  List<LiveServiceUpdate> _mockLiveServices = [];

  void _ensureAdminMockSeeded() {
    if (_adminMockSeeded) return;
    _adminMockSeeded = true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    _mockAdminKpi = const AdminKpi(
      activeServices: 4,
      pendingApprovals: 7,
      emergencyAlerts: 1,
      dailyRevenue: 48200,
      revenueDelta: 12.4,
      totalDoctorsOnDuty: 18,
      doctorsInService: 4,
    );

    _mockActivityFeed = [
      ActivityEvent(id: 'ev1', message: 'Dr. Nafisa reached Rumi Ahmed\'s home (MT-4827)', timestamp: now.subtract(const Duration(minutes: 3)), eventType: ActivityEventType.arrival, requestId: 'MT-4827'),
      ActivityEvent(id: 'ev2', message: 'Dr. Kamrul assigned to MT-4830 (Wound dressing)', timestamp: now.subtract(const Duration(minutes: 8)), eventType: ActivityEventType.assignment, requestId: 'MT-4830'),
      ActivityEvent(id: 'ev3', message: 'Emergency request from Mirpur — MT-4835', timestamp: now.subtract(const Duration(minutes: 14)), eventType: ActivityEventType.emergency, requestId: 'MT-4835'),
      ActivityEvent(id: 'ev4', message: 'Service MT-4820 completed — Dr. Sumaiya', timestamp: now.subtract(const Duration(minutes: 22)), eventType: ActivityEventType.completion, requestId: 'MT-4820'),
      ActivityEvent(id: 'ev5', message: 'New request MT-4831 pending review', timestamp: now.subtract(const Duration(minutes: 31)), eventType: ActivityEventType.system, requestId: 'MT-4831'),
      ActivityEvent(id: 'ev6', message: 'Dr. Anika went online — Gulshan area', timestamp: now.subtract(const Duration(minutes: 45)), eventType: ActivityEventType.system),
      ActivityEvent(id: 'ev7', message: 'Dr. Shafiq completed MT-4818 — Mirpur', timestamp: now.subtract(const Duration(hours: 1, minutes: 10)), eventType: ActivityEventType.completion, requestId: 'MT-4818'),
      ActivityEvent(id: 'ev8', message: 'System: 3 new requests overnight', timestamp: now.subtract(const Duration(hours: 2)), eventType: ActivityEventType.system),
    ];

    _mockAdminRequests = [
      AdminCareRequest(id: 'MT-4827', patientId: 'p001', patientName: 'Rumi Ahmed', patientAge: 62, patientGender: 'F', serviceType: ServiceType.postSurgery, serviceName: 'Post-surgery care', location: 'House 42, Rd 11A, Dhanmondi', area: 'Dhanmondi', latitude: 23.7465, longitude: 90.3760, durationHours: 2, asap: false, scheduledTime: now.add(const Duration(hours: 1)), status: 'pending', createdAt: now.subtract(const Duration(minutes: 4)), urgencyLevel: UrgencyLevel.medium, surgeryDetails: 'Gallbladder removal — Day 3 post-op', patientHistory: 'Type 2 diabetes, hypertension. Gallbladder surgery on Saturday.', patientOffer: 3500, adjustedPrice: 3500, marketPriceMin: 3200, marketPriceMax: 4500, notes: 'Needs wound dressing change and mobility help.', phone: '+880 17XX-XXXX21'),
      AdminCareRequest(id: 'MT-4830', patientId: 'p002', patientName: 'Hasan Ali', patientAge: 68, patientGender: 'M', serviceType: ServiceType.woundDressing, serviceName: 'Wound dressing', location: 'Apt 8C, Gulshan 2', area: 'Gulshan', durationHours: 1, status: 'pending', createdAt: now.subtract(const Duration(minutes: 11)), urgencyLevel: UrgencyLevel.high, surgeryDetails: 'Knee replacement — Day 7', patientHistory: 'Chronic arthritis, post-knee-replacement.', patientOffer: 1000, adjustedPrice: 1200, marketPriceMin: 1000, marketPriceMax: 1800, notes: 'Wound infection risk — needs urgent attention.', phone: '+880 18XX-XXXX05'),
      AdminCareRequest(id: 'MT-4829', patientId: 'p003', patientName: 'Tania Akter', patientAge: 34, patientGender: 'F', serviceType: ServiceType.vitalsCheck, serviceName: 'Post-op vitals', location: 'Sector 7, Uttara', area: 'Uttara', durationHours: 1, status: 'pending', createdAt: now.subtract(const Duration(minutes: 18)), urgencyLevel: UrgencyLevel.low, patientOffer: 800, adjustedPrice: 900, marketPriceMin: 700, marketPriceMax: 1200, phone: '+880 19XX-XXXX12'),
      AdminCareRequest(id: 'MT-4828', patientId: 'p004', patientName: 'Md. Reza', patientAge: 55, patientGender: 'M', serviceType: ServiceType.postSurgery, serviceName: 'Post-surgery care', location: 'Block C, Mirpur 10', area: 'Mirpur', durationHours: 3, status: 'pending', createdAt: now.subtract(const Duration(minutes: 22)), urgencyLevel: UrgencyLevel.high, surgeryDetails: 'Appendectomy — Day 2', patientHistory: 'No major comorbidities.', patientOffer: 2800, adjustedPrice: 3200, marketPriceMin: 2800, marketPriceMax: 4000, notes: 'Diabetic - monitor blood sugar.', phone: '+880 17XX-XXXX33'),
      AdminCareRequest(id: 'MT-4835', patientId: 'p009', patientName: 'Farhan Kabir', patientAge: 45, patientGender: 'M', serviceType: ServiceType.postSurgery, serviceName: 'Post-surgery care', location: 'Pallabi, Mirpur', area: 'Mirpur', durationHours: 2, asap: true, status: 'pending', createdAt: now.subtract(const Duration(minutes: 14)), urgencyLevel: UrgencyLevel.critical, surgeryDetails: 'Heart bypass — Day 5', patientHistory: 'Cardiac patient, high-risk.', patientOffer: 5000, adjustedPrice: 5500, marketPriceMin: 4500, marketPriceMax: 7000, notes: 'EMERGENCY — chest pain reported.', phone: '+880 16XX-XXXX44'),
      AdminCareRequest(id: 'MT-4831', patientId: 'p005', patientName: 'Nusrat Jahan', patientAge: 41, patientGender: 'F', serviceType: ServiceType.postSurgery, serviceName: 'Post-surgery care', location: 'Rd 27, Banani', area: 'Banani', durationHours: 2, status: 'pending', createdAt: now.subtract(const Duration(minutes: 31)), urgencyLevel: UrgencyLevel.medium, patientOffer: 4200, adjustedPrice: 4200, marketPriceMin: 3800, marketPriceMax: 5000, phone: '+880 18XX-XXXX07'),
      AdminCareRequest(id: 'MT-4832', patientId: 'p006', patientName: 'Rafiq Uddin', patientAge: 70, patientGender: 'M', serviceType: ServiceType.elderlyCare, serviceName: 'Elderly care', location: 'Mohammadpur', area: 'Mohammadpur', durationHours: 4, status: 'pending', createdAt: now.subtract(const Duration(minutes: 38)), urgencyLevel: UrgencyLevel.medium, patientOffer: 3000, adjustedPrice: 3200, marketPriceMin: 2500, marketPriceMax: 4000, phone: '+880 17XX-XXXX55'),
      AdminCareRequest(id: 'MT-4826', patientId: 'p007', patientName: 'Nusrat J.', patientAge: 41, patientGender: 'F', serviceType: ServiceType.postSurgery, serviceName: 'Post-surgery care', location: 'Banani DOHS', area: 'Banani', durationHours: 2, status: 'approved', createdAt: now.subtract(const Duration(minutes: 34)), assignedDoctorId: 'doc_001', assignedDoctorName: 'Dr. Nafisa Rahman', patientOffer: 4200, adjustedPrice: 4200, marketPriceMin: 3800, marketPriceMax: 5000),
      AdminCareRequest(id: 'MT-4825', patientId: 'p008', patientName: 'Karim U.', patientAge: 72, patientGender: 'M', serviceType: ServiceType.woundDressing, serviceName: 'Wound dressing', location: 'Dhanmondi 15', area: 'Dhanmondi', durationHours: 1, status: 'approved', createdAt: now.subtract(const Duration(minutes: 41)), assignedDoctorId: 'doc_002', assignedDoctorName: 'Dr. Kamrul Hasan', patientOffer: 1100, adjustedPrice: 1100, marketPriceMin: 900, marketPriceMax: 1500),
    ];

    _mockDoctors = [
      AvailableDoctor(id: 'doc_001', name: 'Dr. Nafisa Rahman', specialization: 'General Surgery', yearsExperience: 8, rating: 4.93, reviewCount: 127, distanceKm: 3.4, fee: 2400, upcomingAppointments: [TimeSlot(start: today.add(const Duration(hours: 17)), end: today.add(const Duration(hours: 18)), label: 'Mr. Hasan Ali — Wound dressing')]),
      AvailableDoctor(id: 'doc_002', name: 'Dr. Kamrul Hasan', specialization: 'Orthopedics', yearsExperience: 12, rating: 4.87, reviewCount: 184, distanceKm: 5.1, fee: 2600, upcomingAppointments: [TimeSlot(start: today.add(const Duration(hours: 10)), end: today.add(const Duration(hours: 12)), label: 'Scheduled surgery follow-up')]),
      AvailableDoctor(id: 'doc_003', name: 'Dr. Anika Chowdhury', specialization: 'Internal Medicine', yearsExperience: 6, rating: 4.81, reviewCount: 92, distanceKm: 6.8, fee: 2200),
      AvailableDoctor(id: 'doc_004', name: 'Dr. Shafiq Islam', specialization: 'General Surgery', yearsExperience: 10, rating: 4.76, reviewCount: 156, distanceKm: 8.2, fee: 2500),
      AvailableDoctor(id: 'doc_005', name: 'Dr. Sumaiya Akter', specialization: 'Internal Medicine', yearsExperience: 6, rating: 4.72, reviewCount: 92, distanceKm: 9.5, fee: 2100),
    ];

    _mockHelpers = [
      const AvailableHelper(id: 'hlp_001', name: 'Shahana Begum', specialty: 'Nursing aide', yearsExperience: 5, fee: 900),
      const AvailableHelper(id: 'hlp_002', name: 'Rina Khatun', specialty: 'Nursing aide', yearsExperience: 3, fee: 800),
      const AvailableHelper(id: 'hlp_003', name: 'Fatema Akter', specialty: 'Patient care', yearsExperience: 4, fee: 850),
    ];

    _mockLiveServices = [
      const LiveServiceUpdate(
        id: 'MT-4827',
        patientName: 'Rumi Ahmed',
        doctorName: 'Dr. Nafisa R.',
        area: 'Dhanmondi',
        status: LiveServiceStatus.inService,
        progressPercent: 0.75,
        elapsedMinutes: 45,
        totalMinutes: 60,
        latitude: 23.7465,
        longitude: 90.3760,
      ),
      const LiveServiceUpdate(
        id: 'MT-4830',
        patientName: 'Hasan Ali',
        doctorName: 'Dr. Kamrul H.',
        area: 'Gulshan',
        status: LiveServiceStatus.onTheWay,
        progressPercent: 0.40,
        elapsedMinutes: 8,
        totalMinutes: 12,
        latitude: 23.7925,
        longitude: 90.4078,
      ),
      const LiveServiceUpdate(
        id: 'MT-4831',
        patientName: 'Tania Akter',
        doctorName: 'Dr. Anika C.',
        area: 'Uttara',
        status: LiveServiceStatus.arrived,
        progressPercent: 0,
        elapsedMinutes: 22,
        totalMinutes: 60,
        latitude: 23.8728,
        longitude: 90.3984,
      ),
      const LiveServiceUpdate(
        id: 'MT-4832',
        patientName: 'Md. Reza',
        doctorName: 'Dr. Shafiq I.',
        area: 'Mirpur',
        status: LiveServiceStatus.onTheWay,
        progressPercent: 0.20,
        elapsedMinutes: 3,
        totalMinutes: 15,
        latitude: 23.8223,
        longitude: 90.3654,
      ),
    ];
  }

  /// Returns the latest live-service snapshot. In mock mode adds a tiny jitter
  /// to `elapsedMinutes` so consecutive refreshes feel alive without changing
  /// the visible status of each row.
  Future<List<LiveServiceUpdate>> getLiveServices() async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 280));
      _ensureAdminMockSeeded();
      final rng = DateTime.now().millisecondsSinceEpoch;
      _mockLiveServices = [
        for (final s in _mockLiveServices)
          s.copyWith(
            elapsedMinutes: (s.elapsedMinutes + ((rng + s.id.hashCode) % 2))
                .clamp(0, s.totalMinutes + 10),
            progressPercent:
                s.status == LiveServiceStatus.arrived ? 0 : s.progressPercent,
          ),
      ];
      return List.unmodifiable(_mockLiveServices);
    }
    try {
      final response = await _dio.get('/api/admin/live-services');
      return (response.data as List)
          .map((e) => LiveServiceUpdate(
                id: (e['id'] ?? '').toString(),
                patientName: (e['patientName'] ?? '').toString(),
                doctorName: (e['doctorName'] ?? '').toString(),
                area: (e['area'] ?? '').toString(),
                status: _parseLiveStatus(e['status']?.toString()),
                progressPercent:
                    ((e['progressPercent'] as num?) ?? 0).toDouble(),
                elapsedMinutes: (e['elapsedMinutes'] as int?) ?? 0,
                totalMinutes: (e['totalMinutes'] as int?) ?? 0,
                latitude: (e['latitude'] as num?)?.toDouble(),
                longitude: (e['longitude'] as num?)?.toDouble(),
              ))
          .toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  static LiveServiceStatus _parseLiveStatus(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'arrived':
        return LiveServiceStatus.arrived;
      case 'in_service':
      case 'inservice':
        return LiveServiceStatus.inService;
      case 'on_the_way':
      case 'ontheway':
      default:
        return LiveServiceStatus.onTheWay;
    }
  }

  /// `GET /admin/chart-data` — 7-day approved/declined rollup for the
  /// Overview BarChart. Always returns 7 points (zero-filled days), so
  /// the chart never re-renders a different bar count between polls.
  Future<AdminChartData> getAdminChartData() async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      // Mock seven days of plausible approved/declined values so the
      // offline-demo dashboard still draws a believable chart.
      return AdminChartData(series: [
        for (var i = 0; i < 7; i++)
          AdminChartPoint(
            date: '2026-05-${(24 + i).toString().padLeft(2, '0')}',
            label: const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][i],
            approved: [4, 7, 6, 8, 7, 10, 9][i],
            declined: [1, 3, 1, 2, 2, 3, 2][i],
            total: [5, 10, 7, 10, 9, 13, 11][i],
          ),
      ]);
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>('/admin/chart-data');
      return AdminChartData.fromJson(res.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `GET /admin/patients` — accounts where `role: 'user'`. Powers the
  /// new Patients sidebar screen. Per-row try/catch so one bad doc
  /// doesn't blank the whole table.
  Future<List<User>> getAdminPatients() async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      return const [
        User(
          id: 'patient_001',
          name: 'Rumi Ahmed',
          email: 'patient@taafi.app',
          phone: '+8801710000001',
          role: UserRole.patient,
        ),
      ];
    }
    try {
      final res = await _dio.get<List<dynamic>>('/admin/patients');
      final list = res.data ?? const [];
      final out = <User>[];
      for (final e in list) {
        try {
          out.add(User.fromJson(Map<String, dynamic>.from(e as Map)));
        } catch (err) {
          assert(() {
            debugPrint('[admin] skipped unparseable patient: $err');
            return true;
          }());
        }
      }
      return out;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `GET /api/admin/patients/:id` — a single patient's clinical drill-down
  /// (account + medical vault + full care-request history).
  Future<AdminPatientDetail> getAdminPatientDetail(String patientId) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      return const AdminPatientDetail(
        patient: User(
          id: 'patient_001',
          name: 'Rumi Ahmed',
          email: 'patient@taafi.app',
          phone: '+8801710000001',
          role: UserRole.patient,
        ),
        vault: PatientMedicalVault.empty,
        careRequests: [],
      );
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/admin/patients/$patientId',
      );
      return AdminPatientDetail.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `GET /admin/providers` — full provider list (doctors + helpers).
  Future<List<DoctorProfile>> getAdminProviders() async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      return [await getDoctorProfile('doctor_001')];
    }
    try {
      final res = await _dio.get<List<dynamic>>('/admin/providers');
      final list = res.data ?? const [];
      final out = <DoctorProfile>[];
      for (final e in list) {
        try {
          out.add(DoctorProfile.fromJson(Map<String, dynamic>.from(e as Map)));
        } catch (err) {
          assert(() {
            debugPrint('[admin] skipped unparseable provider: $err');
            return true;
          }());
        }
      }
      return out;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `GET /admin/billing` — completed care_requests with final_price,
  /// reusing the existing snake_case parser so the table row shape
  /// matches the Review Queue's [AdminCareRequest].
  /// `GET /admin/billing` — completed settlements, optionally scoped to a
  /// `[startDate, endDate]` window (the backend makes the end inclusive of
  /// the whole day). Dates are sent as `yyyy-MM-dd` ISO strings.
  Future<List<AdminCareRequest>> getAdminBilling({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      _ensureAdminMockSeeded();
      return _mockAdminRequests.where((r) {
        if (r.status != 'completed') return false;
        if (startDate != null && r.createdAt.isBefore(startDate)) return false;
        if (endDate != null &&
            r.createdAt.isAfter(endDate.add(const Duration(days: 1)))) {
          return false;
        }
        return true;
      }).toList(growable: false);
    }
    try {
      final res = await _dio.get<List<dynamic>>(
        '/admin/billing',
        queryParameters: {
          if (startDate != null) 'startDate': iso(startDate),
          if (endDate != null) 'endDate': iso(endDate),
        },
      );
      final list = res.data ?? const [];
      final out = <AdminCareRequest>[];
      for (final e in list) {
        try {
          out.add(adminCareRequestFromMongo(
              Map<String, dynamic>.from(e as Map)));
        } catch (err) {
          assert(() {
            debugPrint('[admin] skipped unparseable billing row: $err');
            return true;
          }());
        }
      }
      return out;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<AdminKpi> getAdminKpi() async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 350));
      _ensureAdminMockSeeded();
      return _mockAdminKpi!;
    }
    try {
      final response = await _dio.get('/admin/dashboard');
      return AdminKpi.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `GET /api/admin/dashboard-telemetry` — real-time operations telemetry
  /// computed server-side via a single `$facet` aggregation. Backs the
  /// Overview metric cards' live polling. Same [AdminKpi] shape as
  /// [getAdminKpi] so the cards parse it without a new model.
  Future<AdminKpi> getDashboardTelemetry() async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 350));
      _ensureAdminMockSeeded();
      return _mockAdminKpi!;
    }
    try {
      final response = await _dio.get('/api/admin/dashboard-telemetry');
      return AdminKpi.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `PATCH /api/admin/providers/:id/verify` — flip a provider's
  /// verification status (pending ⇄ verified). Returns the updated
  /// [DoctorProfile] so the caller can reflect the new state immediately.
  Future<DoctorProfile> toggleProviderVerification(String providerId) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      final list = await getAdminProviders();
      final match = list.where((p) => p.id == providerId);
      final base = match.isEmpty ? null : match.first;
      return (base ?? const DoctorProfile(id: '', fullName: '', email: '', phone: ''))
          .copyWith(
        verificationStatus:
            (base?.verificationStatus == 'verified') ? 'pending' : 'verified',
      );
    }
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/api/admin/providers/$providerId/verify',
      );
      final body = res.data ?? const <String, dynamic>{};
      final raw = body['provider'];
      if (raw is Map) {
        return DoctorProfile.fromJson(Map<String, dynamic>.from(raw));
      }
      return DoctorProfile.fromJson(body);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `POST /api/admin/register-sub-admin` — root-admin-only creation of a
  /// secondary admin account. Throws on any non-2xx so the form surfaces
  /// the server's validation/conflict message.
  Future<void> registerSubAdmin({
    required String name,
    required String email,
    required String password,
    String? phone,
  }) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 300));
      return;
    }
    try {
      await _dio.post<Map<String, dynamic>>(
        '/api/admin/register-sub-admin',
        data: {
          'name': name,
          'email': email,
          'password': password,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
        },
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `GET /api/admin/finance/cash-in-hand` — every doctor/nurse currently
  /// holding un-remitted physical cash plus the field-wide rollups the
  /// Cash Clearance terminal's summary cards render.
  Future<CashInHandSummary> getCashInHand() async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      return const CashInHandSummary(
        providers: [
          ProviderCashLedgerEntry(
            accountId: 'doctor_001',
            name: 'Dr. Rumi Ahmed',
            role: 'doctor',
            phone: '+8801710000001',
            cashInHand: 1500,
          ),
          ProviderCashLedgerEntry(
            accountId: 'nurse_001',
            name: 'Nurse Karim',
            role: 'nurse',
            phone: '+8801710000002',
            cashInHand: 900,
          ),
        ],
        totalCashInField: 2400,
        collectedToday: 0,
        outstandingProvidersCount: 2,
      );
    }
    try {
      final res =
          await _dio.get<Map<String, dynamic>>('/api/admin/finance/cash-in-hand');
      return CashInHandSummary.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `POST /api/admin/finance/settle-provider-cash` — record a physical cash
  /// handover and zero the provider's `cash_in_hand` ledger. Throws on any
  /// non-2xx (e.g. 409 when the ledger changed mid-settlement) so the modal
  /// surfaces the server message.
  Future<CashSettlementResult> settleProviderCash({
    required String providerId,
    required double amountCollected,
    String? adminNotes,
  }) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 250));
      return CashSettlementResult(
        receiptId: 'RCPT-MOCK-${DateTime.now().millisecondsSinceEpoch}',
        providerId: providerId,
        amountCollected: amountCollected,
        expectedAmount: amountCollected,
        discrepancy: 0,
      );
    }
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/admin/finance/settle-provider-cash',
        data: {
          'providerId': providerId,
          'amountCollected': amountCollected,
          if (adminNotes != null && adminNotes.isNotEmpty)
            'adminNotes': adminNotes,
        },
      );
      return CashSettlementResult.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `GET /api/admin/finance/payouts` — the provider withdrawal queue plus
  /// the pending rollups the console's summary cards and sidebar badge use.
  /// `status` accepts PENDING (default), APPROVED, REJECTED, or all.
  Future<PayoutQueue> getPayoutRequests({String status = 'PENDING'}) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 200));
      return PayoutQueue(
        items: [
          PayoutRequestModel(
            id: 'payout_001',
            providerAccountId: 'doctor_001',
            providerName: 'Dr. Rumi Ahmed',
            providerRole: 'doctor',
            providerPhone: '+8801710000001',
            amount: 3500,
            method: 'bKash',
            accountNumber: '01710000001',
            status: 'PENDING',
            requestedAt: DateTime.now().subtract(const Duration(hours: 5)),
          ),
          PayoutRequestModel(
            id: 'payout_002',
            providerAccountId: 'nurse_001',
            providerName: 'Nurse Karim',
            providerRole: 'nurse',
            providerPhone: '+8801710000002',
            amount: 1200,
            method: 'Nagad',
            accountNumber: '01710000002',
            status: 'PENDING',
            requestedAt: DateTime.now().subtract(const Duration(days: 1)),
          ),
        ],
        pendingCount: 2,
        pendingTotal: 4700,
      );
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/admin/finance/payouts',
        queryParameters: {'status': status},
      );
      return PayoutQueue.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `POST /api/admin/finance/payouts/:id/approve` — mark a withdrawal paid.
  /// `referenceId` is the bank/MFS transaction reference and is required
  /// server-side so every payout is auditable. Throws on 409 (already
  /// actioned) so the modal can surface the reason.
  Future<PayoutRequestModel> approvePayout({
    required String payoutId,
    required String referenceId,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/admin/finance/payouts/$payoutId/approve',
        data: {'referenceId': referenceId},
      );
      final raw = (res.data ?? const {})['payoutRequest'];
      return PayoutRequestModel.fromJson(
        raw is Map ? Map<String, dynamic>.from(raw) : const {},
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `POST /api/admin/finance/payouts/:id/reject` — decline a withdrawal and
  /// return the held funds to the provider's available balance. The reason is
  /// required and is shown to the provider.
  Future<PayoutRequestModel> rejectPayout({
    required String payoutId,
    required String reason,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/admin/finance/payouts/$payoutId/reject',
        data: {'reason': reason},
      );
      final raw = (res.data ?? const {})['payoutRequest'];
      return PayoutRequestModel.fromJson(
        raw is Map ? Map<String, dynamic>.from(raw) : const {},
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `GET /api/admin/settings` — the global platform-configuration document.
  Future<AdminSettings> getAdminSettings() async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 150));
      return AdminSettings.empty;
    }
    try {
      final res =
          await _dio.get<Map<String, dynamic>>('/api/admin/settings');
      final raw = res.data?['settings'];
      return AdminSettings.fromJson(
        raw is Map ? Map<String, dynamic>.from(raw) : const {},
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `PUT /api/admin/settings` — persist the whole settings document. Returns
  /// the server's canonical copy.
  Future<AdminSettings> updateAdminSettings(AdminSettings settings) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 150));
      return settings;
    }
    try {
      final res = await _dio.put<Map<String, dynamic>>(
        '/api/admin/settings',
        data: settings.toUpdateJson(),
      );
      final raw = res.data?['settings'];
      return AdminSettings.fromJson(
        raw is Map ? Map<String, dynamic>.from(raw) : const {},
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<ActivityEvent>> getActivityFeed() async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 250));
      _ensureAdminMockSeeded();
      return List.unmodifiable(_mockActivityFeed);
    }
    try {
      final response = await _dio.get('/admin/activity');
      return (response.data as List).map((e) => ActivityEvent.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<AdminCareRequest>> getAdminCareRequests() async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 400));
      _ensureAdminMockSeeded();
      return List.unmodifiable(_mockAdminRequests);
    }
    try {
      final response = await _dio.get<List<dynamic>>('/admin/requests');
      final list = response.data ?? const [];
      // Snake_case Mongo documents. The parser normalizes
      // `status: "submitted"` → `"pending"` so the existing admin filter
      // chips and count provider keep working unchanged.
      //
      // Per-row isolation: one malformed care_requests document must never
      // blank the entire admin queue. Bad rows are skipped + logged, the
      // rest render.
      final out = <AdminCareRequest>[];
      for (final e in list) {
        try {
          out.add(adminCareRequestFromMongo(Map<String, dynamic>.from(e as Map)));
        } catch (err) {
          assert(() {
            debugPrint('[admin] skipped unparseable care_request: $err');
            return true;
          }());
        }
      }
      return out;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<AvailableDoctor>> getAvailableDoctors(String requestId) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 300));
      _ensureAdminMockSeeded();
      return List.unmodifiable(_mockDoctors);
    }
    try {
      final response =
          await _dio.get<List<dynamic>>('/admin/requests/$requestId/doctors');
      final list = response.data ?? const [];
      // `providers` collection docs (snake_case, full_name, availability_status)
      // enriched server-side with per-request match metadata.
      return list
          .map((e) =>
              providerToDoctorFromMongo(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `GET /admin/requests/:id/nurses` — verified + online nurses.
  Future<List<AvailableNurse>> getAvailableNurses(String requestId) async {
    try {
      final response =
          await _dio.get<List<dynamic>>('/admin/requests/$requestId/nurses');
      final list = response.data ?? const [];
      return list
          .map((e) =>
              providerToNurseFromMongo(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// `GET /admin/requests/:id/team-pool` — segregated doctor / nurse
  /// rosters in a single response, so the Assign Team dual-list
  /// renders without firing two roundtrips. Falls back to a graceful
  /// per-role fetch if either array is missing on the wire.
  Future<TeamPool> getTeamPool(String requestId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/admin/requests/$requestId/team-pool',
      );
      final body = response.data ?? const <String, dynamic>{};
      List<T> parseList<T>(
        dynamic raw,
        T Function(Map<String, dynamic>) parser,
      ) {
        if (raw is! List) return const [];
        final out = <T>[];
        for (final e in raw) {
          if (e is Map) {
            try {
              out.add(parser(Map<String, dynamic>.from(e)));
            } catch (_) {
              // Drop a malformed row, keep the rest of the pool.
            }
          }
        }
        return out;
      }

      return TeamPool(
        doctors: parseList(body['doctors'], providerToDoctorFromMongo),
        nurses: parseList(body['nurses'], providerToNurseFromMongo),
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<AvailableHelper>> getAvailableHelpers(String requestId) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 250));
      _ensureAdminMockSeeded();
      return List.unmodifiable(_mockHelpers);
    }
    try {
      final response =
          await _dio.get<List<dynamic>>('/admin/requests/$requestId/helpers');
      final list = response.data ?? const [];
      return list
          .map((e) =>
              providerToHelperFromMongo(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> assignTeam(
    String requestId,
    String? doctorId, {
    String? doctorName,
    String? nurseId,
    String? nurseName,
    String? helperId,
    String? helperName,
    double? finalPrice,
  }) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 500));
      _ensureAdminMockSeeded();
      final idx = _mockAdminRequests.indexWhere((r) => r.id == requestId);
      if (idx != -1) {
        final doc = _mockDoctors.firstWhere((d) => d.id == doctorId);
        final req = _mockAdminRequests[idx];
        _mockAdminRequests[idx] = req.copyWith(
          status: 'approved',
          assignedDoctorId: doctorId,
          assignedDoctorName: doc.name,
          assignedHelperId: helperId,
          assignedHelperName: helperId != null
              ? _mockHelpers.firstWhere((h) => h.id == helperId).name
              : null,
        );

        // ── Cross-role fan-out (Admin → Doctor) ──────────────────────────
        // Append the just-assigned visit to the doctor's upcoming list so
        // the dashboard materializes it on next refetch. Scheduled time
        // falls back to "in 1 hour" when the request was ASAP.
        final start =
            req.scheduledTime ?? DateTime.now().add(const Duration(hours: 1));
        final age = req.patientAge > 0
            ? ', ${req.patientAge}${req.patientGender ?? ''}'
            : '';
        _mockExtraUpcoming.add(
          UpcomingAppointment(
            id: 'apt_${req.id}',
            startTime: start,
            patientName: '${req.patientName}$age',
            serviceName: req.serviceName,
            fee: req.adjustedPrice ?? req.patientOffer,
            distanceKm: doc.distanceKm,
            address: req.location,
          ),
        );

        // Activity feed entry so admin sees the assignment fire.
        _mockActivityFeed.insert(
          0,
          ActivityEvent(
            id: 'ev_assign_${DateTime.now().millisecondsSinceEpoch}',
            message: '${doc.name} assigned to ${req.id} (${req.serviceName})',
            timestamp: DateTime.now(),
            eventType: ActivityEventType.assignment,
            requestId: req.id,
          ),
        );
      }
      return;
    }
    try {
      // Snake_case payload — exact contract of POST /admin/requests/:id/assign.
      // (`doctor_id` is required by the backend; the previous `doctorId`
      // camelCase caused the "doctor_id is required" 400.)
      // Null-aware map entries (`?value`) omit the key entirely if the
      // value is null, so the backend doesn't see `"helper_id": null`.
      await _dio.post('/admin/requests/$requestId/assign', data: {
        'doctor_id': ?doctorId,
        'doctor_name': ?doctorName,
        'nurse_id': ?nurseId,
        'nurse_name': ?nurseName,
        'helper_id': ?helperId,
        'helper_name': ?helperName,
        'final_price': ?finalPrice,
      });
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> bulkUpdateRequestStatus(List<String> ids, String status) async {
    if (_useMockMode) {
      await Future.delayed(const Duration(milliseconds: 400));
      _ensureAdminMockSeeded();
      for (final id in ids) {
        final idx = _mockAdminRequests.indexWhere((r) => r.id == id);
        if (idx != -1) {
          _mockAdminRequests[idx] = _mockAdminRequests[idx].copyWith(status: status);
        }
      }
      return;
    }
    try {
      await _dio.post('/admin/requests/bulk-status', data: {
        'ids': ids,
        'status': status,
      });
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Turns a [DioException] into a human-readable, UI-friendly string.
  /// Every login/network failure flows through here, so unclear messages
  /// like "errno = 111" or "Connection failed" become actionable copy that
  /// a user can react to. Also writes a one-line diagnostic to the debug
  /// console so the underlying cause is never lost.
  /// Auth-specific wrapper around [_handleError]. Keeps the exact same
  /// message-resolution ladder (server `message` → status fallback →
  /// transport copy) but boxes the result in an [AuthException] carrying
  /// the machine-readable `error_code` the login screen branches on.
  ///
  /// Only the sign-in endpoints use this; every other call site keeps
  /// throwing the plain string from [_handleError].
  AuthException _authError(DioException error) {
    final body = error.response?.data;
    String? codeOf(String key) {
      if (body is Map && body[key] is String) {
        final raw = (body[key] as String).trim();
        if (raw.isNotEmpty) return raw;
      }
      return null;
    }

    return AuthException(
      _handleError(error),
      statusCode: error.response?.statusCode,
      errorCode: codeOf('error_code'),
      phone: codeOf('phone'),
    );
  }

  String _handleError(DioException error) {
    final status = error.response?.statusCode;
    final url = error.requestOptions.uri.toString();
    final type = error.type;

    // Diagnostic line — visible in `flutter run`'s VS Code Debug Console.
    debugPrint(
        '⚠️  [DioClient] ${type.name} on $url'
        '${status == null ? '' : ' (status=$status)'} :: ${error.message}');

    // 1. Server returned a structured error → trust its `message` verbatim.
    // We used to override 401s with a hardcoded "Invalid email or password"
    // string, which masked the new spec-required "Invalid phone number or
    // password" copy from `/auth/login`. Pass-through is the right move:
    // the backend already crafts each message for its specific failure.
    final body = error.response?.data;
    if (body is Map && body['message'] is String) {
      final raw = (body['message'] as String).trim();
      if (raw.isNotEmpty) return raw;
    }

    // 2. Status-code based fallbacks for responses with no body.
    if (status == 401) {
      return 'Incorrect mobile number or password. Please try again.';
    }
    if (status == 403) return 'Account is inactive or not allowed.';
    if (status == 404) return 'Server endpoint not found (${error.requestOptions.path}).';
    if (status != null && status >= 500) {
      return 'Server error ($status). Check the backend logs.';
    }

    // 3. No response — connection/network class failures.
    switch (type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out. Is the backend running at $_baseUrl?';
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return 'Cannot reach the server at $_baseUrl. Is it running? '
            '(start the backend with `npm run dev` in backend/)';
      case DioExceptionType.badCertificate:
        return 'TLS / certificate error talking to $_baseUrl.';
      case DioExceptionType.cancel:
        return 'Request was cancelled.';
      case DioExceptionType.badResponse:
        return 'Unexpected response from server.';
    }
  }

  /// Best-effort mapping from a free-text service title (as set by the patient
  /// catalog) to the admin-side [ServiceType] enum. Falls through to
  /// `postSurgery` when no keyword matches so the row still renders.
  static ServiceType _inferServiceTypeFromTitle(String title) {
    final t = title.toLowerCase();
    if (t.contains('wound') || t.contains('dressing')) {
      return ServiceType.woundDressing;
    }
    if (t.contains('vital') || t.contains('check')) {
      return ServiceType.vitalsCheck;
    }
    if (t.contains('elder') || t.contains('care')) {
      return ServiceType.elderlyCare;
    }
    return ServiceType.postSurgery;
  }
}
