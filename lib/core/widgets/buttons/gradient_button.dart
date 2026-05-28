import 'package:flutter/material.dart';

class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final double? height;
  final double borderRadius;

  const GradientButton({
    super.key,
    required this.label,
    this.onPressed,
    this.height,
    this.borderRadius = 32, // Stadium shape (half of height for full round)
  });

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = onPressed != null;
    final buttonHeight = height ?? 56.0;

    return Container(
      width: double.infinity,
      height: buttonHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: isEnabled
            ? const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xFF00C6FF), // 亮青色
                  Color(0xFF0072FF), // 蓝色
                  Color(0xFFB100FF), // 紫色
                ],
              )
            : LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.grey.withValues(alpha: 0.3),
                  Colors.grey.withValues(alpha: 0.1),
                ],
              ),
        boxShadow: isEnabled
            ? [
                BoxShadow(
                  color: Colors.purple.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: isEnabled ? Colors.white : Colors.white24,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Icon(
                    Icons.chevron_right,
                    color: isEnabled ? Colors.white : Colors.white10,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
