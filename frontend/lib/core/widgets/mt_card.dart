import 'package:flutter/material.dart';
import '../theme/mt_colors.dart';

class MtCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsets padding;
  final Color backgroundColor;
  final Color borderColor;
  final double elevation;
  final GestureTapCallback? onTap;

  const MtCard({
    super.key,
    required this.child,
    this.borderRadius = 12,
    this.padding = const EdgeInsets.all(16),
    this.backgroundColor = MtColors.surface,
    this.borderColor = MtColors.line,
    this.elevation = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: borderColor),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
