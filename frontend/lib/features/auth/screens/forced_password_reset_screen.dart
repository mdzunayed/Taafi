import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../auth_provider.dart';

/// Single-use screen the router lands an admin-provisioned doctor /
/// nurse on immediately after their first login with the temporary
/// password. The user must set a new password before they're allowed
/// to reach the dashboard — the screen has no "skip" affordance.
///
/// Driven entirely by [authTokenProvider.completeForcedPasswordReset];
/// the backend clears the `requires_password_reset` latch and re-issues
/// a clean session on success, the router redirect then unblocks the
/// dashboard route automatically.
class ForcedPasswordResetScreen extends ConsumerStatefulWidget {
  const ForcedPasswordResetScreen({super.key});

  @override
  ConsumerState<ForcedPasswordResetScreen> createState() =>
      _ForcedPasswordResetScreenState();
}

class _ForcedPasswordResetScreenState
    extends ConsumerState<ForcedPasswordResetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newPasswordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _showNew = false;
  bool _showConfirm = false;
  bool _busy = false;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String? _validatePassword(String? raw) {
    final v = (raw ?? '').trim();
    if (v.length < 8) return 'Use at least 8 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(v) ||
        !RegExp(r'[0-9]').hasMatch(v)) {
      return 'Mix letters and numbers';
    }
    return null;
  }

  String? _validateConfirm(String? raw) {
    if ((raw ?? '') != _newPasswordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(authTokenProvider.notifier)
          .completeForcedPasswordReset(_newPasswordController.text);
      // No explicit navigation — the router redirect picks up the
      // freshly-cleared `requiresReset` latch and lands the session
      // on the role-specific dashboard.
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't reset password: $e")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    await ref.read(authTokenProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final greetingName = user?.name.split(' ').first ?? '';

    return Scaffold(
      backgroundColor: MtColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      color: MtColors.brandSofter,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_reset,
                      color: MtColors.brand,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Set your new password',
                    style: MtTextStyles.h1.copyWith(color: MtColors.ink),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    greetingName.isEmpty
                        ? "Your account was provisioned by an administrator. Choose a private password to continue."
                        : "Welcome, $greetingName. Your account was provisioned by an administrator — choose a private password to continue.",
                    style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(
                      color: MtColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: MtColors.line),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _FieldLabel(label: 'New password'),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _newPasswordController,
                            obscureText: !_showNew,
                            autofocus: true,
                            textInputAction: TextInputAction.next,
                            decoration: _inputDecoration(
                              hint: 'At least 8 chars, letters + numbers',
                              suffix: IconButton(
                                icon: Icon(
                                  _showNew
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: MtColors.ink3,
                                ),
                                onPressed: () =>
                                    setState(() => _showNew = !_showNew),
                              ),
                            ),
                            validator: _validatePassword,
                          ),
                          const SizedBox(height: 14),
                          _FieldLabel(label: 'Confirm password'),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _confirmController,
                            obscureText: !_showConfirm,
                            textInputAction: TextInputAction.done,
                            decoration: _inputDecoration(
                              hint: 'Retype the password above',
                              suffix: IconButton(
                                icon: Icon(
                                  _showConfirm
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: MtColors.ink3,
                                ),
                                onPressed: () => setState(
                                    () => _showConfirm = !_showConfirm),
                              ),
                            ),
                            validator: _validateConfirm,
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _busy ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: MtColors.brand,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        valueColor: AlwaysStoppedAnimation<
                                            Color>(Colors.white),
                                      ),
                                    )
                                  : Text('Save new password',
                                      style: MtTextStyles.labelLg
                                          .copyWith(color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _busy ? null : _signOut,
                    style: TextButton.styleFrom(
                      foregroundColor: MtColors.ink3,
                    ),
                    child: const Text('Sign out instead'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: MtTextStyles.bodyMd.copyWith(color: MtColors.ink3),
      filled: true,
      fillColor: MtColors.surface2,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MtColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MtColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MtColors.brand, width: 1.5),
      ),
      suffixIcon: suffix,
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: MtTextStyles.labelMd.copyWith(
        color: MtColors.ink,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
