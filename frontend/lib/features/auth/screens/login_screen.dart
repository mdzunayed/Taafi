import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/support_config.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/mt_button.dart';
import '../../../core/models/user.dart';
import '../auth_provider.dart';

/// Demo credentials baked into the mock auth backend.
const _demoCredentials = <UserRole, ({String email, String password})>{
  UserRole.patient: (email: 'patient@taafi.app', password: 'password'),
  UserRole.doctor: (email: 'doctor@taafi.app', password: 'password'),
  UserRole.admin: (email: 'admin@taafi.app', password: 'password'),
};

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  UserRole? _selectedRole;

  /// Last auth failure, shown as a persistent red banner above the form
  /// so a missed snackbar can never silently hide the problem.
  String? _authError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _fillDemo() {
    if (_selectedRole == null) return;
    final creds = _demoCredentials[_selectedRole]!;
    setState(() {
      _emailController.text = creds.email;
      _passwordController.text = creds.password;
      _authError = null; // clear any prior failure when prefilling
    });
  }

  Future<void> _handleLogin() async {
    // Reset the banner at the start of every attempt so a stale error
    // doesn't visually persist while we're calling the network.
    setState(() => _authError = null);

    if (_selectedRole == null) {
      _showError('Pick a role (Patient / Doctor / Admin) before signing in.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final authNotifier = ref.read(authTokenProvider.notifier);
    // The role picker on this screen drives the new role-aware login —
    // backend rejects role mismatches with a 403 so we don't even
    // bother sanity-checking the response role separately below.
    await authNotifier.login(
      _emailController.text.trim(),
      _passwordController.text,
      role: _selectedRole!,
    );

    if (!mounted) return;

    final authState = ref.read(authTokenProvider);
    final error = authState.whenOrNull(error: (e, _) => e);
    if (error != null) {
      // DioClient._handleError already produces a friendly message; show it.
      _showError(error.toString());
      return;
    }

    final user = ref.read(currentUserProvider);
    if (user == null) {
      _showError("Sign-in completed but no profile was returned. "
          "Check the backend's /auth/login response shape.");
      return;
    }

    // Enforce that credentials match the chosen role.
    if (user.role != _selectedRole) {
      await authNotifier.logout();
      if (!mounted) return;
      final picked = _selectedRole;
      _showError(
        'Those credentials are for ${_roleLabel(user.role)}, '
        'not ${picked == null ? "the selected role" : _roleLabel(picked)}.',
      );
      return;
    }

    context.go(routeForUser(user));
  }

  /// Surfaces an auth failure in BOTH places so it can't be missed:
  /// (1) a persistent red banner above the form, (2) a red snackbar with
  /// an icon that stays visible for 6 s.
  void _showError(String message) {
    if (!mounted) return;
    setState(() => _authError = message);
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
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

  String _roleLabel(UserRole role) {
    switch (role) {
      case UserRole.patient:
        return 'Patient';
      case UserRole.doctor:
        return 'Doctor';
      case UserRole.nurse:
        return 'Nurse';
      case UserRole.admin:
        return 'Admin';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authTokenProvider).isLoading;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [MtColors.brandSoft, MtColors.surface],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: MtColors.brand,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(Icons.local_hospital,
                              size: 36, color: Colors.white),
                        ),
                        const SizedBox(height: 24),
                        Text('Taafi',
                            style: MtTextStyles.displayLg
                                .copyWith(color: MtColors.ink, fontSize: 36)),
                        const SizedBox(height: 4),
                        Text(kBrandTaglineBn,
                            textAlign: TextAlign.center,
                            style: MtTextStyles.bodyMd.copyWith(
                                color: MtColors.ink2,
                                fontSize: 14,
                                fontWeight: FontWeight.w400)),
                        const SizedBox(height: 32),

                        // --- Persistent auth error banner ---
                        // Shows the last login failure above the form so a
                        // missed snackbar can never silently hide the cause.
                        if (_authError != null) ...[
                          _AuthErrorBanner(
                            message: _authError ?? '',
                            onDismiss: () => setState(() => _authError = null),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // --- Role picker ---
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text('I AM A',
                              style: MtTextStyles.labelSm
                                  .copyWith(color: MtColors.ink3, letterSpacing: 1.2)),
                        ),
                        const SizedBox(height: 8),
                        _RolePicker(
                          selected: _selectedRole,
                          onSelected: (role) => setState(() {
                            _selectedRole = role;
                            _authError = null; // clear stale error on a fresh pick
                          }),
                        ),
                        const SizedBox(height: 20),

                        // --- Email ---
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          textCapitalization: TextCapitalization.none,
                          textInputAction: TextInputAction.next,
                          decoration: _decoration(
                              hint: 'Email', icon: Icons.email_outlined),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Email is required';
                            if (!v.contains('@')) return 'Enter a valid email';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        // --- Password ---
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _handleLogin(),
                          decoration: _decoration(
                              hint: 'Password', icon: Icons.lock_outline),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Password is required';
                            if (v.length < 4) return 'Password is too short';
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),

                        // --- Sign in button ---
                        MtButton(
                          label: _selectedRole == null
                              ? 'Select a role to continue'
                              : 'Sign in as ${_roleLabel(_selectedRole!)}',
                          leadingIcon: Icons.login,
                          isLoading: isLoading,
                          onPressed: _selectedRole == null ? () {} : _handleLogin,
                        ),

                        // --- Demo helper (only shown after a role is picked) ---
                        if (_selectedRole != null) ...[
                          const SizedBox(height: 18),
                          _DemoHint(
                            role: _selectedRole!,
                            creds: _demoCredentials[_selectedRole]!,
                            onFill: _fillDemo,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration({required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: MtColors.ink3),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MtColors.rejected),
      ),
    );
  }
}

class _RolePicker extends StatelessWidget {
  final UserRole? selected;
  final ValueChanged<UserRole> onSelected;

  const _RolePicker({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: _RoleChip(
                role: UserRole.patient,
                label: 'Patient',
                icon: Icons.favorite_border,
                selected: selected == UserRole.patient,
                onTap: () => onSelected(UserRole.patient))),
        const SizedBox(width: 8),
        Expanded(
            child: _RoleChip(
                role: UserRole.doctor,
                label: 'Doctor',
                icon: Icons.medical_services_outlined,
                selected: selected == UserRole.doctor,
                onTap: () => onSelected(UserRole.doctor))),
        const SizedBox(width: 8),
        Expanded(
            child: _RoleChip(
                role: UserRole.admin,
                label: 'Admin',
                icon: Icons.shield_outlined,
                selected: selected == UserRole.admin,
                onTap: () => onSelected(UserRole.admin))),
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  final UserRole role;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RoleChip({
    required this.role,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? MtColors.brandSoft : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? MtColors.brand : MtColors.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 22, color: selected ? MtColors.brand : MtColors.ink2),
              const SizedBox(height: 6),
              Text(
                label,
                style: MtTextStyles.labelMd.copyWith(
                  color: selected ? MtColors.brand : MtColors.ink2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DemoHint extends StatelessWidget {
  final UserRole role;
  final ({String email, String password}) creds;
  final VoidCallback onFill;

  const _DemoHint({
    required this.role,
    required this.creds,
    required this.onFill,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MtColors.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MtColors.line),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: MtColors.ink3),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Demo credentials',
                    style:
                        MtTextStyles.labelSm.copyWith(color: MtColors.ink3)),
                const SizedBox(height: 2),
                Text('${creds.email} · ${creds.password}',
                    style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2)),
              ],
            ),
          ),
          TextButton(
            onPressed: onFill,
            style: TextButton.styleFrom(foregroundColor: MtColors.brand),
            child: const Text('Fill'),
          ),
        ],
      ),
    );
  }
}

/// Persistent red error banner shown above the login form. Pairs with the
/// red snackbar so even if the user dismisses one they still see the other.
class _AuthErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _AuthErrorBanner({required this.message, required this.onDismiss});

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
