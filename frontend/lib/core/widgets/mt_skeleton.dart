import 'package:flutter/material.dart';

import '../theme/mt_colors.dart';

class MtSkeleton extends StatefulWidget {
  final double? width;
  final double height;
  final BorderRadiusGeometry borderRadius;
  final Color? color;

  const MtSkeleton._({
    this.width,
    required this.height,
    required this.borderRadius,
    this.color,
  });

  factory MtSkeleton.box({
    double? width,
    required double height,
    double radius = 10,
    Color? color,
  }) {
    return MtSkeleton._(
      width: width,
      height: height,
      borderRadius: BorderRadius.circular(radius),
      color: color,
    );
  }

  factory MtSkeleton.line({
    double? width,
    double height = 12,
    Color? color,
  }) {
    return MtSkeleton._(
      width: width,
      height: height,
      borderRadius: BorderRadius.circular(6),
      color: color,
    );
  }

  factory MtSkeleton.circle({required double size, Color? color}) {
    return MtSkeleton._(
      width: size,
      height: size,
      borderRadius: BorderRadius.circular(size / 2),
      color: color,
    );
  }

  @override
  State<MtSkeleton> createState() => _MtSkeletonState();
}

class _MtSkeletonState extends State<MtSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.color ?? MtColors.bg;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final opacity = 0.55 + (0.45 * t);
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: base.withValues(alpha: opacity),
            borderRadius: widget.borderRadius,
          ),
        );
      },
    );
  }
}
