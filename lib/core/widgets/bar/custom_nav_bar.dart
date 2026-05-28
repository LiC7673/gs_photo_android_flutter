import 'dart:ui';
import 'package:flutter/material.dart';

class CustomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const CustomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 88,
          decoration: BoxDecoration(
            // 降低不透明度，使背景模糊效果可见
            color: const Color(0xFF03081C).withValues(alpha: 0.8),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            child: Row(
              children: [
                _buildNavItem(0, '首页', Icons.home_rounded),
                _buildNavItem(1, "任务", Icons.task),
                _buildNavItem(2, '发现', Icons.explore_outlined),
                _buildNavItem(3, '我的', Icons.person_outline),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    String label,
    IconData defaultIcon, {
    bool hasBadge = false,
  }) {
    final bool isSelected = currentIndex == index;
    final Color activeColor = const Color(0xFF00C6FF); // 亮青色
    final Color inactiveColor = const Color(0xFF5E6A81); // 灰色调

    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: SizedBox.expand(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    defaultIcon,
                    size: 28,
                    color: isSelected ? activeColor : inactiveColor,
                    shadows: isSelected
                        ? [
                            Shadow(
                              color: activeColor.withValues(alpha: 0.8),
                              blurRadius: 16,
                            ),
                          ]
                        : null,
                  ),
                  if (hasBadge)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF03081C),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withValues(alpha: 0.5),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? activeColor : inactiveColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
