import 'package:flutter/material.dart';
import '../theme/mt_colors.dart';
import '../theme/mt_text_styles.dart';

class InitialsAvatar extends StatelessWidget {
  final String name;
  final double size;
  final Color? backgroundColor;
  final Color? textColor;

  const InitialsAvatar({
    super.key,
    required this.name,
    this.size = 44,
    this.backgroundColor,
    this.textColor,
  });

  String _getInitials() {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? MtColors.brand,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        _getInitials(),
        style: MtTextStyles.labelLg.copyWith(
          color: textColor ?? Colors.white,
          fontSize: size * 0.35,
        ),
      ),
    );
  }
}
