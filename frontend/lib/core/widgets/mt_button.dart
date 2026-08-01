import 'package:flutter/material.dart';
import '../theme/mt_colors.dart';
import '../theme/mt_text_styles.dart';

class MtButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool isLoading;
  final IconData? leadingIcon;
  final double? width;
  final Color? backgroundColor;
  final Color? textColor;
  final bool isOutlined;
  final double height;

  const MtButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.leadingIcon,
    this.width,
    this.backgroundColor,
    this.textColor,
    this.isOutlined = false,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ?? MtColors.brand;
    final txtColor = textColor ?? (isOutlined ? MtColors.ink : Colors.white);

    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leadingIcon != null && !isLoading) ...[
          Icon(leadingIcon, size: 20, color: txtColor),
          const SizedBox(width: 8),
        ],
        if (isLoading)
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(txtColor),
              strokeWidth: 2,
            ),
          )
        else
          Text(label, style: MtTextStyles.labelLg.copyWith(color: txtColor)),
      ],
    );

    if (isOutlined) {
      return SizedBox(
        width: width ?? double.infinity,
        height: height,
        child: OutlinedButton(
          onPressed: isLoading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: bgColor, width: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: child,
        ),
      );
    }

    return SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          disabledBackgroundColor: MtColors.line,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: child,
      ),
    );
  }
}

class MtIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;
  final Color? backgroundColor;
  final double size;
  final double iconSize;

  const MtIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color,
    this.backgroundColor,
    this.size = 40,
    this.iconSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: iconSize),
        color: color ?? MtColors.ink,
        style: IconButton.styleFrom(
          backgroundColor: backgroundColor ?? MtColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: MtColors.line),
          ),
        ),
      ),
    );
  }
}
