import 'package:flutter/material.dart';
import '../theme/mt_colors.dart';
import '../theme/mt_text_styles.dart';

enum ServiceStatus { pendingReview, enroute, arrived, inService, completed }

class StatusBadge extends StatelessWidget {
  final ServiceStatus status;
  final String? label;

  const StatusBadge({super.key, required this.status, this.label});

  _StatusInfo get _info {
    switch (status) {
      case ServiceStatus.pendingReview:
        return _StatusInfo(
          color: MtColors.pending,
          bgColor: MtColors.pendingBg,
          label: label ?? 'PENDING REVIEW',
        );
      case ServiceStatus.enroute:
        return _StatusInfo(
          color: MtColors.brand,
          bgColor: MtColors.brandSoft,
          label: label ?? 'ON THE WAY',
        );
      case ServiceStatus.arrived:
        return _StatusInfo(
          color: MtColors.brand,
          bgColor: MtColors.brandSoft,
          label: label ?? 'ARRIVED',
        );
      case ServiceStatus.inService:
        return _StatusInfo(
          color: MtColors.completed,
          bgColor: MtColors.completedBg,
          label: label ?? 'IN SERVICE',
        );
      case ServiceStatus.completed:
        return _StatusInfo(
          color: MtColors.completed,
          bgColor: MtColors.completedBg,
          label: label ?? 'COMPLETED',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: info.bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: info.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            info.label,
            style: MtTextStyles.labelSm.copyWith(color: info.color),
          ),
        ],
      ),
    );
  }
}

class _StatusInfo {
  final Color color;
  final Color bgColor;
  final String label;

  _StatusInfo({
    required this.color,
    required this.bgColor,
    required this.label,
  });
}
