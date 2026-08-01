import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A reusable entrance wrapper that fades its [child] in while sliding it up a
/// touch, staggered by [index] so a row/rail of cards cascades into view.
///
/// Zero external dependencies — just a single [AnimationController] driving a
/// [FadeTransition] + [SlideTransition] with a premium `easeOutQuint` curve
/// (fast start, silky slow finish). The per-item delay is `delayPer * index`
/// (capped at [maxStaggerSteps] so cards that scroll in far down the list
/// don't wait an eternity). Drop it around any widget:
///
/// ```dart
/// StaggeredAnimatedCard(index: i, child: MyCard(...))
/// ```
class StaggeredAnimatedCard extends StatefulWidget {
  /// Position of this card within its row/list — drives the entrance delay.
  final int index;

  /// The card to animate in.
  final Widget child;

  /// Delay added per [index] step (Card 0 = 0ms, Card 1 = 100ms, …).
  final Duration delayPer;

  /// Length of the fade+slide itself.
  final Duration duration;

  /// Cap on how many [index] steps contribute to the delay, so deep-list items
  /// still appear promptly when scrolled into view.
  final int maxStaggerSteps;

  const StaggeredAnimatedCard({
    super.key,
    required this.index,
    required this.child,
    this.delayPer = const Duration(milliseconds: 100),
    this.duration = const Duration(milliseconds: 500),
    this.maxStaggerSteps = 4,
  });

  @override
  State<StaggeredAnimatedCard> createState() => _StaggeredAnimatedCardState();
}

class _StaggeredAnimatedCardState extends State<StaggeredAnimatedCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    // easeOutQuint — starts fast, decelerates into a silky-smooth landing.
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuint,
    );
    _fade = curved;
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.12), // ~12% of card height ≈ a small rise
      end: Offset.zero,
    ).animate(curved);

    final steps = math.min(widget.index, widget.maxStaggerSteps);
    final delay = widget.delayPer * steps;
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
