import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors_ext.dart';
import '../../../../core/theme/mt_text_styles.dart';

/// The three stops of the care-booking checkout.
enum BookingStep { service, summary, checkout }

extension BookingStepX on BookingStep {
  /// 1-based position, as shown inside the node circle.
  int get number => index + 1;

  String get label {
    switch (this) {
      case BookingStep.service:
        return 'Service';
      case BookingStep.summary:
        return 'Summary';
      case BookingStep.checkout:
        return 'Checkout';
    }
  }

  bool isDone(BookingStep current) => index < current.index;
  bool isCurrent(BookingStep current) => index == current.index;
}

/// Sticky progress indicator carried across all three checkout screens.
///
/// Completed steps collapse to a filled dark node with a check; the current
/// step is a filled brand node with an emphasised label; upcoming steps stay
/// outlined and muted. The connector between two nodes fills only when the
/// step on its left is complete, so the bar reads as a progress track rather
/// than three unrelated badges.
class BookingStepper extends StatelessWidget {
  final BookingStep current;

  /// Tapping a *completed* step walks back to it. `null` (the default)
  /// leaves the stepper purely indicative — correct on the first step, where
  /// there is nothing behind it to return to.
  final ValueChanged<BookingStep>? onStepTapped;

  const BookingStepper({super.key, required this.current, this.onStepTapped});

  @override
  Widget build(BuildContext context) {
    final steps = BookingStep.values;
    return Semantics(
      label: 'Booking progress: step ${current.number} of ${steps.length}, '
          '${current.label}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            _StepNode(
              step: steps[i],
              current: current,
              onTap: steps[i].isDone(current) && onStepTapped != null
                  ? () => onStepTapped!(steps[i])
                  : null,
            ),
            if (i < steps.length - 1)
              Expanded(
                child: _Connector(filled: steps[i].isDone(current)),
              ),
          ],
        ],
      ),
    );
  }
}

class _StepNode extends StatelessWidget {
  final BookingStep step;
  final BookingStep current;
  final VoidCallback? onTap;

  const _StepNode({required this.step, required this.current, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final done = step.isDone(current);
    final active = step.isCurrent(current);

    final Color fill;
    final Color border;
    final Color fg;
    if (done) {
      // Completed — solid dark chip, the "already banked" state.
      fill = c.title;
      border = c.title;
      fg = c.surface;
    } else if (active) {
      fill = c.brand;
      border = c.brand;
      fg = Colors.white;
    } else {
      fill = c.surfaceHi;
      border = c.cardBorder;
      fg = c.muted;
    }

    final node = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(color: border, width: 1.4),
            boxShadow: active
                ? [BoxShadow(color: c.glow, blurRadius: 10, spreadRadius: 1)]
                : null,
          ),
          alignment: Alignment.center,
          child: done
              ? Icon(Icons.check_rounded, size: 17, color: fg)
              : Text(
                  '${step.number}',
                  style: MtTextStyles.labelMd.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
        const SizedBox(height: 6),
        Text(
          step.label,
          style: MtTextStyles.labelMd.copyWith(
            color: active ? c.brand : (done ? c.title : c.muted),
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );

    if (onTap == null) return node;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: node,
      ),
    );
  }
}

class _Connector extends StatelessWidget {
  final bool filled;
  const _Connector({required this.filled});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Padding(
      // Centres the rule on the 30px node without pushing the labels around.
      padding: const EdgeInsets.only(top: 14, left: 6, right: 6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 2,
        decoration: BoxDecoration(
          color: filled ? c.title : c.cardBorder,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Sticky top chrome shared by every checkout screen: back affordance,
/// screen title, and the [BookingStepper] pinned underneath. Screens place
/// this as the first child of a [Column] with the scrollable body in an
/// [Expanded], so it never scrolls away.
class BookingFlowHeader extends StatelessWidget {
  final String title;

  /// Optional second line — e.g. the service being booked.
  final String? subtitle;
  final BookingStep step;
  final VoidCallback onBack;
  final ValueChanged<BookingStep>? onStepTapped;

  const BookingFlowHeader({
    super.key,
    required this.title,
    required this.step,
    required this.onBack,
    this.subtitle,
    this.onStepTapped,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.cardBorder)),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: c.title),
                    onPressed: onBack,
                    tooltip: 'Back',
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: MtTextStyles.h3.copyWith(color: c.title)),
                        if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MtTextStyles.bodySm.copyWith(color: c.muted),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
              child: BookingStepper(current: step, onStepTapped: onStepTapped),
            ),
          ],
        ),
      ),
    );
  }
}
