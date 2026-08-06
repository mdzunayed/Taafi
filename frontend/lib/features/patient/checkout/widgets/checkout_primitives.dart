import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors_ext.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../screens/booking_flow_pages.dart' show money;

/// Sticky bottom bar shared by the Summary and Checkout steps: a running
/// total on the left, a full-width primary CTA underneath, and an optional
/// banner slot above both (active-booking warning, deposit explainer).
class CheckoutActionBar extends StatelessWidget {
  final String totalLabel;
  final double total;

  /// Optional second line under the total, e.g. "৳250 charged now".
  final String? totalNote;

  final String ctaLabel;
  final IconData? ctaIcon;

  /// `null` disables the CTA.
  final VoidCallback? onPressed;
  final bool isLoading;
  final String? loadingLabel;

  /// Rendered above the total — used for the active-booking banner and the
  /// inline validation message.
  final Widget? banner;

  const CheckoutActionBar({
    super.key,
    required this.totalLabel,
    required this.total,
    required this.ctaLabel,
    required this.onPressed,
    this.totalNote,
    this.ctaIcon,
    this.isLoading = false,
    this.loadingLabel,
    this.banner,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.cardBorder)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (banner != null) ...[banner!, const SizedBox(height: 12)],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        totalLabel,
                        style: MtTextStyles.bodySm.copyWith(color: c.muted),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        money(total),
                        style: MtTextStyles.h2.copyWith(color: c.title),
                      ),
                      if (totalNote != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          totalNote!,
                          style: MtTextStyles.bodySm.copyWith(color: c.body),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: isLoading ? null : onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: c.onAccent,
                  disabledBackgroundColor: c.surfaceHi,
                  disabledForegroundColor: c.muted,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isLoading) ...[
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(c.onAccent),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        loadingLabel ?? 'Please wait…',
                        style: MtTextStyles.labelLg.copyWith(color: c.onAccent),
                      ),
                    ] else ...[
                      if (ctaIcon != null) ...[
                        Icon(ctaIcon, size: 18),
                        const SizedBox(width: 8),
                      ],
                      // No explicit color: inherits the button foreground so
                      // the disabled state dims the label with it.
                      Text(ctaLabel, style: MtTextStyles.labelLg),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of a bill breakdown.
class PriceRow extends StatelessWidget {
  final String label;
  final String value;

  /// Renders bigger + bolder — reserved for the grand total.
  final bool emphasize;
  final Color? valueColor;

  /// Small muted note under the label (e.g. "Deducted from your final bill").
  final String? note;

  const PriceRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasize = false,
    this.valueColor,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: emphasize
                    ? MtTextStyles.labelLg.copyWith(color: c.title)
                    : MtTextStyles.bodyMd.copyWith(color: c.body),
              ),
              if (note != null) ...[
                const SizedBox(height: 2),
                Text(note!,
                    style: MtTextStyles.bodySm.copyWith(color: c.muted)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: emphasize
              ? MtTextStyles.h3.copyWith(
                  color: valueColor ?? c.title,
                  fontWeight: FontWeight.w800,
                )
              : MtTextStyles.bodyMd.copyWith(
                  color: valueColor ?? c.title,
                  fontWeight: FontWeight.w600,
                ),
        ),
      ],
    );
  }
}

/// Section heading used down the left edge of both checkout screens.
class CheckoutSectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const CheckoutSectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: MtTextStyles.sectionLabel.copyWith(color: c.muted),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// White rounded panel every checkout section sits in.
class CheckoutCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;

  const CheckoutCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? c.cardBorder),
      ),
      child: child,
    );
  }
}
