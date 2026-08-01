import 'package:flutter/material.dart';

import '../theme/mt_colors.dart';
import '../theme/mt_text_styles.dart';
import 'mt_button.dart';

class MtErrorState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;
  final EdgeInsetsGeometry padding;

  const MtErrorState({
    super.key,
    this.title = 'Something went wrong',
    required this.message,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.padding = const EdgeInsets.all(16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, color: MtColors.rejected),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: 140,
              child: MtButton(
                label: retryLabel,
                isOutlined: true,
                onPressed: onRetry!,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
