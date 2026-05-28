import 'package:flutter/material.dart';

class SciFiBackground extends StatelessWidget {
  final Widget child;

  const SciFiBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 1. 基础深色背景层
        Container(
          width: double.infinity,
          height: double.infinity,
          color: const Color(0xFF020412), // 极深的海军蓝
        ),

        // 2. 左上角青色微光 (提供科幻感)
        Positioned(
          top: -120,
          left: -120,
          child: Container(
            width: 480,
            height: 480,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF00C6FF).withValues(alpha: 0.12),
                  const Color(0xFF00C6FF).withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),

        // 3. 右下角紫色微光 (增加深度)
        Positioned(
          bottom: -168,
          right: -120,
          child: Container(
            width: 600,
            height: 600,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFFB100FF).withValues(alpha: 0.08),
                  const Color(0xFFB100FF).withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),

        // 4. 内容层
        child,
      ],
    );
  }
}
