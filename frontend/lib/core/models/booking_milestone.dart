import 'package:equatable/equatable.dart';

import 'provider_type.dart';

/// Patient-facing booking lifecycle — the six legible steps behind the
/// ONGOING CARE tracker.
///
/// This mirrors `backend/src/utils/bookingMilestones.js` exactly. The server
/// derives the milestone from the canonical `care_requests.status` (which is
/// far more granular, because payments/dispatch/chat reason off it) and ships
/// it on every booking payload, so the app never re-implements the mapping.
enum BookingMilestone {
  requested,
  confirmed,
  scheduled,
  enRoute,
  inService,
  completed,
  cancelled,
}

extension BookingMilestoneX on BookingMilestone {
  /// Total steps in the ordered lifecycle (cancelled sits outside it).
  static const int totalSteps = 6;

  /// 1-based position, or 0 for [BookingMilestone.cancelled] which has no
  /// place on the progress bar.
  int get step {
    switch (this) {
      case BookingMilestone.requested:
        return 1;
      case BookingMilestone.confirmed:
        return 2;
      case BookingMilestone.scheduled:
        return 3;
      case BookingMilestone.enRoute:
        return 4;
      case BookingMilestone.inService:
        return 5;
      case BookingMilestone.completed:
        return 6;
      case BookingMilestone.cancelled:
        return 0;
    }
  }

  /// Role-aware copy for this step: "Nurse On the Way" / "Doctor On the Way".
  ///
  /// The server already ships resolved labels on every booking payload, so
  /// this is the fallback for an offline render or an older API — but it has
  /// to be role-aware too, otherwise the tracker silently downgrades to
  /// generic "Provider" wording exactly when the network is worst.
  String labelFor(ProviderType type) =>
      type.milestoneCopy(toWire()) ?? label;

  /// Role-neutral default copy for this step.
  String get label {
    switch (this) {
      case BookingMilestone.requested:
        return 'Booking Received — Under Review';
      case BookingMilestone.confirmed:
        return 'Confirmed — Assigning Provider';
      case BookingMilestone.scheduled:
        return 'Provider Assigned — Scheduled';
      case BookingMilestone.enRoute:
        return 'Healthcare Provider On the Way';
      case BookingMilestone.inService:
        return 'Care Session in Progress';
      case BookingMilestone.completed:
        return 'Service Complete';
      case BookingMilestone.cancelled:
        return 'Booking Cancelled';
    }
  }

  /// Short badge copy for the pulsing status chip on the card.
  String get shortLabel {
    switch (this) {
      case BookingMilestone.requested:
        return 'UNDER REVIEW';
      case BookingMilestone.confirmed:
        return 'CONFIRMED';
      case BookingMilestone.scheduled:
        return 'SCHEDULED';
      case BookingMilestone.enRoute:
        return 'ON THE WAY';
      case BookingMilestone.inService:
        return 'IN SERVICE';
      case BookingMilestone.completed:
        return 'COMPLETED';
      case BookingMilestone.cancelled:
        return 'CANCELLED';
    }
  }

  /// True while the booking is still running — drives whether the card shows
  /// live affordances (pulse animation, WhatsApp support, progress bar).
  bool get isLive =>
      this != BookingMilestone.completed && this != BookingMilestone.cancelled;

  /// The steps where a provider is actively moving/working, which the card
  /// animates more insistently.
  bool get isOnTheMove =>
      this == BookingMilestone.enRoute || this == BookingMilestone.inService;

  String toWire() {
    switch (this) {
      case BookingMilestone.requested:
        return 'REQUESTED';
      case BookingMilestone.confirmed:
        return 'CONFIRMED';
      case BookingMilestone.scheduled:
        return 'SCHEDULED';
      case BookingMilestone.enRoute:
        return 'EN_ROUTE';
      case BookingMilestone.inService:
        return 'IN_SERVICE';
      case BookingMilestone.completed:
        return 'COMPLETED';
      case BookingMilestone.cancelled:
        return 'CANCELLED';
    }
  }

  static BookingMilestone fromWire(String? raw) {
    switch (raw?.toUpperCase().replaceAll('-', '_')) {
      case 'REQUESTED':
        return BookingMilestone.requested;
      case 'CONFIRMED':
        return BookingMilestone.confirmed;
      case 'SCHEDULED':
        return BookingMilestone.scheduled;
      case 'EN_ROUTE':
      case 'ENROUTE':
        return BookingMilestone.enRoute;
      case 'IN_SERVICE':
      case 'INSERVICE':
        return BookingMilestone.inService;
      case 'COMPLETED':
        return BookingMilestone.completed;
      case 'CANCELLED':
      case 'CANCELED':
      case 'REJECTED':
        return BookingMilestone.cancelled;
      default:
        return BookingMilestone.requested;
    }
  }
}

/// Where one step sits relative to the booking's current position.
enum MilestoneStepState { done, current, upcoming }

MilestoneStepState _stepStateFromWire(String? raw) {
  switch (raw?.toLowerCase()) {
    case 'done':
      return MilestoneStepState.done;
    case 'current':
      return MilestoneStepState.current;
    default:
      return MilestoneStepState.upcoming;
  }
}

/// One row of the vertical tracking timeline, as computed by the server.
///
/// [timestamp] is null for steps not yet reached, and also for steps a legacy
/// booking passed through before milestone history existed — the UI renders
/// "—" rather than inventing a time.
class MilestoneTimelineEntry extends Equatable {
  final BookingMilestone milestone;
  final int step;
  final int total;
  final String label;
  final MilestoneStepState state;
  final DateTime? timestamp;
  final String? note;

  const MilestoneTimelineEntry({
    required this.milestone,
    required this.step,
    required this.total,
    required this.label,
    required this.state,
    this.timestamp,
    this.note,
  });

  bool get isDone => state == MilestoneStepState.done;
  bool get isCurrent => state == MilestoneStepState.current;

  @override
  List<Object?> get props =>
      [milestone, step, total, label, state, timestamp, note];

  factory MilestoneTimelineEntry.fromJson(
    Map<String, dynamic> json, {
    ProviderType providerType = ProviderTypeX.fallback,
  }) {
    final milestone = BookingMilestoneX.fromWire(json['key']?.toString());
    return MilestoneTimelineEntry(
      milestone: milestone,
      step: (json['step'] as num?)?.toInt() ?? milestone.step,
      total: (json['total'] as num?)?.toInt() ?? BookingMilestoneX.totalSteps,
      // The server's label is already role-aware and folds in the scheduled
      // time; the local one only stands in when it's missing.
      label: json['label']?.toString() ?? milestone.labelFor(providerType),
      state: _stepStateFromWire(json['state']?.toString()),
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? ''),
      note: (json['note']?.toString().isEmpty ?? true)
          ? null
          : json['note'].toString(),
    );
  }

  /// Builds the six-step timeline from a raw `milestone_timeline` array.
  /// Falls back to a locally-derived timeline when the server didn't send one
  /// (older backend, or a cached payload), so the tracking screen is never
  /// blank.
  static List<MilestoneTimelineEntry> listFrom(
    dynamic raw, {
    required BookingMilestone current,
    ProviderType providerType = ProviderTypeX.fallback,
  }) {
    if (raw is List && raw.isNotEmpty) {
      return [
        for (final item in raw)
          if (item is Map)
            MilestoneTimelineEntry.fromJson(
              Map<String, dynamic>.from(item),
              providerType: providerType,
            ),
      ];
    }
    return derive(current, providerType: providerType);
  }

  /// Client-side fallback: the ordered six steps positioned against [current],
  /// worded for [providerType], with no timestamps (we have no history to draw
  /// them from).
  static List<MilestoneTimelineEntry> derive(
    BookingMilestone current, {
    ProviderType providerType = ProviderTypeX.fallback,
  }) {
    const ordered = [
      BookingMilestone.requested,
      BookingMilestone.confirmed,
      BookingMilestone.scheduled,
      BookingMilestone.enRoute,
      BookingMilestone.inService,
      BookingMilestone.completed,
    ];
    final cancelled = current == BookingMilestone.cancelled;
    return [
      for (final m in ordered)
        MilestoneTimelineEntry(
          milestone: m,
          step: m.step,
          total: BookingMilestoneX.totalSteps,
          label: m.labelFor(providerType),
          state: cancelled
              ? MilestoneStepState.upcoming
              : m.step < current.step
                  ? MilestoneStepState.done
                  : m.step == current.step
                      ? MilestoneStepState.current
                      : MilestoneStepState.upcoming,
        ),
    ];
  }
}
