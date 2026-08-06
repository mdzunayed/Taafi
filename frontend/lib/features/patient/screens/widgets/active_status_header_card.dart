import 'package:flutter/material.dart';

import '../../../../core/models/active_care_step.dart';
import '../../../../core/models/booking_milestone.dart';
import '../../../../core/models/deposit_status.dart';
import '../../../../core/models/patient_active_request.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../booking_flow_pages.dart' show money;
import 'booking_milestone_theme.dart';
import 'milestone_progress_bar.dart';
import 'patient_home_palette.dart';
import 'pulsing_status_dot.dart';

/// The at-a-glance answer above the Active Care timeline: what state the
/// booking is in, how far along it is, and — when the patient owes something —
/// that they are the one holding it up.
///
/// The status capsule deliberately overrides the server's milestone wording
/// while a deposit is outstanding. The backend keeps `deposit_required` on
/// milestone `REQUESTED` (correct: nothing is confirmed until the money
/// lands), so its label reads "Booking Received — Under Review" — which tells
/// a patient who owes ৳500 that they are waiting on us.
class ActiveStatusHeaderCard extends StatelessWidget {
  final PatientActiveRequest request;

  const ActiveStatusHeaderCard({super.key, required this.request});

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final timeline = ActiveCareTimeline(request);
    final milestone = request.milestone;
    final style = BookingMilestoneTheme.of(context, milestone);
    final actionDue = request.needsDeposit;
    // Orange is this app's "you must act" colour. Anything the care team owes
    // the patient keeps the milestone's own hue.
    final accent = actionDue
        ? hd.accent
        : BookingMilestoneTheme.accentFor(context, milestone);
    final scheduled = request.scheduledTimeLabel?.trim();
    final step = timeline.currentStep;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: style.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PulsingStatusDot(
                color: accent,
                size: 8,
                animate: milestone.isLive,
                intense: milestone.isOnTheMove || actionDue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _capsuleLabel,
                  style: MtTextStyles.labelSm.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              if (milestone.isLive)
                Text(
                  'Step ${step.stepNumber} of ${ActiveCareStepX.totalSteps}',
                  style: MtTextStyles.labelSm.copyWith(
                    color: hd.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _headline,
            style: MtTextStyles.labelLg.copyWith(
              color: hd.title,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          if (request.serviceTitleEn.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              request.serviceTitleEn,
              style: MtTextStyles.bodyMd.copyWith(color: hd.body),
            ),
          ],
          const SizedBox(height: 14),
          MilestoneProgressBar(
            milestone: milestone,
            style: style,
            stepOverride: step.stepNumber,
          ),
          if (scheduled != null && scheduled.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.event_outlined, size: 16, color: hd.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Appointment · $scheduled',
                    style: MtTextStyles.bodySm.copyWith(color: hd.body),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String get _capsuleLabel {
    if (request.depositStatus == DepositStatus.failed) {
      return 'DEPOSIT PAYMENT FAILED';
    }
    if (request.needsDeposit) return 'ACTION NEEDED · DEPOSIT DUE';
    if (request.milestone == BookingMilestone.completed &&
        request.outstandingBalance > 0) {
      return 'ACTION NEEDED · BALANCE DUE';
    }
    return request.milestone.shortLabel;
  }

  String get _headline {
    if (request.needsDeposit) {
      return 'Pay ${money(request.depositDue)} to confirm your visit';
    }
    if (request.milestone == BookingMilestone.completed &&
        request.outstandingBalance > 0) {
      return 'Visit complete — ${money(request.outstandingBalance)} left to '
          'settle';
    }
    return request.milestoneHeadline;
  }
}
