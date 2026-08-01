import 'package:flutter/material.dart';

import '../../../../core/models/booking_milestone.dart';
import 'patient_home_palette.dart';

/// Colours for one milestone, resolved against the ambient patient palette.
///
/// The accent is what carries the state: amber while the booking waits on a
/// human, violet once it's confirmed, orange when a time is locked in, and
/// green the moment care is actually moving toward the patient — the same
/// read-at-a-glance convention delivery apps use.
@immutable
class MilestoneStyle {
  final Color accent;
  final Color surface;
  final Color surfaceHi;
  final Color border;
  final Color title;
  final Color body;
  final Color muted;

  const MilestoneStyle({
    required this.accent,
    required this.surface,
    required this.surfaceHi,
    required this.border,
    required this.title,
    required this.body,
    required this.muted,
  });
}

class BookingMilestoneTheme {
  BookingMilestoneTheme._();

  static MilestoneStyle of(BuildContext context, BookingMilestone milestone) {
    final hd = HomeDark.of(context);
    return MilestoneStyle(
      accent: accentFor(context, milestone),
      surface: hd.surface,
      surfaceHi: hd.surfaceHi,
      border: hd.border,
      title: hd.title,
      body: hd.body,
      muted: hd.muted,
    );
  }

  /// Status colour for [milestone]. Kept public so the timeline screen paints
  /// each step with the same language as the card.
  static Color accentFor(BuildContext context, BookingMilestone milestone) {
    final hd = HomeDark.of(context);
    switch (milestone) {
      case BookingMilestone.requested:
        // Still with the review desk — neutral-warm, not yet actionable.
        return hd.violetBright;
      case BookingMilestone.confirmed:
        return hd.indigo;
      case BookingMilestone.scheduled:
        // Orange: a time is committed, the visit is queued.
        return hd.accent;
      case BookingMilestone.enRoute:
      case BookingMilestone.inService:
        // Green: care is actively moving toward / with the patient.
        return hd.positive;
      case BookingMilestone.completed:
        return hd.positive;
      case BookingMilestone.cancelled:
        return hd.danger;
    }
  }
}
