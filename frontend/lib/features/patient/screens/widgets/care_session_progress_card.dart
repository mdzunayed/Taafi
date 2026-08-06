import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/mt_text_styles.dart';
import 'booking_milestone_theme.dart';

/// What the patient sees while the visit is actually happening.
///
/// Two honest things, and deliberately nothing else:
///
///  1. **How long the session has been running**, counted from the server's
///     `IN_SERVICE` timestamp. When the payload carries no stamp (an older
///     booking, or a step reached through a flow that skipped status history)
///     the timer is omitted rather than started from "now" — a counter that
///     resets every time the tab is reopened is worse than no counter.
///  2. **What a visit involves**, labelled as an expectation. There is no
///     patient-facing checklist in the backend: the care log lives in the
///     provider console and is filed in one go at the end. Rendering these as
///     ticking-off progress would be inventing live state, so they read as
///     "what happens", not "what has happened".
class CareSessionProgressCard extends StatefulWidget {
  /// Server `IN_SERVICE` timestamp. Null when the payload has none.
  final DateTime? startedAt;

  /// Names the attending role in the copy — "Your Nurse is with you".
  final String roleLabel;

  final MilestoneStyle style;

  const CareSessionProgressCard({
    super.key,
    required this.startedAt,
    required this.roleLabel,
    required this.style,
  });

  @override
  State<CareSessionProgressCard> createState() =>
      _CareSessionProgressCardState();
}

class _CareSessionProgressCardState extends State<CareSessionProgressCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    if (widget.startedAt != null) {
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    }
  }

  @override
  void didUpdateWidget(covariant CareSessionProgressCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A refresh landed the start time the first payload was missing.
    if (widget.startedAt != null && _ticker == null) {
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// "07:42" under an hour, "1:07:42" past it.
  String? get _elapsed {
    final start = widget.startedAt;
    if (start == null) return null;
    var d = DateTime.now().difference(start);
    // Clock skew between the device and the server can make a just-started
    // session read as negative. Floor it rather than print "-00:03".
    if (d.isNegative) d = Duration.zero;
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$mm:$ss';
    return '$mm:$ss';
  }

  static const _expectations = <({IconData icon, String label})>[
    (icon: Icons.monitor_heart_outlined, label: 'Assessment & vitals'),
    (icon: Icons.medical_services_outlined, label: 'Treatment or procedure'),
    (icon: Icons.edit_note_outlined, label: 'Care notes filed'),
    (
      icon: Icons.receipt_long_outlined,
      label: 'Prescription issued after settlement',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final elapsed = _elapsed;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: style.surfaceHi,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: style.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timer_outlined, size: 20, color: style.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your ${widget.roleLabel} is with you',
                  style: MtTextStyles.labelMd.copyWith(
                    color: style.title,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (elapsed != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: style.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    elapsed,
                    style: MtTextStyles.labelMd.copyWith(
                      color: style.accent,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'WHAT HAPPENS DURING YOUR VISIT',
            style: MtTextStyles.sectionLabel.copyWith(
              color: style.muted,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          for (final item in _expectations)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(item.icon, size: 16, color: style.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.label,
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
