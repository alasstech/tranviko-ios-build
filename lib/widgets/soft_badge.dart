import 'package:flutter/material.dart';

/// Widget réutilisable pour les badges souples (soft badges)
class SoftBadge extends StatelessWidget {
  final String label;
  final Color? backgroundColor;
  final Color? textColor;
  final EdgeInsets padding;
  final double borderRadius;

  const SoftBadge({
    super.key,
    required this.label,
    this.backgroundColor,
    this.textColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    this.borderRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    const defaultBgColor = Color(0xFFE3F2FD);
    const defaultTextColor = Color(0xFF0047AB);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? defaultBgColor,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor ?? defaultTextColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
