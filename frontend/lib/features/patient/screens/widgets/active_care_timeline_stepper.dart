import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/active_care_step.dart';
import '../../../../core/models/booking_milestone.dart';
import '../../../../core/models/deposit_status.dart';
import '../../../../core/models/patient_active_request.dart';
import '../booking_flow_pages.dart' show money;
import 'booking_milestone_theme.dart';
import 'patient_home_palette.dart';

/// The single lifecycle timeline for the patient's active booking.
///
/// Replaces the two rails that used to disagree with each other: the review
/// tab painted a five-step "Request submitted → Admin reviewing → Doctor
/// assigned → Doctor confirms → On the way" list derived client-side from
/// `PatientRequestStatus`, while the tracking tab painted a six-step list
/// derived from the server's `milestone_timeline`. A patient who moved between
/// the two tabs saw two different answers to "where is my booking".
///
/// This is the one answer. Steps come from [ActiveCareTimeline] — server
/// milestone, server deposit state, server timestamps — and each row can carry
/// the action that belongs to it, so the patient never has to leave the
/// timeline to pay the deposit, see who is coming, or settle the balance.
class ActiveCareTimelineStepper extends StatelessWidget {
  final PatientActiveRequest request;

  /// Contextual widget inlined beneath a step's copy — the deposit CTA under
  /// [ActiveCareStep.feeSet], the provider card under
  /// [ActiveCareStep.teamAssigned], the invoice under [ActiveCareStep.settled].
  ///
  /// Callers pass only the entries that apply right now; a step with no entry
  /// renders as a plain row.
  final Map<ActiveCareStep, Widget> stepActions;

  const ActiveCareTimelineStepper({
    super.key,
    required this.request,
    this.stepActions = const {},
  });

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final timeline = ActiveCareTimeline(request);

    return Container(
      decoration: BoxDecoration(
        color: hd.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hd.border),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR CARE TIMELINE',
            style: TextStyle(
              color: hd.muted,
              fontSize: 11,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          if (timeline.isCancelled) ...[
            const _CancelledBanner(),
            const SizedBox(height: 14),
          ],
          for (final step in ActiveCareStep.values)
            _StepRow(
              step: step,
              timeline: timeline,
              action: stepActions[step],
              isLast: step == ActiveCareStep.values.last,
            ),
        ],
      ),
    );
  }
}

/// Wording for one row. Role-aware ("Nurse En Route", not "Provider En
/// Route") and state-aware — an upcoming step describes what will happen, a
/// current one what is happening, a done one what happened.
@immutable
class _StepCopy {
  final String title;
  final String detail;
  final String glyph;

  const _StepCopy({
    required this.title,
    required this.detail,
    required this.glyph,
  });

  factory _StepCopy.of(
    ActiveCareStep step,
    ActiveCareTimeline timeline,
    MilestoneStepState state,
  ) {
    final r = timeline.request;
    final role = r.providerRoleLabel;
    final current = state == MilestoneStepState.current;
    final upcoming = state == MilestoneStepState.upcoming;
    // Server-resolved: what was paid if paid, what the admin set if not. Gated
    // on `needsDeposit` / `depositStatus` everywhere it renders as a price, so
    // Phase 1 never names an amount nobody has asked for.
    final depositLabel = money(r.depositDue);
    final providerName = r.displayProviderName?.trim();

    switch (step) {
      case ActiveCareStep.submitted:
        return _StepCopy(
          glyph: '📝',
          title: 'Request Submitted',
          detail: current
              ? 'Request received. Care team preparing consultation call.'
              : 'Placed free — no payment taken at booking.',
        );

      case ActiveCareStep.feeSet:
        return _StepCopy(
          glyph: '📞',
          title: 'Admin Call & Fee Set',
          detail: upcoming
              ? 'Your care team calls to discuss your case and set the fee.'
              : current
                  ? r.depositStatus == DepositStatus.failed
                      ? 'Your last $depositLabel deposit attempt did not go '
                          'through. Try again to confirm your visit.'
                      : 'Fee confirmed on your review call. Pay the '
                          '$depositLabel deposit to confirm your visit.'
                  : r.depositStatus.isConfirmed
                      ? 'Deposit $depositLabel paid — deducted from your '
                          'final bill.'
                      : 'Fee set by your care team.',
        );

      case ActiveCareStep.teamAssigned:
        return _StepCopy(
          glyph: '🧑‍⚕️',
          title: '$role Assigned',
          detail: upcoming
              ? 'We match your $role once the deposit clears.'
              : providerName != null && providerName.isNotEmpty
                  ? '$providerName assigned to your visit'
                  : current
                      ? 'Matching the right $role for you'
                      : '$role assigned',
        );

      case ActiveCareStep.enRoute:
        return _StepCopy(
          glyph: '🚗',
          title: '$role En Route',
          detail: upcoming
              ? "You'll see an update the moment they set off."
              : '$role is on the way to your location.',
        );

      case ActiveCareStep.inService:
        return _StepCopy(
          glyph: '🩺',
          title: 'Care Session In Progress',
          detail: upcoming
              ? 'Begins when your $role arrives at your address.'
              : current
                  ? 'Your $role is with you now.'
                  : 'Care session completed.',
        );

      case ActiveCareStep.settled:
        final owed = r.outstandingBalance;
        return _StepCopy(
          glyph: '✅',
          title: 'Completed & Settled',
          detail: upcoming
              ? 'Invoice and prescription unlock once your visit ends.'
              : current
                  ? owed > 0
                      ? 'Visit finished — ${money(owed)} left to settle.'
                      : r.isAwaitingPaymentVerification
                          ? 'Payment received — your care team is verifying it.'
                          : 'Visit finished — wrapping up your records.'
                  : 'Visit complete. Prescription and invoice are in your '
                      'records.',
        );
    }
  }
}

class _StepRow extends StatelessWidget {
  final ActiveCareStep step;
  final ActiveCareTimeline timeline;
  final Widget? action;
  final bool isLast;

  const _StepRow({
    required this.step,
    required this.timeline,
    required this.action,
    required this.isLast,
  });

  /// "4:12 PM" for today, "12 Aug, 4:12 PM" otherwise. Only reached steps
  /// carry a stamp — an upcoming step shows its description instead, never a
  /// made-up time.
  String? _stamp() {
    final at = timeline.stampOf(step);
    if (at == null) return null;
    final now = DateTime.now();
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    return DateFormat(sameDay ? 'h:mm a' : 'd MMM, h:mm a').format(at);
  }

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    final state = timeline.stateOf(step);
    final done = state == MilestoneStepState.done;
    final current = state == MilestoneStepState.current;
    final reached = done || current;
    final accent =
        BookingMilestoneTheme.accentFor(context, step.stampMilestone);
    final copy = _StepCopy.of(step, timeline, state);
    final stamp = _stamp();
    final inlineAction = action;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: reached
                      ? accent.withValues(alpha: current ? 0.20 : 0.12)
                      : hd.surfaceHi,
                  border: Border.all(
                    color: reached ? accent : hd.border,
                    width: current ? 2 : 1,
                  ),
                ),
                child: Text(
                  copy.glyph,
                  style: TextStyle(
                    fontSize: 15,
                    // An upcoming step's glyph is dimmed rather than hidden,
                    // so the patient can read the whole journey up front.
                    color: reached ? null : hd.muted,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: done ? accent : hd.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 4, bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          copy.title,
                          style: TextStyle(
                            color: reached ? hd.title : hd.muted,
                            fontSize: 14,
                            fontWeight:
                                current ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (current)
                        _NowBadge(accent: accent)
                      else if (stamp != null)
                        Text(
                          stamp,
                          style: TextStyle(color: hd.muted, fontSize: 11.5),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    copy.detail,
                    style: TextStyle(
                      color: current ? hd.body : hd.muted,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                  // A reached step that also carries a time keeps it on its
                  // own line when the NOW badge above took the slot.
                  if (current && stamp != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      stamp,
                      style: TextStyle(color: hd.muted, fontSize: 11.5),
                    ),
                  ],
                  // The action lives inside the step it belongs to. Paying the
                  // deposit and seeing who is coming are the two things a
                  // waiting patient opens this screen for; making them scroll
                  // past the timeline to find either is what the two old tabs
                  // did.
                  if (inlineAction != null) ...[
                    const SizedBox(height: 12),
                    inlineAction,
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NowBadge extends StatelessWidget {
  final Color accent;
  const _NowBadge({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'NOW',
        style: TextStyle(
          color: accent,
          fontSize: 9.5,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CancelledBanner extends StatelessWidget {
  const _CancelledBanner();

  @override
  Widget build(BuildContext context) {
    final hd = HomeDark.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hd.dangerBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hd.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.cancel_outlined, size: 18, color: hd.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This booking was cancelled. The steps below show how far it '
              'got before it stopped.',
              style: TextStyle(color: hd.body, fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
