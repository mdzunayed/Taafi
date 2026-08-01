import 'package:flutter/material.dart';

/// A premium, self-contained shimmer engine.
///
/// Wraps any skeleton silhouette ([child]) and slides a soft diagonal
/// highlight across it on a continuous loop — the classic "loading shimmer"
/// used to mask raw network flicker behind asynchronous telemetry and list
/// widgets. No third-party `shimmer` package is required: a single
/// [AnimationController] drives a translating [LinearGradient] painted over the
/// opaque pixels of [child] via a [ShaderMask].
///
/// Wrap a *whole* skeleton tree in ONE [ShimmerLoadingPlaceholder] so the
/// entire group of placeholders share a single ticker (cheap + perfectly in
/// sync) rather than animating each shape independently. Compose the silhouette
/// itself from [ShimmerBox] primitives (or the ready-made [ShimmerKpiRow] /
/// [ShimmerCareCardList] layouts below).
class ShimmerLoadingPlaceholder extends StatefulWidget {
  /// The skeleton silhouette the highlight sweeps across. Only opaque pixels
  /// pick up the shimmer, so gaps between shapes read as empty space.
  final Widget child;

  /// The dim slate the silhouette rests at — defaults to `Colors.grey.shade200`.
  final Color baseColor;

  /// The bright sheen that travels across — defaults to `Colors.grey.shade50`.
  final Color highlightColor;

  /// One full sweep duration.
  final Duration period;

  const ShimmerLoadingPlaceholder({
    super.key,
    required this.child,
    this.baseColor = const Color(0xFFE5E7EB), // Colors.grey.shade200
    this.highlightColor = const Color(0xFFFAFAFA), // Colors.grey.shade50
    this.period = const Duration(milliseconds: 1400),
  });

  @override
  State<ShimmerLoadingPlaceholder> createState() =>
      _ShimmerLoadingPlaceholderState();
}

class _ShimmerLoadingPlaceholderState extends State<ShimmerLoadingPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            // Travel the highlight from well off the left edge to well off the
            // right edge so the sheen never appears to "stick" at the bounds.
            final slide = (_controller.value * 3.0) - 1.5;
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
              stops: const [0.35, 0.5, 0.65],
              transform: _SlidingGradientTransform(slide),
            ).createShader(bounds);
          },
          child: child,
        );
      },
    );
  }
}

/// Translates a gradient horizontally by [slidePercent] of the painted bounds,
/// which is what turns a static gradient into a sweeping highlight.
class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform(this.slidePercent);

  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0.0, 0.0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Silhouette primitives
// ─────────────────────────────────────────────────────────────────────────────

/// A single opaque skeleton shape. Colour is irrelevant — the wrapping
/// [ShimmerLoadingPlaceholder] repaints every opaque pixel with the shimmer
/// gradient — so this just stamps the *geometry* of a placeholder. Defaults to
/// a slate fill so it still reads as a skeleton even without a shimmer parent.
class ShimmerBox extends StatelessWidget {
  final double? width;
  final double height;
  final BorderRadiusGeometry borderRadius;

  const ShimmerBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  /// A short text-line silhouette.
  factory ShimmerBox.line({double? width, double height = 12}) => ShimmerBox(
        width: width,
        height: height,
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      );

  /// A circular silhouette (avatar / icon slot).
  factory ShimmerBox.circle(double size) => ShimmerBox(
        width: size,
        height: size,
        borderRadius: BorderRadius.all(Radius.circular(size / 2)),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE5E7EB),
        borderRadius: borderRadius,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ready-made layouts
// ─────────────────────────────────────────────────────────────────────────────

/// A horizontal row of KPI/metric-card silhouettes that matches the admin
/// dashboard's telemetry cards (fixed height + radius) so the grid never
/// reflows when the real numbers land.
class ShimmerKpiRow extends StatelessWidget {
  final int count;
  final double cardHeight;
  final double spacing;

  const ShimmerKpiRow({
    super.key,
    this.count = 4,
    this.cardHeight = 100,
    this.spacing = 16,
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerLoadingPlaceholder(
      child: Row(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) SizedBox(width: spacing),
            Expanded(
              child: ShimmerBox(
                height: cardHeight,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A scrollable column of clinician care-card silhouettes — avatar, two text
/// lines and an action bar — sized to the real triage / dispatch / job-log
/// cards so the workspace layout stays rigid while the feed fetches.
class ShimmerCareCardList extends StatelessWidget {
  final int count;
  final EdgeInsetsGeometry padding;

  const ShimmerCareCardList({
    super.key,
    this.count = 4,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 24),
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerLoadingPlaceholder(
      child: ListView.separated(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, _) => const _CareCardSkeleton(),
      ),
    );
  }
}

class _CareCardSkeleton extends StatelessWidget {
  const _CareCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // Transparent fill keeps the shimmer on the silhouette shapes only,
        // while a subtle outline preserves the card boundary for stability.
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDEFF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ShimmerBox.circle(48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox.line(width: 150, height: 13),
                    const SizedBox(height: 8),
                    ShimmerBox.line(width: 100, height: 11),
                  ],
                ),
              ),
              ShimmerBox(
                width: 64,
                height: 22,
                borderRadius: BorderRadius.circular(8),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ShimmerBox(height: 48, borderRadius: BorderRadius.circular(12)),
        ],
      ),
    );
  }
}
