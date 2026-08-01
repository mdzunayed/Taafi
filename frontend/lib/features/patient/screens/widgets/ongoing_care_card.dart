import 'package:flutter/material.dart';

import '../../../../core/models/booking_milestone.dart';
import '../../../../core/models/patient_active_request.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/utils/whatsapp_support.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/whatsapp_support_button.dart';
import 'booking_milestone_theme.dart';
import 'milestone_progress_bar.dart';
import 'pulsing_status_dot.dart';

/// The ONGOING CARE card on the patient home screen — a live order-tracker in
/// the shape patients already know from food delivery apps.
///
/// Reads entirely off the server-derived milestone block (see
/// `backend/src/utils/bookingMilestones.js`): a pulsing status badge, the
/// six-segment step bar, the current milestone headline, the admin-committed
/// appointment time, and the two actions that matter mid-booking — open the
/// full timeline, or reach a human on WhatsApp.
///
/// There is no GPS in this product; every state shown here comes from an
/// admin milestone update, which is why the appointment TIME (not a live map)
/// is the card's anchor.
class OngoingCareCard extends StatelessWidget {
  final PatientActiveRequest request;

  /// Opens the full vertical timeline (BookingTrackingScreen).
  final VoidCallback onTrackDetails;

  const OngoingCareCard({
    super.key,
    required this.request,
    required this.onTrackDetails,
  });

  BookingMilestone get _milestone => request.milestone;

  /// "Scheduled" once a time is committed, otherwise the label explains that
  /// we're still waiting on one — never show an empty pill.
  String get _timePillText {
    final label = request.scheduledTimeLabel?.trim();
    if (label != null && label.isNotEmpty) return 'Scheduled: $label';
    if (_milestone == BookingMilestone.completed) return 'Visit complete';
    return 'Awaiting scheduled time';
  }

  bool get _hasSchedule =>
      (request.scheduledTimeLabel?.trim().isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    final style = BookingMilestoneTheme.of(context, _milestone);

    return Semantics(
      container: true,
      label: 'Ongoing care. ${request.milestoneHeadline}. $_timePillText',
      child: Container(
        decoration: BoxDecoration(
          color: style.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: style.accent.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusBadgeRow(request: request, style: style),
                  const SizedBox(height: 14),

                  // Current milestone headline — the one line a patient reads.
                  Text(
                    request.milestoneHeadline,
                    style: MtTextStyles.labelLg.copyWith(
                      color: style.title,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (request.serviceTitleEn.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      request.serviceTitleEn,
                      style: MtTextStyles.bodySm.copyWith(color: style.body),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  const SizedBox(height: 14),
                  MilestoneProgressBar(milestone: _milestone, style: style),

                  const SizedBox(height: 14),
                  _AppointmentTimePill(
                    text: _timePillText,
                    style: style,
                    emphasised: _hasSchedule && _milestone.isLive,
                  ),

                  if (request.displayProviderName != null) ...[
                    const SizedBox(height: 14),
                    _ProviderRow(request: request, style: style),
                  ],
                ],
              ),
            ),
            _ActionBar(
              request: request,
              style: style,
              onTrackDetails: onTrackDetails,
            ),
          ],
        ),
      ),
    );
  }
}

/// Pulsing dot + status word on the left, "Step 3 of 6" counter on the right.
class _StatusBadgeRow extends StatelessWidget {
  final PatientActiveRequest request;
  final MilestoneStyle style;
  const _StatusBadgeRow({required this.request, required this.style});

  @override
  Widget build(BuildContext context) {
    final milestone = request.milestone;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: style.accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PulsingStatusDot(
                color: style.accent,
                // Only the genuinely live steps animate — a completed or
                // cancelled booking shows a calm, static dot.
                animate: milestone.isLive,
                // On-the-move steps pulse harder so the card reads as urgent
                // at a glance.
                intense: milestone.isOnTheMove,
              ),
              const SizedBox(width: 8),
              Text(
                milestone.shortLabel,
                style: MtTextStyles.labelSm.copyWith(
                  color: style.accent,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        if (milestone.isLive && milestone.step > 0)
          Text(
            'Step ${milestone.step} of ${BookingMilestoneX.totalSteps}',
            style: MtTextStyles.labelSm.copyWith(
              color: style.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

/// The 🕒 appointment-time pill. This is the card's anchor: with no GPS, the
/// admin-assigned time is what tells the patient when care actually arrives.
class _AppointmentTimePill extends StatelessWidget {
  final String text;
  final MilestoneStyle style;
  final bool emphasised;

  const _AppointmentTimePill({
    required this.text,
    required this.style,
    required this.emphasised,
  });

  @override
  Widget build(BuildContext context) {
    final color = emphasised ? style.accent : style.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: style.surfaceHi,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: MtTextStyles.labelMd.copyWith(
                color: emphasised ? style.title : style.body,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Who is attending — the admin-set provider name, with the paired nurse
/// noted underneath when a visit carries both.
class _ProviderRow extends StatelessWidget {
  final PatientActiveRequest request;
  final MilestoneStyle style;
  const _ProviderRow({required this.request, required this.style});

  @override
  Widget build(BuildContext context) {
    final name = request.displayProviderName ?? '';
    final doctor = request.assignedDoctor;
    final nurse = request.assignedNurse;
    final subtitle = request.providerSpecialization ?? doctor?.specialty;
    // Only call out the nurse separately when they aren't already the person
    // named on the row.
    final showNurse = nurse != null && nurse.fullName != name;

    return Row(
      children: [
        InitialsAvatar(
          name: name,
          size: 38,
          backgroundColor: style.surfaceHi,
          textColor: style.accent,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: MtTextStyles.labelMd.copyWith(
                  color: style.title,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null && subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: MtTextStyles.bodySm.copyWith(color: style.body),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (showNurse)
                Text(
                  'with ${nurse.fullName}',
                  style: MtTextStyles.bodySm.copyWith(color: style.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Track Details + WhatsApp Support, on a raised strip so they read as the
/// card's primary affordances.
class _ActionBar extends StatelessWidget {
  final PatientActiveRequest request;
  final MilestoneStyle style;
  final VoidCallback onTrackDetails;

  const _ActionBar({
    required this.request,
    required this.style,
    required this.onTrackDetails,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: style.surfaceHi,
        border: Border(top: BorderSide(color: style.border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onTrackDetails,
              style: OutlinedButton.styleFrom(
                foregroundColor: style.accent,
                side: BorderSide(color: style.accent.withValues(alpha: 0.6)),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.timeline_rounded, size: 17),
              label: const Text(
                'Track Details',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: WhatsAppSupportButton(
              label: 'WhatsApp',
              message: bookingWhatsAppMessage(
                bookingId: request.id,
                serviceTitle: request.serviceTitleEn,
                scheduledLabel: request.scheduledTimeLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
