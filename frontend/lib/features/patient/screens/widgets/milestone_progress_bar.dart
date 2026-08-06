import 'package:flutter/material.dart';

import '../../../../core/models/booking_milestone.dart';
import 'booking_milestone_theme.dart';

/// Six-segment horizontal step bar — "how far along is my booking".
///
/// Each segment is one milestone. Completed and current segments fill with the
/// milestone accent; the rest stay as dim rails. The current segment animates
/// its fill so a milestone push visibly advances the bar instead of snapping.
///
/// A cancelled booking renders every segment dim: the visit stopped, and
/// showing partial "progress" toward a service that isn't coming would be a
/// lie the patient has to decode.
class MilestoneProgressBar extends StatelessWidget {
  final BookingMilestone milestone;
  final MilestoneStyle style;
  final double height;

  /// 1-based step to fill up to, when the caller groups the lifecycle
  /// differently from the server's milestones.
  ///
  /// The Active Care tracker splits the deposit gate out of `REQUESTED` into
  /// its own patient-facing step (see `ActiveCareStep`), so its bar has to
  /// fill against that grouping — otherwise the rail and the timeline beneath
  /// it report different positions for the same booking. Everything else
  /// leaves this null and follows [milestone] directly.
  final int? stepOverride;

  const MilestoneProgressBar({
    super.key,
    required this.milestone,
    required this.style,
    this.height = 6,
    this.stepOverride,
  });

  @override
  Widget build(BuildContext context) {
    final current = stepOverride ?? milestone.step;
    final cancelled = milestone == BookingMilestone.cancelled;

    return Row(
      children: [
        for (var step = 1; step <= BookingMilestoneX.totalSteps; step++) ...[
          if (step > 1) const SizedBox(width: 5),
          Expanded(
            child: _Segment(
              height: height,
              // Every step up to and including the current one is filled.
              filled: !cancelled && step <= current,
              // Only the leading edge animates — earlier segments are settled
              // history and shouldn't re-run their fill on every rebuild.
              animate: !cancelled && step == current,
              color: style.accent,
              railColor: style.muted.withValues(alpha: 0.22),
            ),
          ),
        ],
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  final double height;
  final bool filled;
  final bool animate;
  final Color color;
  final Color railColor;

  const _Segment({
    required this.height,
    required this.filled,
    required this.animate,
    required this.color,
    required this.railColor,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height);
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        height: height,
        color: railColor,
        child: filled
            ? (animate
                ? TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 520),
                    curve: Curves.easeOutCubic,
                    builder: (context, t, _) => FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: t,
                      child: ColoredBox(color: color),
                    ),
                  )
                : ColoredBox(color: color))
            : null,
      ),
    );
  }
}
