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
    final screenHeight = MediaQuery.of(context).size.height;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: screenHeight * 0.11, // 从 0.1 增加到 0.11，提供更多缓冲
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
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(context, 0, '首页', Icons.home_rounded),
                _buildNavItem(context, 1, "任务", Icons.task),
                _buildNavItem(context, 2, '发现', Icons.explore_outlined),
                _buildNavItem(context, 3, '我的', Icons.person_outline),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, int index, String label, IconData defaultIcon, {bool hasBadge = false}) {
    final bool isSelected = currentIndex == index;
    final screenWidth = MediaQuery.of(context).size.width;
    final Color activeColor = const Color(0xFF00C6FF); // 亮青色
    final Color inactiveColor = const Color(0xFF5E6A81); // 灰色调

    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: screenWidth * 0.02),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                defaultIcon,
                size: screenWidth * 0.07,
                color: isSelected ? activeColor : inactiveColor,
                shadows: isSelected ? [
                  Shadow(
                    color: activeColor.withValues(alpha: 0.8),
                    blurRadius: 15,
                  ),
                ] : null,
              ),
              if (hasBadge)
                Positioned(
                  right: -screenWidth * 0.005,
                  top: -screenWidth * 0.005,
                  child: Container(
                    width: screenWidth * 0.025,
                    height: screenWidth * 0.025,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF03081C), width: 1.5),
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
          SizedBox(height: screenWidth * 0.01),
          Text(
            label,
            style: TextStyle(
              fontSize: screenWidth * 0.03,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? activeColor : inactiveColor,
            ),
          ),
        ],
      ),
    );
  }
}
