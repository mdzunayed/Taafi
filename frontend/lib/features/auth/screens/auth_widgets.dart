import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/user.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';

// ---------------------------------------------------------------------------
// Shared visual atoms for the four new auth screens.
//
// Keeping these in one file means the screens can be read top-to-bottom
// without diving through five "_FieldLabel" / "_PrimaryButton" partials.
// ---------------------------------------------------------------------------

/// The square heartbeat-pulse badge that anchors the Welcome screen and
/// (smaller) the Success screen header. Hand-painted so the curve
/// matches the screenshot exactly instead of relying on an icon font.
class HeartPulseBadge extends StatelessWidget {
  final double size;
  const HeartPulseBadge({super.key, this.size = 72});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: MtColors.brandSoft,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: CustomPaint(
        painter: _HeartPulsePainter(),
      ),
    );
  }
}

class _HeartPulsePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MtColors.brand
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.07
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    final cy = h * 0.5;

    final path = Path()
      ..moveTo(w * 0.16, cy)
      ..lineTo(w * 0.32, cy)
      ..lineTo(w * 0.40, cy - h * 0.18)
      ..lineTo(w * 0.50, cy + h * 0.20)
      ..lineTo(w * 0.60, cy - h * 0.10)
      ..lineTo(w * 0.68, cy)
      ..lineTo(w * 0.84, cy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Branded, rounded text field used by every auth screen. White fill,
/// thin grey border, orange focus ring — matches the screenshots
/// exactly.
class AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData? icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final void Function(String)? onFieldSubmitted;
  final void Function(String)? onChanged;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;

  /// Paints the resting borders red without attaching a per-field error
  /// string. Covers the case [validator] can't: the input was well-formed
  /// (so `errorBorder` never fires) but the SERVER rejected it — e.g. a
  /// 401 from `/auth/login`. The owning screen drives this from its own
  /// failure state and clears it on the next keystroke.
  final bool hasError;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.icon,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.suffixIcon,
    this.validator,
    this.onFieldSubmitted,
    this.onChanged,
    this.autofillHints,
    this.inputFormatters,
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) {
    // Resting borders flip to the rejected token when the server knocked
    // the submission back; focus still wins so the field the user is
    // actively fixing reads as active, not broken.
    final restingBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: hasError
          ? const BorderSide(color: MtColors.rejected, width: 1.5)
          : const BorderSide(color: MtColors.line),
    );

    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
      onChanged: onChanged,
      autofillHints: autofillHints,
      inputFormatters: inputFormatters,
      style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: MtTextStyles.bodyMd.copyWith(color: MtColors.ink3),
        prefixIcon: icon == null
            ? null
            : Icon(icon,
                color: hasError ? MtColors.rejected : MtColors.ink3, size: 18),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: hasError ? MtColors.rejectedBg : Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        border: restingBorder,
        enabledBorder: restingBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MtColors.brand, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MtColors.rejected),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MtColors.rejected, width: 1.5),
        ),
      ),
    );
  }
}

/// Full-width orange button shared by every auth screen. Shows a small
/// inline CircularProgressIndicator while [isLoading] so the form stays
/// interactive (vs blocking the whole screen).
class PrimaryAuthButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback? onPressed;
  final IconData? trailingIcon;

  const PrimaryAuthButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.trailingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: MtColors.brand,
          foregroundColor: Colors.white,
          disabledBackgroundColor: MtColors.brand.withValues(alpha: 0.55),
          disabledForegroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: MtTextStyles.labelLg.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  if (trailingIcon != null) ...[
                    const SizedBox(width: 10),
                    Icon(trailingIcon, color: Colors.white, size: 18),
                  ],
                ],
              ),
      ),
    );
  }
}

/// Recognizer factory for the "Create an account" rich-text tail on the
/// Welcome Back screen. Keeps the screen tidy — the call site is a
/// single argument instead of a per-screen `_AuthLinkRecognizer`.
GestureRecognizer tapToSignUp(BuildContext context) {
  return TapGestureRecognizer()
    ..onTap = () {
      context.push('/sign-up');
    };
}

/// Concentric expanding-circle backdrop for the Success screen's
/// checkmark. Three rings of decreasing opacity painted at constant
/// radii — no animation so it never competes with the navigation flow.
class ConcentricCheck extends StatelessWidget {
  final double size;
  const ConcentricCheck({super.key, this.size = 220});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ConcentricPainter(),
        child: Center(
          child: Container(
            width: size * 0.34,
            height: size * 0.34,
            decoration: const BoxDecoration(
              color: MtColors.brand,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check,
              color: Colors.white,
              size: size * 0.20,
            ),
          ),
        ),
      ),
    );
  }
}

class _ConcentricPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = math.min(size.width, size.height) / 2;
    final rings = [
      (radius: maxR * 1.00, alpha: 0.08),
      (radius: maxR * 0.78, alpha: 0.14),
      (radius: maxR * 0.52, alpha: 0.22),
    ];
    for (final ring in rings) {
      final paint = Paint()
        ..color = MtColors.brand.withValues(alpha: ring.alpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, ring.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// AuthRolePicker — segmented Patient / Doctor / Admin selector shown
// above the Phone Number field on the Welcome Back screen.
//
// Visually mirrors the legacy `_RoleChip` in login_screen.dart so the
// two entry points feel like one design system. Kept in the shared
// widgets file so future auth screens can reuse it.
// ---------------------------------------------------------------------------

class AuthRolePicker extends StatelessWidget {
  final UserRole selected;
  final ValueChanged<UserRole> onSelected;

  const AuthRolePicker({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final chips = [
      _AuthRoleChip(
        label: 'Patient',
        icon: Icons.favorite_border,
        selected: selected == UserRole.patient,
        onTap: () => onSelected(UserRole.patient),
      ),
      _AuthRoleChip(
        label: 'Doctor',
        icon: Icons.medical_services_outlined,
        selected: selected == UserRole.doctor,
        onTap: () => onSelected(UserRole.doctor),
      ),
      _AuthRoleChip(
        label: 'Nurse',
        icon: Icons.medical_information_outlined,
        selected: selected == UserRole.nurse,
        onTap: () => onSelected(UserRole.nurse),
      ),
      _AuthRoleChip(
        label: 'Admin',
        icon: Icons.shield_outlined,
        selected: selected == UserRole.admin,
        onTap: () => onSelected(UserRole.admin),
      ),
    ];

    // Four chips fit comfortably on phone widths >= ~360 px. On
    // narrower screens we wrap into a 2×2 grid so the labels never
    // truncate or compress below readable size.
    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxWidth < 360;
        if (!tight) {
          return Row(
            children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: chips[i]),
              ],
            ],
          );
        }
        // 2×2 grid for narrow screens.
        return Column(
          children: [
            Row(
              children: [
                Expanded(child: chips[0]),
                const SizedBox(width: 8),
                Expanded(child: chips[1]),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: chips[2]),
                const SizedBox(width: 8),
                Expanded(child: chips[3]),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _AuthRoleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _AuthRoleChip({
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
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
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
                  size: 20,
                  color: selected ? MtColors.brand : MtColors.ink2),
              const SizedBox(height: 4),
              Text(
                label,
                style: MtTextStyles.labelMd.copyWith(
                  color: selected ? MtColors.brand : MtColors.ink2,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

