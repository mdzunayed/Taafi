import 'package:flutter/material.dart';
import '../theme/mt_colors.dart';
import '../theme/mt_text_styles.dart';

class SectionLabel extends StatelessWidget {
  final String labelEn;
  final String? labelBn;
  final MainAxisAlignment alignment;

  const SectionLabel({
    super.key,
    required this.labelEn,
    this.labelBn,
    this.alignment = MainAxisAlignment.spaceBetween,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: alignment,
        children: [
          Text(
            labelEn.toUpperCase(),
            style: MtTextStyles.sectionLabel.copyWith(color: MtColors.ink3),
          ),
          if (labelBn != null)
            Text(
              labelBn!,
              style: MtTextStyles.sectionLabel.copyWith(
                color: MtColors.ink3,
                fontFamily: 'Kalpurush',
              ),
            ),
        ],
      ),
    );
  }
}
