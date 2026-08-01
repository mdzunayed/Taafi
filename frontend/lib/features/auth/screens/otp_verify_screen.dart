import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../auth_flow_provider.dart';
import 'auth_widgets.dart';

class OtpVerifyScreen extends ConsumerStatefulWidget {
  const OtpVerifyScreen({super.key});

  @override
  ConsumerState<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends ConsumerState<OtpVerifyScreen> {
  // 6-digit pin — dev OTP '222222' lines up exactly. Auto-advance +
  // paste-spread logic below is length-agnostic so no other change.
  static const _length = 6;
  late final List<TextEditingController> _ctrls;
  late final List<FocusNode> _nodes;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(_length, (_) => TextEditingController());
    _nodes = List.generate(_length, (_) => FocusNode());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nodes.first.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  String get _code => _ctrls.map((c) => c.text).join();

  void _onChanged(int index, String value) {
    if (value.isEmpty) {
      // Backspace from an already-empty box jumps to the previous one
      // so the user can scrub left without lifting their finger off
      // the digit keys.
      if (index > 0) _nodes[index - 1].requestFocus();
      setState(() {});
      return;
    }
    // Paste-the-whole-code support: if the framework hands us multiple
    // digits at once (web autofill / iOS SMS bar), spread them.
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (var i = 0; i < _length; i++) {
        _ctrls[i].text = i < digits.length ? digits[i] : '';
      }
      _nodes[(digits.length - 1).clamp(0, _length - 1)].requestFocus();
      setState(() {});
      _maybeAutoSubmit();
      return;
    }
    if (index < _length - 1) {
      _nodes[index + 1].requestFocus();
    } else {
      _nodes[index].unfocus();
    }
    setState(() {});
    _maybeAutoSubmit();
  }

  /// Auto-submit once all four boxes are filled — saves a tap on the
  /// Verify button when the SMS autofill bar drops the full code in.
  void _maybeAutoSubmit() {
    if (_code.length == _length) {
      _verify();
    }
  }

  Future<void> _verify() async {
    if (_code.length != _length) return;
    final ok = await ref.read(authFlowProvider.notifier).verifyOtp(_code);
    if (!mounted) return;
    if (!ok) {
      final err = ref.read(authFlowProvider).error;
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: MtColors.rejected),
        );
      }
      return;
    }
    // verifyOtp already hydrated the auth session — the router redirect
    // would normally take us straight to the patient home, but the
    // Success screen is part of the design, so we land there first and
    // let the user tap Continue when they're ready.
    context.pushReplacement('/verify-success');
  }

  Future<void> _resend() async {
    final ok = await ref.read(authFlowProvider.notifier).requestOtp();
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code re-sent')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(authFlowProvider);
    final phone = flow.phone.isEmpty ? 'your phone' : flow.phone;
    return Scaffold(
      backgroundColor: MtColors.brandSofter,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _OtpTopBar(
                    onBack: () => Navigator.of(context).maybePop(),
                    onClose: () =>
                        Navigator.of(context).popUntil((r) => r.isFirst),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Verify Your Phone',
                    style: MtTextStyles.h1.copyWith(
                      color: MtColors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 32,
                    ),
                  ),
                  const SizedBox(height: 12),
                  RichText(
                    text: TextSpan(
                      style: MtTextStyles.bodyMd.copyWith(
                        color: MtColors.ink2,
                        height: 1.4,
                      ),
                      children: [
                        const TextSpan(
                          text: 'Enter the 4-digit code sent to ',
                        ),
                        TextSpan(
                          text: phone,
                          style: MtTextStyles.labelLg.copyWith(
                            color: MtColors.ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 36),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        _OtpBox(
                          controller: _ctrls[i],
                          focusNode: _nodes[i],
                          onChanged: (v) => _onChanged(i, v),
                          onBackspace: () {
                            if (_ctrls[i].text.isEmpty && i > 0) {
                              _nodes[i - 1].requestFocus();
                              _ctrls[i - 1].clear();
                              setState(() {});
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 32),
                  PrimaryAuthButton(
                    label: 'Verify',
                    isLoading: flow.isLoading,
                    onPressed: _code.length == _length ? _verify : null,
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      "Didn't receive the code?",
                      style: MtTextStyles.bodyMd
                          .copyWith(color: MtColors.ink2),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton(
                      onPressed: flow.isLoading ? null : _resend,
                      style: TextButton.styleFrom(
                        foregroundColor: MtColors.brand,
                      ),
                      child: Text(
                        'Resend Code',
                        style: MtTextStyles.labelLg.copyWith(
                          color: MtColors.brand,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OtpTopBar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onClose;
  const _OtpTopBar({required this.onBack, required this.onClose});

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
      // 6 boxes need to fit in a 440-px max-width centred column with
      // 24-px outer padding + 5 gaps × 10 px → 44 px per box is the
      // largest size that still avoids horizontal overflow.
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

