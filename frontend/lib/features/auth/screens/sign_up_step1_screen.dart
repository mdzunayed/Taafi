import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../auth_flow_provider.dart';
import 'auth_widgets.dart';

class SignUpStep1Screen extends ConsumerStatefulWidget {
  const SignUpStep1Screen({super.key});

  @override
  ConsumerState<SignUpStep1Screen> createState() => _SignUpStep1ScreenState();
}

class _SignUpStep1ScreenState extends ConsumerState<SignUpStep1Screen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _password;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(authFlowProvider);
    _name = TextEditingController(text: draft.fullName);
    _phone = TextEditingController(text: draft.phone);
    _address = TextEditingController(text: draft.address);
    _password = TextEditingController(text: draft.password);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final notifier = ref.read(authFlowProvider.notifier);
    notifier.saveStep1(
      fullName: _name.text,
      phone: _phone.text,
      address: _address.text,
      password: _password.text,
    );
    final ok = await notifier.register();
    if (!ok) {
      if (!mounted) return;
      final err = ref.read(authFlowProvider).error;
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: MtColors.rejected),
        );
      }
      return;
    }
    if (!mounted) return;
    context.push('/otp-verify');
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authFlowProvider).isLoading;
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
                      onClose: () => Navigator.of(context)
                          .popUntil((r) => r.isFirst),
                    ),
                    const SizedBox(height: 28),
                    const _StepIndicator(currentStep: 1, totalSteps: 3),
                    const SizedBox(height: 36),
                    Text(
                      'Create your account',
                      style: MtTextStyles.h1.copyWith(
                        color: MtColors.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 32,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Join our healthcare community today. We'll start with the basics.",
                      style: MtTextStyles.bodyMd
                          .copyWith(color: MtColors.ink2, height: 1.45),
                    ),
                    const SizedBox(height: 28),
                    const _Label('Full Name'),
                    const SizedBox(height: 8),
                    AuthTextField(
                      controller: _name,
                      hint: 'John Doe',
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.name,
                      autofillHints: const [AutofillHints.name],
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Full name is required' : null,
                    ),
                    const SizedBox(height: 18),
                    const _Label('Phone Number'),
                    const SizedBox(height: 8),
                    AuthTextField(
                      controller: _phone,
                      hint: '+1 (555) 000-0000',
                      icon: Icons.phone_outlined,
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.phone,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      validator: (v) {
                        final value = (v ?? '').trim();
                        if (value.isEmpty) return 'Phone is required';
                        final digits = value.replaceAll(RegExp(r'\D'), '');
                        if (digits.length < 7) return 'Enter a valid phone';
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    const _Label('Address'),
                    const SizedBox(height: 8),
                    AuthTextField(
                      controller: _address,
                      hint: 'House, road, area',
                      icon: Icons.home_outlined,
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.streetAddress,
                      autofillHints: const [
                        AutofillHints.fullStreetAddress,
                        AutofillHints.streetAddressLine1,
                      ],
                      validator: (v) {
                        final value = (v ?? '').trim();
                        if (value.isEmpty) return 'Address is required';
                        if (value.length < 4) return 'Address looks too short';
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    const _Label('Password'),
                    const SizedBox(height: 8),
                    AuthTextField(
                      controller: _password,
                      hint: 'At least 6 characters',
                      icon: Icons.lock_outline,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      onFieldSubmitted: (_) => _next(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: MtColors.ink3,
                          size: 20,
                        ),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                      validator: (v) {
                        final value = v ?? '';
                        if (value.isEmpty) return 'Password is required';
                        if (value.length < 6) {
                          return 'Use at least 6 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 32),
                    PrimaryAuthButton(
                      label: 'Next Step',
                      trailingIcon: Icons.arrow_forward,
                      isLoading: isLoading,
                      onPressed: _next,
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

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: MtTextStyles.labelMd
          .copyWith(color: MtColors.ink, fontWeight: FontWeight.w700),
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
        Expanded(
          child: Center(
            child: Text(
              'Sign Up',
              style: MtTextStyles.h3.copyWith(
                color: MtColors.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
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

class _StepIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  const _StepIndicator({required this.currentStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    final progress = currentStep / totalSteps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Step $currentStep of $totalSteps',
              style: MtTextStyles.labelLg.copyWith(
                color: MtColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${(progress * 100).round()}%',
              style: MtTextStyles.labelLg.copyWith(
                color: MtColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: MtColors.line,
            valueColor: const AlwaysStoppedAnimation(MtColors.brand),
          ),
        ),
      ],
    );
  }
}
