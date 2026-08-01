import 'package:flutter/material.dart';

/// A status dot that breathes a halo while the booking is live.
///
/// The halo is a scaling, fading ring behind a solid core — cheap to run
/// (one controller, no layout work) and it reads as "this is happening now"
/// without any text. Set [animate] false for terminal states so a finished
/// booking doesn't keep drawing attention.
class PulsingStatusDot extends StatefulWidget {
  final Color color;
  final bool animate;

  /// Faster, wider pulse for the steps where a provider is on the move.
  final bool intense;
  final double size;

  const PulsingStatusDot({
    super.key,
    required this.color,
    this.animate = true,
    this.intense = false,
    this.size = 9,
  });

  @override
  State<PulsingStatusDot> createState() => _PulsingStatusDotState();
}

class _PulsingStatusDotState extends State<PulsingStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Built eagerly, not via a `late` initializer: for a non-animating dot
    // nothing would touch the field until dispose(), which would construct
    // the ticker (an inherited-widget lookup) on an already-deactivated
    // element and throw.
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.intense ? 1100 : 1800),
    );
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant PulsingStatusDot old) {
    super.didUpdateWidget(old);
    // The milestone can advance under us (socket push) — start/stop and
    // re-time the pulse to match the new state rather than rebuilding.
    if (widget.intense != old.intense) {
      _controller.duration =
          Duration(milliseconds: widget.intense ? 1100 : 1800);
      if (_controller.isAnimating) _controller.repeat();
    }
    if (widget.animate != old.animate) {
      if (widget.animate) {
        _controller.repeat();
      } else {
        _controller.stop();
        _controller.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final core = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );

    if (!widget.animate) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: core,
      );
    }

    final haloMax = widget.size * (widget.intense ? 2.6 : 2.1);
    return SizedBox(
      width: haloMax,
      height: haloMax,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                // Fades out as it expands, so each pulse reads as one ping.
                opacity: (1 - t) * 0.55,
                child: Container(
                  width: widget.size + (haloMax - widget.size) * t,
                  height: widget.size + (haloMax - widget.size) * t,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              ?child,
            ],
          );
        },
        child: core,
      ),
    );
  }
}
