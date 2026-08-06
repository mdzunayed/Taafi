import 'package:flutter/material.dart';

import '../../core/models/prescription.dart';
import '../../core/theme/mt_colors.dart';
import '../../core/theme/mt_text_styles.dart';
import '../../core/widgets/mt_button.dart';

/// Colors for the release-gate status chip, shared by the vault card,
/// the detail gate and the admin queue badges.
({Color fg, Color bg}) releaseChipColors(PrescriptionReleaseStatus s) {
  switch (s) {
    case PrescriptionReleaseStatus.paymentRequired:
      return (fg: MtColors.pending, bg: MtColors.pendingBg);
    case PrescriptionReleaseStatus.pendingAdminReview:
      return (fg: MtColors.pending, bg: MtColors.pendingBg);
    case PrescriptionReleaseStatus.unlocked:
      return (fg: MtColors.completed, bg: MtColors.completedBg);
    case PrescriptionReleaseStatus.rejected:
      return (fg: MtColors.rejected, bg: MtColors.rejectedBg);
  }
}

/// Short chip copy for a locked script in list surfaces.
String releaseChipLabel(Prescription p) {
  switch (p.releaseStatus) {
    case PrescriptionReleaseStatus.paymentRequired:
      return 'Balance due';
    case PrescriptionReleaseStatus.pendingAdminReview:
      return 'Under review';
    case PrescriptionReleaseStatus.unlocked:
      return 'Unlocked';
    case PrescriptionReleaseStatus.rejected:
      return 'Rejected';
  }
}

/// The release-pipeline gate card shown in place of the Rx content while
/// a script is locked. Renders the 4-step pipeline (Issued → Pay service
/// balance → Admin review → Unlocked) with the current stage highlighted,
/// plus the state-appropriate call to action. `onPay` settles the
/// BOOKING's outstanding balance — there is no per-prescription fee.
class PrescriptionReleaseGateCard extends StatelessWidget {
  final Prescription script;
  final VoidCallback onRefresh;
  final VoidCallback onPay;

  const PrescriptionReleaseGateCard({
    super.key,
    required this.script,
    required this.onRefresh,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    final s = script.releaseStatus;
    final rejected = s == PrescriptionReleaseStatus.rejected;
    final chip = releaseChipColors(s);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: chip.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  rejected ? Icons.block_outlined : Icons.lock_outline,
                  color: chip.fg,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rejected
                          ? 'Prescription rejected'
                          : 'Prescription locked',
                      style: MtTextStyles.h3.copyWith(color: MtColors.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${script.effectiveItemCount} medication'
                      '${script.effectiveItemCount == 1 ? '' : 's'} inside',
                      style:
                          MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: chip.bg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  s.labelEn,
                  style: MtTextStyles.bodySm.copyWith(
                    color: chip.fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (rejected) ...[
            Text(
              'Your prescription could not be approved during review. '
              'Please contact support for assistance — no further payment '
              'is required.',
              style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
            ),
          ] else ...[
            _ReleasePipelineSteps(status: s),
            const SizedBox(height: 18),
            if (s == PrescriptionReleaseStatus.paymentRequired) ...[
              MtButton(
                label: 'Pay service balance',
                leadingIcon: Icons.lock_open_outlined,
                onPressed: onPay,
              ),
              const SizedBox(height: 10),
              Text(
                'Your prescription will be available once payment is '
                'confirmed by your doctor (cash) or admin (online).',
                textAlign: TextAlign.center,
                style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
              ),
            ] else ...[
              Text(
                'Payment received. A Taafi admin is reviewing your '
                'prescription — it unlocks automatically once approved.',
                textAlign: TextAlign.center,
                style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
              ),
              const SizedBox(height: 10),
              MtButton(
                label: 'Refresh status',
                isOutlined: true,
                leadingIcon: Icons.refresh,
                onPressed: onRefresh,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

enum _StepState { done, active, pending }

/// The Issued → Pay balance → Admin review → Unlocked progression,
/// mirroring the booking flow's status timeline visual.
class _ReleasePipelineSteps extends StatelessWidget {
  final PrescriptionReleaseStatus status;
  const _ReleasePipelineSteps({required this.status});

  @override
  Widget build(BuildContext context) {
    final paying = status == PrescriptionReleaseStatus.paymentRequired;
    final steps = <(String, _StepState)>[
      ('Issued by doctor', _StepState.done),
      ('Pay service balance', paying ? _StepState.active : _StepState.done),
      (
        'Admin review',
        paying
            ? _StepState.pending
            : (status == PrescriptionReleaseStatus.pendingAdminReview
                ? _StepState.active
                : _StepState.done)
      ),
      (
        'Unlocked',
        status == PrescriptionReleaseStatus.unlocked
            ? _StepState.done
            : _StepState.pending
      ),
    ];
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          _StepRow(
            label: steps[i].$1,
            state: steps[i].$2,
            isLast: i == steps.length - 1,
          ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  final String label;
  final _StepState state;
  final bool isLast;
  const _StepRow({
    required this.label,
    required this.state,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _StepState.done => MtColors.completed,
      _StepState.active => MtColors.pending,
      _StepState.pending => MtColors.ink3,
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Icon(
                switch (state) {
                  _StepState.done => Icons.check_circle,
                  _StepState.active => Icons.radio_button_checked,
                  _StepState.pending => Icons.radio_button_unchecked,
                },
                size: 18,
                color: color,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: state == _StepState.done
                        ? MtColors.completed.withValues(alpha: 0.4)
                        : MtColors.line,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
            child: Text(
              label,
              style: MtTextStyles.bodyMd.copyWith(
                color: state == _StepState.pending
                    ? MtColors.ink3
                    : MtColors.ink,
                fontWeight: state == _StepState.active
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
