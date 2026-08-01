import 'package:flutter/material.dart';

import '../../../../core/theme/mt_text_styles.dart';
import 'booking_milestone_theme.dart';

/// Pre-arrival guidance, shown only while the provider is on their way or
/// already working.
///
/// The window matters as much as the text: told at booking time the patient
/// has forgotten it by the visit, and told afterwards it is useless. Between
/// EN_ROUTE and IN_SERVICE is the one stretch where "keep your recent lab
/// reports ready" still changes how the visit goes.
///
/// The copy itself is role-specific and comes from the booking (server-side
/// `preparation_tip`, or the local mirror in `ProviderTypeX.preparationTip`) —
/// this widget only frames it.
class PreparationTipsBanner extends StatelessWidget {
  /// The guidance to render, already resolved for the attending role.
  final String tip;

  /// Names the role in the heading — "Before your Nurse arrives".
  final String roleLabel;

  final MilestoneStyle style;

  const PreparationTipsBanner({
    super.key,
    required this.tip,
    required this.roleLabel,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: style.surfaceHi,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: style.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.tips_and_updates_rounded, size: 20, color: style.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Before your $roleLabel arrives',
                  style: MtTextStyles.labelMd.copyWith(
                    color: style.title,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tip,
                  style: MtTextStyles.bodySm.copyWith(
                    color: style.body,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
