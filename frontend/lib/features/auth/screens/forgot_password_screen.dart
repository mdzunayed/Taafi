import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../auth_provider.dart';
import 'auth_widgets.dart';

/// Forgot-password flow. One screen, three fields:
///   1. Phone Number — the account being recovered.
///   2. 6-digit OTP boxes — currently pinned to the dev code `222222`.
///   3. New Password (+ confirmation) — bcrypt-hashed server-side.
///
/// On success the backend issues a fresh JWT, [DioClient] persists the
/// session, and we hydrate [authTokenProvider] so the router redirect
/// drops the user straight into their role-specific home — they don't
/// have to log in again with the password they just set.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  /// Pre-fill the phone from the Welcome Back screen so the user
  /// doesn't have to retype it after tapping "Forgot?".
  final String? initialPhone;

  const ForgotPasswordScreen({super.key, this.initialPhone});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  static const _otpLength = 6;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phone;
  late final TextEditingController _password;
  late final TextEditingController _confirmPassword;
  final List<TextEditingController> _otpCtrls =
      List.generate(_otpLength, (_) => TextEditingController());
  final List<FocusNode> _otpNodes =
      List.generate(_otpLength, (_) => FocusNode());

  bool _obscure = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _phone = TextEditingController(text: widget.initialPhone ?? '');
    _password = TextEditingController();
    _confirmPassword = TextEditingController();
    // Auto-focus the first OTP box once the phone is pre-filled so the
    // user can start typing the code immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (widget.initialPhone ?? '').isNotEmpty) {
        _otpNodes.first.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    for (final c in _otpCtrls) {
      c.dispose();
    }
    for (final n in _otpNodes) {
      n.dispose();
    }
    super.dispose();
  }

  String get _otpCode => _otpCtrls.map((c) => c.text).join();

  void _onOtpChanged(int index, String value) {
    if (value.isEmpty) {
      // Backspace from an empty box → jump to the previous one so the
      // user can scrub left without lifting fingers.
      if (index > 0) _otpNodes[index - 1].requestFocus();
      setState(() {});
      return;
    }
    // Paste / autofill spread: framework may hand us many digits at once.
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (var i = 0; i < _otpLength; i++) {
        _otpCtrls[i].text = i < digits.length ? digits[i] : '';
      }
      _otpNodes[(digits.length - 1).clamp(0, _otpLength - 1)]
          .requestFocus();
      setState(() {});
      return;
    }
    if (index < _otpLength - 1) {
      _otpNodes[index + 1].requestFocus();
    } else {
      _otpNodes[index].unfocus();
    }
    setState(() {});
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_otpCode.length != _otpLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Enter the 6-digit verification code'),
          backgroundColor: MtColors.rejected,
        ),
      );
      return;
    }
    if (_password.text != _confirmPassword.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Passwords do not match'),
          backgroundColor: MtColors.rejected,
        ),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final token = await ref.read(dioClientProvider).resetPassword(
            phone: _phone.text,
            otp: _otpCode,
            newPassword: _password.text,
          );
      ref.read(authTokenProvider.notifier).hydrate(token);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset — you are signed in.'),
          backgroundColor: MtColors.completed,
        ),
      );
      context.go(routeForUser(token.user));
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().startsWith('Exception: ')
          ? e.toString().substring(11)
          : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: MtColors.rejected),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MtColors.brandSofter,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TopBar(
                      onBack: () => Navigator.of(context).maybePop(),
                      onClose: () =>
                          Navigator.of(context).popUntil((r) => r.isFirst),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Reset Password',
                      style: MtTextStyles.h1.copyWith(
                        color: MtColors.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 30,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter your phone number and the 6-digit verification code we sent. For dev testing, the code is 222222.',
                      style: MtTextStyles.bodyMd.copyWith(
                        color: MtColors.ink2,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const _Label('Phone Number'),
                    const SizedBox(height: 8),
                    AuthTextField(
                      controller: _phone,
                      hint: '+1 (555) 000-0000',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9+\-()\s]'),
                        ),
                      ],
                      autofillHints: const [AutofillHints.telephoneNumber],
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
                    const SizedBox(height: 20),
                    const _Label('Verification Code'),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _otpLength; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          _OtpBox(
                            controller: _otpCtrls[i],
                            focusNode: _otpNodes[i],
                            onChanged: (v) => _onOtpChanged(i, v),
                            onBackspace: () {
                              if (_otpCtrls[i].text.isEmpty && i > 0) {
                                _otpNodes[i - 1].requestFocus();
                                _otpCtrls[i - 1].clear();
                                setState(() {});
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),
                    const _Label('New Password'),
                    const SizedBox(height: 8),
                    AuthTextField(
                      controller: _password,
                      hint: 'At least 6 characters',
                      icon: Icons.lock_outline,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: MtColors.ink3,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      validator: (v) {
                        final value = v ?? '';
                        if (value.isEmpty) return 'Password is required';
                        if (value.length < 6) return 'Use at least 6 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    const _Label('Confirm New Password'),
                    const SizedBox(height: 8),
                    AuthTextField(
                      controller: _confirmPassword,
                      hint: 'Re-enter the new password',
                      icon: Icons.lock_outline,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      validator: (v) {
                        if ((v ?? '').isEmpty) {
                          return 'Confirm the new password';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    PrimaryAuthButton(
                      label: 'Reset Password',
                      trailingIcon: Icons.lock_reset_outlined,
                      isLoading: _busy,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton(
                        onPressed: () => context.go('/login'),
                        style: TextButton.styleFrom(
                          foregroundColor: MtColors.brand,
                        ),
                        child: Text(
                          'Back to sign in',
                          style: MtTextStyles.labelMd
                              .copyWith(color: MtColors.brand),
                        ),
                      ),
                    ),
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

// ---------------------------------------------------------------------------
// Small private widgets — kept local because forgot-password is the only
// screen that uses this exact layout.
// ---------------------------------------------------------------------------

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: MtTextStyles.labelMd.copyWith(
        color: MtColors.ink,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onClose;
  const _TopBar({required this.onBack, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InkWell(
          onTap: onBack,
          borderRadius: BorderRadius.circular(8),
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.arrow_back, color: MtColors.ink, size: 22),
          ),
        ),
        const Spacer(),
        InkWell(
          onTap: onClose,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: MtColors.ink2.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.close, color: Colors.white, size: 20),
          ),
        ),
      ],
    );
  }
}

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspace;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onBackspace,
  });

  @override
  Widget build(BuildContext context) {
    final filled = controller.text.isNotEmpty;
    return Container(
      width: 44,
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: filled ? MtColors.brand : MtColors.line,
          width: filled ? 1.6 : 1,
        ),
      ),
      child: KeyboardListener(
        focusNode: FocusNode(skipTraversal: true),
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace &&
              controller.text.isEmpty) {
            onBackspace();
          }
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          showCursor: true,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: MtTextStyles.h1.copyWith(
            color: MtColors.ink,
            fontWeight: FontWeight.w800,
            fontSize: 22,
          ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            counterText: '',
            isCollapsed: true,
            contentPadding: EdgeInsets.zero,
          ),
          maxLength: 1,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
