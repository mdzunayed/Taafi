import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/config/support_config.dart';
import '../../../core/models/user.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../auth_flow_provider.dart';
import '../auth_provider.dart';
import 'auth_widgets.dart';

class WelcomeBackScreen extends ConsumerStatefulWidget {
  const WelcomeBackScreen({super.key});

  @override
  ConsumerState<WelcomeBackScreen> createState() => _WelcomeBackScreenState();
}

/// Top-level segment for the login surface. Cleanly separates the
/// public self-registering [patient] role from the privileged
/// [staff] roles (doctor / nurse / admin) — provisioned via the
/// admin console, never self-served. The `Sign Up as a Patient` CTA
/// at the bottom of the card is gated on this; flipping to `staff`
/// strips the sign-up wrapper from the widget tree entirely.
enum _AuthStage { patient, staff }

class _WelcomeBackScreenState extends ConsumerState<WelcomeBackScreen> {
  final _formKey = GlobalKey<FormState>();
  // Phone-first sign-in. The field still accepts an email so existing
  // admin/doctor demo creds keep working — DioClient.login routes on
  // the `@` character.
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  _AuthStage _stage = _AuthStage.patient;
  UserRole _role = UserRole.patient;

  /// Last login failure surfaced inline above the form so the message
  /// stays visible even after the SnackBar dismisses. Cleared at the
  /// start of every fresh attempt and whenever the user edits a field.
  ///
  /// The text is always server-authored (or, for the Google path, a
  /// locally-composed string); [_loginErrorCause] carries the typed
  /// exception when there is one so the fields know whether to go red.
  String? _loginError;

  /// Typed cause behind [_loginError], when the failure came from
  /// `/auth/login`. Null for the Google path and for transport errors.
  AuthException? _loginErrorCause;

  /// Only a *credentials* rejection implicates what the user typed. A
  /// wrong-tab 403 or a deactivated account means the phone/password
  /// were fine, so leaving those fields red would be a lie.
  bool get _credentialFieldsRejected =>
      _loginErrorCause?.isCredentialFailure ?? false;

  /// True while the Google native consent flow is mid-flight. Drives
  /// the spinner inside the "Continue with Google" button.
  bool _googleBusy = false;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  void _clearLoginError() {
    if (_loginError == null && _loginErrorCause == null) return;
    setState(() {
      _loginError = null;
      _loginErrorCause = null;
    });
    // Retract the SnackBar too — otherwise it hangs around on its own 6s
    // timer after the banner and the red borders have already gone,
    // still accusing input the user has since corrected.
    ScaffoldMessenger.of(context).clearSnackBars();
  }

  /// Flip the segmented toggle. Snaps `_role` back to the right
  /// default for the new stage so a user who left "Admin" selected in
  /// the staff panel and then bounced to "Patient" doesn't keep
  /// holding the privileged role state. The first staff sub-chip
  /// (Doctor) is the staff default — the spec calls Doctor out as
  /// the most common privileged sign-in.
  void _setStage(_AuthStage next) {
    if (_stage == next) return;
    setState(() {
      _stage = next;
      _role = next == _AuthStage.patient
          ? UserRole.patient
          : UserRole.doctor;
    });
    _clearLoginError();
  }

  void _setStaffRole(UserRole role) {
    if (_role == role) return;
    setState(() => _role = role);
    _clearLoginError();
  }

  /// Surfaces a failure in BOTH places so it can't be missed: the
  /// persistent red banner above the form and a red floating SnackBar.
  /// [cause] is the typed exception when one exists — it decides whether
  /// the credential fields also go red.
  void _showLoginError(String message, {AuthException? cause}) {
    if (!mounted) return;
    setState(() {
      _loginError = message;
      _loginErrorCause = cause;
    });
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: MtColors.rejected,
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _signIn() async {
    // Loading defense — bail if a request is already in flight so the
    // keyboard "done" action + button tap can't double-submit.
    if (ref.read(authFlowProvider).isLoading) return;
    _clearLoginError();
    if (!(_formKey.currentState?.validate() ?? false)) {
      // Mechanical warning when a credential block fails validation.
      HapticFeedback.vibrate();
      return;
    }
    HapticFeedback.lightImpact();
    try {
      final ok = await ref.read(authFlowProvider.notifier).signIn(
            identifier: _identifier.text,
            password: _password.text,
            role: _role,
          );
      if (!mounted) return;
      if (!ok) {
        final flow = ref.read(authFlowProvider);
        final cause = flow.authError;

        // Registered but never confirmed the OTP — that's a resumable
        // state, not a failure. Hand them the OTP screen (seeded with the
        // phone the server has on file) instead of a dead-end banner.
        if (cause != null && cause.requiresVerification) {
          ref.read(authFlowProvider.notifier).prepareVerification(
                phone: cause.phone ?? _identifier.text.trim(),
                password: _password.text,
              );
          context.push('/otp-verify');
          return;
        }

        // Everything else: show the server's message verbatim. The
        // backend authors copy per failure mode (bad credentials, wrong
        // tab, deactivated account), so rewriting it here would only
        // lose information.
        _showLoginError(
          cause?.message ??
              flow.error ??
              'Sign-in failed. Please try again.',
          cause: cause,
        );
        return;
      }
      // GoRouter's redirect picks the user's role-specific home now that
      // the session is in state.
      final user = ref.read(authTokenProvider).valueOrNull?.user;
      if (user == null) {
        // We're already on /login — re-navigating here used to be the one
        // remaining silent dead-end. Tell the user what went wrong instead.
        _showLoginError(
            'Sign-in completed but no profile was returned. Please try again.');
        return;
      }
      context.go(routeForUser(user));
    } catch (e) {
      // Defensive — the notifier resolves to `false` rather than throwing,
      // but a transport/parse error must never crash the form silently.
      if (!mounted) return;
      _showLoginError(
        _friendlyError(e),
        cause: e is AuthException ? e : null,
      );
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_googleBusy) return;
    HapticFeedback.lightImpact();
    _clearLoginError();
    setState(() => _googleBusy = true);
    try {
      // The web platform infers the OAuth client ID from the
      // `<meta name="google-signin-client_id">` tag in web/index.html.
      // If that tag isn't set, signIn() throws a clear PlatformException
      // we catch + surface to the user with actionable copy.
      final google = GoogleSignIn(scopes: const ['email', 'profile']);
      final account = await google.signIn();
      if (account == null) {
        // User cancelled the consent dialog — not an error, just bail.
        return;
      }
      await ref.read(authTokenProvider.notifier).loginWithGoogle(
            email: account.email,
            googleId: account.id,
            fullName: account.displayName ?? account.email.split('@').first,
            photoUrl: account.photoUrl ?? '',
            role: _role,
          );
      if (!mounted) return;
      final state = ref.read(authTokenProvider);
      final err = state.whenOrNull(error: (e, _) => e);
      if (err != null) {
        _showLoginError(_friendlyError(err));
        return;
      }
      final user = ref.read(currentUserProvider);
      if (user == null) {
        _showLoginError('Google sign-in completed but no profile was returned.');
        return;
      }
      context.go(routeForUser(user));
    } catch (e) {
      // Most common cause on Chrome: missing OAuth client ID config.
      // Surface a clear next step rather than a raw PlatformException.
      _showLoginError(_friendlyGoogleError(e));
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    return s.startsWith('Exception: ') ? s.substring(11) : s;
  }

  String _friendlyGoogleError(Object e) {
    final msg = _friendlyError(e);
    // Detect the "OAuth client ID not configured" failure mode and
    // give the user something actionable instead of a stack trace.
    if (msg.contains('ClientID') ||
        msg.contains('client_id') ||
        msg.contains('idpiframe_initialization_failed') ||
        msg.contains('not initialized')) {
      return 'Google Sign-In is not configured yet — add your OAuth client ID to web/index.html.';
    }
    return 'Google sign-in failed: $msg';
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authFlowProvider).isLoading;
    return Scaffold(
      backgroundColor: MtColors.brandSofter,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: ConstrainedBox(
              // 480 px card cap per the desktop/web safety spec —
              // wider monitors stop stretching the card edge-to-edge.
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    // Brand header — official Taafi logo with the Bangla
                    // tagline directly beneath it.
                    Column(
                      children: [
                        Image.asset(
                          'assets/logo/taafi-logo.png',
                          height: 112,
                          fit: BoxFit.contain,
                          // If the asset ever fails to load, fall back to
                          // the hand-painted badge so the header never blanks.
                          errorBuilder: (_, _, _) =>
                              const HeartPulseBadge(size: 96),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          kBrandTaglineBn,
                          textAlign: TextAlign.center,
                          style: MtTextStyles.bodyMd.copyWith(
                            color: MtColors.ink2,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Persistent error banner — pairs with the SnackBar
                    // surfacing from `_showLoginError`. Visible until
                    // dismissed OR the user edits the form. Ensures a
                    // failed login can't fail silently even if the
                    // SnackBar is missed.
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeIn,
                        // Fade + a short slide down from above the form, so
                        // the banner reads as arriving rather than popping.
                        transitionBuilder: (child, animation) =>
                            FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, -0.25),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: _loginError == null
                            ? const SizedBox(
                                key: ValueKey('no-login-error'),
                                width: double.infinity,
                                height: 0,
                              )
                            : Padding(
                                // Keyed on the message so a *different*
                                // failure re-runs the entrance animation.
                                key: ValueKey('login-error:$_loginError'),
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _LoginErrorBanner(
                                  message: _loginError!,
                                  onDismiss: _clearLoginError,
                                ),
                              ),
                      ),
                    ),
                    // Two-stage role gate. The primary segment
                    // separates the public "Patient" surface from the
                    // privileged "Staff / Other" surface — only the
                    // staff stage exposes the doctor/nurse/admin sub-
                    // chip row, and only the patient stage shows the
                    // sign-up CTA at the bottom of the card. The
                    // chosen role is what /api/auth/login uses for
                    // the role-aware lookup; backend 403s on
                    // mismatch.
                    const _FieldLabel('Sign in as'),
                    const SizedBox(height: 8),
                    _PrimarySegment(
                      stage: _stage,
                      onChanged: _setStage,
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: _stage == _AuthStage.staff
                            ? Padding(
                                key: const ValueKey('staff-chips'),
                                padding:
                                    const EdgeInsets.fromLTRB(0, 12, 0, 0),
                                child: _StaffSubChips(
                                  selected: _role,
                                  onChanged: _setStaffRole,
                                ),
                              )
                            : const SizedBox(
                                key: ValueKey('no-staff-chips'),
                                height: 0,
                                width: double.infinity,
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const _FieldLabel('Phone Number'),
                    const SizedBox(height: 8),
                    AuthTextField(
                      controller: _identifier,
                      hint: '+1 (555) 000-0000',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      // Server said these credentials are wrong — the
                      // validators can't catch that, so flag both fields
                      // here. Cleared on the next keystroke below.
                      hasError: _credentialFieldsRejected,
                      // Phone-only — email is fully purged from the
                      // sign-in surface per the production spec. Only
                      // digits, `+`, spaces, hyphens and parens get
                      // through to the controller.
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-()\s]')),
                      ],
                      autofillHints: const [AutofillHints.telephoneNumber],
                      onChanged: (_) => _clearLoginError(),
                      validator: (v) {
                        final value = (v ?? '').trim();
                        if (value.isEmpty) return 'Phone number is required';
                        final digits = value.replaceAll(RegExp(r'\D'), '');
                        if (digits.length < 7) {
                          return 'Enter a valid phone number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const _FieldLabel('Password'),
                        TextButton(
                          onPressed: () {
                            // Carry the phone they've already typed
                            // (if any) so the reset screen pre-fills it.
                            final phone = _identifier.text.trim();
                            context.push(
                              '/forgot-password',
                              extra: phone.isEmpty ? null : phone,
                            );
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: MtColors.brand,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'Forgot?',
                            style: MtTextStyles.labelMd
                                .copyWith(color: MtColors.brand),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AuthTextField(
                      controller: _password,
                      hint: '••••••••',
                      icon: Icons.lock_outline,
                      obscureText: _obscure,
                      hasError: _credentialFieldsRejected,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => _clearLoginError(),
                      onFieldSubmitted: (_) => _signIn(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: MtColors.ink3,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      validator: (v) {
                        if ((v ?? '').isEmpty) return 'Password is required';
                        if (v!.length < 4) return 'Password is too short';
                        return null;
                      },
                    ),
                    const SizedBox(height: 22),
                    PrimaryAuthButton(
                      label: 'Sign In',
                      isLoading: isLoading,
                      onPressed: _signIn,
                    ),
                    const SizedBox(height: 28),
                    const _OrDivider(),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _SocialButton(
                            label: 'Google',
                            icon: _GoogleGlyph(),
                            isLoading: _googleBusy,
                            onTap: _googleBusy ? null : _signInWithGoogle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SocialButton(
                            label: 'Apple',
                            icon: const Icon(Icons.apple,
                                size: 18, color: MtColors.ink),
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Apple sign-in coming soon')),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    // Sign-up CTAs are PATIENT-ONLY. The moment the
                    // user flips to the Staff / Other stage, both the
                    // inline RichText link and the explicit Sign Up
                    // button are stripped from the widget tree entirely
                    // — admin / doctor / nurse accounts are minted via
                    // the Admin console, never self-served.
                    if (_stage == _AuthStage.patient) ...[
                      const SizedBox(height: 28),
                      // Single, unclickable prompt sitting directly above the
                      // sign-up button — the redundant inline link is gone, so
                      // the outlined button below is the solitary gateway to
                      // registration.
                      Center(
                        child: Text(
                          "Don't have an account?",
                          style: MtTextStyles.bodyMd
                              .copyWith(color: Colors.grey.shade600),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          context.push('/sign-up');
                        },
                        icon: const Icon(Icons.person_add_alt_1_outlined,
                            size: 18, color: MtColors.brand),
                        label: Text(
                          'Sign Up as a Patient',
                          style: MtTextStyles.labelLg.copyWith(
                            color: MtColors.brand,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: MtColors.brand),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 24),
                      const _StaffOnlyNotice(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: MtTextStyles.labelMd
          .copyWith(color: MtColors.ink, fontWeight: FontWeight.w600),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: MtColors.line, thickness: 1)),
        const SizedBox(width: 12),
        Text(
          'OR CONTINUE WITH',
          style: MtTextStyles.labelSm.copyWith(
            color: MtColors.ink3,
            letterSpacing: 1.2,
            fontSize: 10,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(child: Divider(color: MtColors.line, thickness: 1)),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String label;
  final Widget icon;
  /// Nullable so the parent can pass `null` to disable the button
  /// while a sign-in attempt is in flight.
  final VoidCallback? onTap;
  final bool isLoading;
  const _SocialButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: isLoading ? null : onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: MtColors.ink,
        side: const BorderSide(color: MtColors.line),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        // Light shadow matches the Material Google-button guideline.
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.12),
      ),
      child: isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: MtColors.ink2,
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                icon,
                const SizedBox(width: 8),
                Text(
                  label,
                  style: MtTextStyles.labelLg.copyWith(
                    color: MtColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
    );
  }
}

/// Persistent error banner shown above the form on a failed sign-in.
/// Pairs with the red SnackBar from `_showLoginError` — even if the
/// SnackBar dismisses, the cause stays visible until the user dismisses
/// the banner or edits a field.
class _LoginErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _LoginErrorBanner({
    required this.message,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2), // rejected-bg
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MtColors.rejected.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline,
              color: MtColors.rejected, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: MtTextStyles.bodyMd.copyWith(
                color: MtColors.rejected,
                height: 1.35,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close,
                color: MtColors.rejected, size: 18),
            tooltip: 'Dismiss',
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

/// Premium two-option segmented control: `Patient` (public) vs.
/// `Staff / Other` (admin-provisioned). Brand-orange pill slides under
/// the active option; the inactive side stays muted. Keyboard /
/// screen-reader friendly because each side is a real `InkWell`.
class _PrimarySegment extends StatelessWidget {
  final _AuthStage stage;
  final ValueChanged<_AuthStage> onChanged;
  const _PrimarySegment({required this.stage, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MtColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentTile(
              icon: Icons.favorite_border,
              label: 'Patient',
              active: stage == _AuthStage.patient,
              onTap: () => onChanged(_AuthStage.patient),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _SegmentTile(
              icon: Icons.medical_information_outlined,
              label: 'Staff / Other',
              active: stage == _AuthStage.staff,
              onTap: () => onChanged(_AuthStage.staff),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SegmentTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? MtColors.brand : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: active ? Colors.white : MtColors.ink2,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: MtTextStyles.labelMd.copyWith(
                  color: active ? Colors.white : MtColors.ink2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal staff sub-role row — Doctor / Nurse / Admin — revealed
/// only when the primary segment is on `Staff / Other`. Active chip
/// uses the brand deep-orange token; inactive chips stay neutral so
/// the active selection reads clearly.
class _StaffSubChips extends StatelessWidget {
  final UserRole selected;
  final ValueChanged<UserRole> onChanged;
  const _StaffSubChips({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StaffChip(
            label: 'Doctor',
            icon: Icons.medical_services_outlined,
            active: selected == UserRole.doctor,
            onTap: () => onChanged(UserRole.doctor),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StaffChip(
            label: 'Nurse',
            icon: Icons.medical_information_outlined,
            active: selected == UserRole.nurse,
            onTap: () => onChanged(UserRole.nurse),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StaffChip(
            label: 'Admin',
            icon: Icons.shield_outlined,
            active: selected == UserRole.admin,
            onTap: () => onChanged(UserRole.admin),
          ),
        ),
      ],
    );
  }
}

class _StaffChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _StaffChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? MtColors.brandSoft : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? MtColors.brand : MtColors.line,
              width: active ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: active ? MtColors.brand : MtColors.ink2,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: MtTextStyles.labelSm.copyWith(
                  color: active ? MtColors.brand : MtColors.ink2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reassuring notice that replaces the sign-up CTA when the user is on
/// the Staff / Other stage. Reinforces that staff accounts are minted
/// by an admin so the user knows where to look instead of hunting for
/// a missing sign-up button.
class _StaffOnlyNotice extends StatelessWidget {
  const _StaffOnlyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: MtColors.brandSofter,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.brandSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined,
              size: 18, color: MtColors.brand),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Staff accounts are provisioned by your Taafi administrator. Reach out to your admin if you need access.',
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact "G" badge that stands in for the Google logo without adding a
/// font package. Renders as a filled circle with the iconic G in white.
class _GoogleGlyph extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFF4285F4),
        shape: BoxShape.circle,
      ),
      child: const Text(
        'G',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}
