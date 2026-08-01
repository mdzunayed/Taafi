import 'package:flutter/material.dart';

import '../../../../core/models/doctor_dashboard.dart';
import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/utils/age.dart';

/// Highlighted block shown on a provider's active-job screen when the visit
/// is for a dependent (family member) rather than the account holder. Gives
/// the clinician the target patient's relationship, age/sex, blood group and
/// known conditions at a glance. Shared by the doctor and nurse consoles.
class TargetPatientPanel extends StatelessWidget {
  final CareRecipientInfo recipient;
  const TargetPatientPanel({super.key, required this.recipient});

  @override
  Widget build(BuildContext context) {
    final rel = recipient.relationshipLabel;
    final ageSex = recipient.ageSex.isNotEmpty
        ? recipient.ageSex
        : ageSexLabel(recipient.dateOfBirth, recipient.gender);
    final conditions = [
      ...recipient.medicalConditions,
      if (recipient.medicalNotes.trim().isNotEmpty)
        recipient.medicalNotes.trim(),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MtColors.brandSofter,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.brand.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment_ind_outlined,
                  size: 16, color: MtColors.brand),
              const SizedBox(width: 6),
              Text(
                rel.isEmpty ? 'Family member' : 'Family member · $rel',
                style: MtTextStyles.labelMd.copyWith(
                  color: MtColors.brand,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _line(
            'Age / Sex',
            [
              if (ageSex.isNotEmpty) ageSex,
              if (recipient.hasBloodGroup) 'Blood ${recipient.bloodGroup}',
            ].join('   ·   '),
          ),
          if (conditions.isNotEmpty)
            _line('Conditions', conditions.join(', ')),
        ],
      ),
    );
  }

  Widget _line(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: MtTextStyles.bodySm.copyWith(
                color: MtColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
