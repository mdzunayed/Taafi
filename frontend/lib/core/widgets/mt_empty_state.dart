import 'package:flutter/material.dart';

import '../theme/mt_colors.dart';
import '../theme/mt_text_styles.dart';

class MtEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? bnTitle;
  final String? bnSubtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  const MtEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.bnTitle,
    this.bnSubtitle,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: MtColors.brandSofter,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: MtColors.brand, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
            textAlign: TextAlign.center,
          ),
          if (bnTitle != null) ...[
            const SizedBox(height: 2),
            Text(
              bnTitle!,
              style: MtTextStyles.bodySm.copyWith(
                color: MtColors.ink3,
                fontFamily: 'Kalpurush',
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
              textAlign: TextAlign.center,
            ),
          ],
          if (bnSubtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              bnSubtitle!,
              style: MtTextStyles.bodySm.copyWith(
                color: MtColors.ink3,
                fontFamily: 'Kalpurush',
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: onAction,
              style: OutlinedButton.styleFrom(
                foregroundColor: MtColors.brand,
                side: const BorderSide(color: MtColors.brand),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
              ),
              child: Text(actionLabel!, style: MtTextStyles.labelMd),
            ),
          ],
        ],
      ),
    );
  }
}
