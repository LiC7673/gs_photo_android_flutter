import 'dart:ui';
import 'package:flutter/material.dart';

class GlassButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final double width;
  final double? height;
  final double borderRadius;
  final double blur;
  final double opacity;

  const GlassButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.width = double.infinity,
    this.height,
    this.borderRadius = 16.0,
    this.blur = 10.0,
    this.opacity = 0.2,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final buttonHeight = height ?? screenHeight * 0.065;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Stack(
        children: [
          // 1. 毛玻璃滤镜层
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Container(
              width: width,
              height: buttonHeight,
              decoration: BoxDecoration(
                // 2. 半透明背景色 (带有轻微的白色光泽)
                color: Colors.white.withValues(alpha: opacity),
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 1.5,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.2),
                    Colors.white.withValues(alpha: 0.05),
                  ],
                ),
              ),
            ),
          ),
          
          // 3. 交互按钮层
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              child: Container(
                width: width,
                height: buttonHeight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: buttonHeight * 0.6, color: Colors.white),
                      SizedBox(width: buttonHeight * 0.3),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: buttonHeight * 0.45,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: const [
                          Shadow(
                            color: Colors.black26,
                            offset: Offset(0, 2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
