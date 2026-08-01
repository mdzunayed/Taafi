import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/patient_home_repository.dart';
import '../../../core/config/support_config.dart';
import '../../../core/models/booking_milestone.dart';
import '../../../core/models/patient_active_request.dart';
import '../../../core/models/provider_type.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/utils/whatsapp_support.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/whatsapp_support_button.dart';
import '../../auth/auth_provider.dart';
import 'widgets/assigned_provider_card.dart';
import 'widgets/booking_milestone_theme.dart';
import 'widgets/milestone_progress_bar.dart';
import 'widgets/patient_home_palette.dart';
import 'widgets/preparation_tips_banner.dart';
import 'widgets/pulsing_status_dot.dart';

/// Whether the care-team roster is worth its own section.
///
/// It exists to name people the direct-contact card above does NOT already
/// show — a nurse attending alongside the doctor the patient calls. Repeating
/// a single provider in two cards just pads the screen, so a solo visit shows
/// only the contact card.
bool _showsCareTeam(PatientActiveRequest request) {
  final contact = request.assignedProvider;
  final showingContact = contact != null && request.isProviderActive;
  final names = <String>{
    if (request.assignedDoctor != null) request.assignedDoctor!.fullName.trim(),
    if (request.assignedNurse != null) request.assignedNurse!.fullName.trim(),
    if (!showingContact && request.displayProviderName != null)
      request.displayProviderName!.trim(),
  }..removeWhere((n) => n.isEmpty || (showingContact && n == contact.name.trim()));
  return names.isNotEmpty;
}

/// Pushes the detailed tracker for [request]. Single entry point so every
/// "Track Details" affordance opens the same screen the same way.
Future<void> openBookingTracking(
  BuildContext context,
  PatientActiveRequest request,
) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => BookingTrackingScreen(initialRequest: request),
    ),
  );
}

/// Full-screen booking tracker: the six-step vertical timeline, the assigned
/// provider's details, and the exact appointment window.
///
/// Watches [patientActiveRequestProvider] rather than holding the request it
/// was pushed with, so an admin milestone update (socket push or poll) moves
/// this screen live while the patient is looking at it.
class BookingTrackingScreen extends ConsumerWidget {
  /// The booking as of navigation time — the fallback if the live provider
  /// has since dropped the request (e.g. it completed and left the feed).
  final PatientActiveRequest initialRequest;

  const BookingTrackingScreen({super.key, required this.initialRequest});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(patientActiveRequestProvider);
    // Never swap in a *different* booking — only track updates to this one.
    final request =
        (live != null && live.id == initialRequest.id) ? live : initialRequest;

    final hd = HomeDark.of(context);
    final style = BookingMilestoneTheme.of(context, request.milestone);

    // The dispatched provider's contact card, but only inside the window where
    // contacting them makes sense: from the moment a time is committed until
    // the visit ends. Before that there is nobody to call; after it, the
    // support desk is the right channel.
    final provider = request.assignedProvider;
    final showProviderCard = provider != null && request.isProviderActive;
    final tip = request.preparationTip;
    final patientName = ref.watch(currentUserProvider)?.name ?? '';

    return Scaffold(
      backgroundColor: hd.canvas,
      appBar: AppBar(
        backgroundColor: hd.canvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: hd.title,
        elevation: 0,
        title: Text(
          'Track your booking',
          style: MtTextStyles.h2.copyWith(color: hd.title),
        ),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: hd.violetBright,
          backgroundColor: hd.surfaceHi,
          onRefresh: () => ref.read(patientHomeFeedProvider.notifier).refresh(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              _SummaryCard(request: request, style: style),

              // Who is coming, and how to reach them — placed directly under
              // the status because it is the reason most patients open this
              // screen at all once a provider is on the way.
              if (showProviderCard) ...[
                const SizedBox(height: 18),
                _SectionLabel(
                  text: 'YOUR ${provider.type.roleLabel.toUpperCase()}',
                  color: hd.muted,
                ),
                const SizedBox(height: 10),
                AssignedProviderCard(
                  provider: provider,
                  style: style,
                  milestone: request.milestone,
                  scheduledLabel: request.scheduledTimeLabel,
                  whatsAppMessage: providerWhatsAppMessage(
                    patientName: patientName,
                    bookingId: request.id,
                    serviceTitle: request.serviceTitleEn,
                    scheduledLabel: request.scheduledTimeLabel,
                  ),
                ),
              ],

              // Role-specific prep guidance, only while it can still be acted
              // on (EN_ROUTE / IN_SERVICE — see `preparationTip`).
              if (tip != null) ...[
                // Tighter under the provider card (they read as one block),
                // full section spacing when it follows the summary alone.
                SizedBox(height: showProviderCard ? 14 : 18),
                PreparationTipsBanner(
                  tip: tip,
                  roleLabel: request.providerRoleLabel,
                  style: style,
                ),
              ],

              const SizedBox(height: 18),
              _SectionLabel(text: 'BOOKING TIMELINE', color: hd.muted),
              const SizedBox(height: 10),
              _Timeline(request: request, style: style),

              // The rest of the dispatched team, when there is one beyond the
              // direct contact above (a nurse attending alongside a doctor).
              // Suppressed entirely when it would just repeat the card above.
              if (_showsCareTeam(request)) ...[
                const SizedBox(height: 22),
                _SectionLabel(text: 'YOUR CARE TEAM', color: hd.muted),
                const SizedBox(height: 10),
                _CareTeamCard(request: request, style: style),
              ],

              const SizedBox(height: 22),
              _SectionLabel(text: 'TAAFI SUPPORT DESK', color: hd.muted),
              const SizedBox(height: 10),
              _SupportDeskCard(request: request, style: style),
              const SizedBox(height: 12),
              Text(
                'Booking ID  #${request.id}',
                textAlign: TextAlign.center,
                style: MtTextStyles.bodySm.copyWith(color: hd.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionLabel({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: MtTextStyles.sectionLabel.copyWith(color: color, letterSpacing: 1),
    );
  }
}

/// Current state at a glance: status badge, headline, step bar, and the
/// committed appointment window.
class _SummaryCard extends StatelessWidget {
  final PatientActiveRequest request;
  final MilestoneStyle style;
  const _SummaryCard({required this.request, required this.style});

  @override
  Widget build(BuildContext context) {
    final milestone = request.milestone;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: style.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: style.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PulsingStatusDot(
                color: style.accent,
                animate: milestone.isLive,
                intense: milestone.isOnTheMove,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  milestone.shortLabel,
                  style: MtTextStyles.labelSm.copyWith(
                    color: style.accent,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              if (milestone.isLive && milestone.step > 0)
                Text(
                  'Step ${milestone.step} of ${BookingMilestoneX.totalSteps}',
                  style: MtTextStyles.labelSm.copyWith(
                    color: style.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            request.milestoneHeadline,
            style: MtTextStyles.labelLg.copyWith(
              color: style.title,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          if (request.serviceTitleEn.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              request.serviceTitleEn,
              style: MtTextStyles.bodyMd.copyWith(color: style.body),
            ),
          ],
          const SizedBox(height: 14),
          MilestoneProgressBar(milestone: milestone, style: style),
          const SizedBox(height: 16),
          _ScheduleBlock(request: request, style: style),
        ],
      ),
    );
  }
}

/// The exact appointment window the admin committed to, plus the visit's
/// expected duration where the booking carries one.
class _ScheduleBlock extends StatelessWidget {
  final PatientActiveRequest request;
  final MilestoneStyle style;
  const _ScheduleBlock({required this.request, required this.style});

  /// Full, unambiguous rendering ("Mon, 12 Aug 2026 · 04:00 PM") to sit under
  /// the server's relative label — a patient planning their day needs the date.
  String? get _absolute {
    final at = request.scheduledTime;
    if (at == null) return null;
    return DateFormat('EEE, d MMM y · hh:mm a').format(at.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final label = request.scheduledTimeLabel?.trim();
    final hasTime = label != null && label.isNotEmpty;
    final duration = request.durationHours;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: style.surfaceHi,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: style.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.event_available_rounded, size: 18, color: style.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasTime ? 'Scheduled appointment' : 'Appointment time',
                  style: MtTextStyles.labelSm.copyWith(color: style.muted),
                ),
                const SizedBox(height: 3),
                Text(
                  hasTime ? label : 'Your care team will confirm this shortly',
                  style: MtTextStyles.labelMd.copyWith(
                    color: style.title,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (hasTime && _absolute != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _absolute!,
                    style: MtTextStyles.bodySm.copyWith(color: style.body),
                  ),
                ],
                if (duration != null && duration > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Expected duration · ${duration}h',
                    style: MtTextStyles.bodySm.copyWith(color: style.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The vertical stepper: completed steps checked off, the current step
/// highlighted and pulsing, future steps dimmed.
class _Timeline extends StatelessWidget {
  final PatientActiveRequest request;
  final MilestoneStyle style;
  const _Timeline({required this.request, required this.style});

  @override
  Widget build(BuildContext context) {
    final entries = request.resolvedTimeline;
    final cancelled = request.milestone == BookingMilestone.cancelled;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      decoration: BoxDecoration(
        color: style.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: style.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++)
            _TimelineRow(
              entry: entries[i],
              style: style,
              isLast: i == entries.length - 1,
              cancelled: cancelled,
            ),
          if (cancelled)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
              child: Row(
                children: [
                  Icon(Icons.cancel_rounded, size: 18, color: style.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This booking was cancelled. Remaining steps will not run.',
                      style: MtTextStyles.bodySm.copyWith(color: style.body),
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

class _TimelineRow extends StatelessWidget {
  final MilestoneTimelineEntry entry;
  final MilestoneStyle style;
  final bool isLast;
  final bool cancelled;

  const _TimelineRow({
    required this.entry,
    required this.style,
    required this.isLast,
    required this.cancelled,
  });

  /// Per-step accent, so a done step keeps its own milestone colour rather
  /// than inheriting the booking's current one.
  Color _accent(BuildContext context) =>
      BookingMilestoneTheme.accentFor(context, entry.milestone);

  @override
  Widget build(BuildContext context) {
    final reached = entry.isDone || entry.isCurrent;
    final accent = reached ? _accent(context) : style.muted;
    final dim = style.muted.withValues(alpha: 0.35);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rail: node + connector down to the next step.
          Column(
            children: [
              const SizedBox(height: 14),
              _Node(
                entry: entry,
                accent: accent,
                dim: dim,
                surface: style.surface,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: entry.isDone && !cancelled ? accent : dim,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(0, 12, 0, isLast ? 14 : 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.label,
                    style: MtTextStyles.labelMd.copyWith(
                      color: reached ? style.title : style.muted,
                      fontWeight:
                          entry.isCurrent ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  if (entry.timestamp != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      DateFormat('d MMM, hh:mm a')
                          .format(entry.timestamp!.toLocal()),
                      style: MtTextStyles.bodySm.copyWith(color: style.body),
                    ),
                  ],
                  if (entry.note != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      entry.note!,
                      style: MtTextStyles.bodySm.copyWith(color: style.muted),
                    ),
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

/// Timeline node: a filled check for done, a pulsing ring for the current
/// step, a hollow dot for what's still ahead.
class _Node extends StatelessWidget {
  final MilestoneTimelineEntry entry;
  final Color accent;
  final Color dim;
  final Color surface;

  const _Node({
    required this.entry,
    required this.accent,
    required this.dim,
    required this.surface,
  });

  @override
  Widget build(BuildContext context) {
    if (entry.isCurrent) {
      return SizedBox(
        width: 24,
        height: 24,
        child: Center(
          child: PulsingStatusDot(color: accent, size: 12),
        ),
      );
    }
    if (entry.isDone) {
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        child: Icon(Icons.check_rounded, size: 15, color: surface),
      );
    }
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: dim, width: 2),
      ),
    );
  }
}

/// The wider dispatched team — everyone attending who is not the direct
/// contact rendered by [AssignedProviderCard] above.
///
/// Informational only: coordination goes through the one provider the patient
/// calls, so these rows carry no action buttons. Whoever is already shown as
/// the contact is filtered out rather than repeated.
class _CareTeamCard extends StatelessWidget {
  final PatientActiveRequest request;
  final MilestoneStyle style;
  const _CareTeamCard({required this.request, required this.style});

  @override
  Widget build(BuildContext context) {
    final doctor = request.assignedDoctor;
    final nurse = request.assignedNurse;
    final contact = request.isProviderActive ? request.assignedProvider : null;
    final contactName = contact?.name.trim();

    bool isContact(String name) =>
        contactName != null && name.trim() == contactName;

    final rows = <Widget>[];

    if (doctor != null && !isContact(doctor.fullName)) {
      rows.add(
        _PersonRow(
          name: doctor.fullName,
          photoUrl: doctor.profilePicture,
          // Falls through the doctor's own fields before the request's
          // denormalised copy; blank when the profile carries neither.
          qualification: doctor.specialty.isNotEmpty
              ? doctor.specialty
              : (doctor.degrees ?? request.providerSpecialization ?? ''),
          roleLabel: 'Doctor',
          style: style,
        ),
      );
    }
    if (nurse != null && !isContact(nurse.fullName)) {
      rows.add(
        _PersonRow(
          name: nurse.fullName,
          photoUrl: nurse.profilePicture,
          qualification: nurse.qualifications ??
              (nurse.specialty.isNotEmpty ? nurse.specialty : ''),
          roleLabel: 'Nurse',
          style: style,
        ),
      );
    }
    // An admin-named provider with no linked profile row (e.g. an agency
    // nurse) — the only thing we know is the name the admin typed.
    final named = request.displayProviderName?.trim();
    if (rows.isEmpty && named != null && named.isNotEmpty && !isContact(named)) {
      rows.add(
        _PersonRow(
          name: named,
          photoUrl: request.providerAvatarUrl,
          qualification: request.providerSpecialization ?? '',
          roleLabel: null,
          style: style,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: style.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: style.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(color: style.border, height: 22),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// Taafi's own channel, kept deliberately below and visually quieter than the
/// provider card: this is where payment questions, complaints and emergencies
/// go — not "how far away are you". Always present, including before a
/// provider is assigned and after the visit ends, because it is the only
/// contact that is valid at every stage of a booking.
class _SupportDeskCard extends StatelessWidget {
  final PatientActiveRequest request;
  final MilestoneStyle style;
  const _SupportDeskCard({required this.request, required this.style});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: style.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: style.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Payment questions, or something urgent?',
            style: MtTextStyles.labelMd.copyWith(
              color: style.title,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            SupportConfig.supportHoursLabel,
            style: MtTextStyles.bodySm.copyWith(color: style.muted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => launchPhoneCall(
                    context,
                    phone: SupportConfig.supportPhone,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: style.title,
                    side: BorderSide(color: style.border),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.support_agent_rounded, size: 18),
                  label: const Text('Call support',
                      overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: WhatsAppSupportButton(
                  label: 'WhatsApp',
                  outlined: true,
                  message: bookingWhatsAppMessage(
                    bookingId: request.id,
                    serviceTitle: request.serviceTitleEn,
                    scheduledLabel: request.scheduledTimeLabel,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final String qualification;
  final String? roleLabel;
  final MilestoneStyle style;

  const _PersonRow({
    required this.name,
    required this.photoUrl,
    required this.qualification,
    required this.roleLabel,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final url = photoUrl?.trim() ?? '';
    return Row(
      children: [
        // Photo when the provider has one; initials are the placeholder.
        if (url.isNotEmpty)
          ClipOval(
            child: Image.network(
              url,
              width: 46,
              height: 46,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => InitialsAvatar(
                name: name,
                size: 46,
                backgroundColor: style.surfaceHi,
                textColor: style.accent,
              ),
            ),
          )
        else
          InitialsAvatar(
            name: name,
            size: 46,
            backgroundColor: style.surfaceHi,
            textColor: style.accent,
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      style: MtTextStyles.labelLg.copyWith(
                        color: style.title,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (roleLabel != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: style.accent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        roleLabel!,
                        style: MtTextStyles.labelSm.copyWith(
                          color: style.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              // Omitted rather than shown blank when the provider's profile
              // carries no specialty or degrees — nothing is invented here.
              if (qualification.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  qualification,
                  style: MtTextStyles.bodySm.copyWith(color: style.body),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
