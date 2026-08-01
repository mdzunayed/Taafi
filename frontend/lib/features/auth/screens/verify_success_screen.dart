import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../auth_flow_provider.dart';
import '../auth_provider.dart';
import 'auth_widgets.dart';

class VerifySuccessScreen extends ConsumerWidget {
  const VerifySuccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: MtColors.brandSofter,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.of(context).maybePop(),
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.arrow_back,
                          color: MtColors.ink, size: 22),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Verification',
                        style: MtTextStyles.h3.copyWith(
                          color: MtColors.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () =>
                        Navigator.of(context).popUntil((r) => r.isFirst),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: MtColors.ink2.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 24),
                        const Center(child: ConcentricCheck()),
                        const SizedBox(height: 36),
                        Text(
                          'Verification Successful!',
                          textAlign: TextAlign.center,
                          style: MtTextStyles.h1.copyWith(
                            color: MtColors.ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 30,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "Your phone number has been verified. Let's "
                          'finish setting up your account.',
                          textAlign: TextAlign.center,
                          style: MtTextStyles.bodyMd.copyWith(
                            color: MtColors.ink2,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: PrimaryAuthButton(
                  label: 'Continue',
                  trailingIcon: Icons.arrow_forward,
                  onPressed: () {
                    // OTP success already hydrated [authTokenProvider] —
                    // route into the role-specific home and drop the
                    // in-progress draft so a future sign-up starts clean.
                    final user = ref.read(currentUserProvider);
                    ref.read(authFlowProvider.notifier).reset();
                    context.go(user == null ? '/login' : routeForUser(user));
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
