import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';

class TaskItem extends StatelessWidget {
  final String title;
  final String creationTime;
  final String status;
  final IconData statusIcon;
  final Color statusColor;
  final String? thumbnailUrl;
  final String? localThumbnailPath;
  final VoidCallback onView;
  final VoidCallback onDelete;

  const TaskItem({
    super.key,
    required this.title,
    required this.creationTime,
    required this.status,
    this.statusIcon = Icons.info_outline,
    this.statusColor = const Color(0xFF00FFC2),
    this.thumbnailUrl,
    this.localThumbnailPath,
    required this.onView,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    ImageProvider? imageProvider;
    if (localThumbnailPath != null && localThumbnailPath!.isNotEmpty) {
      final localFile = File(localThumbnailPath!);
      if (localFile.existsSync()) {
        imageProvider = FileImage(localFile);
      }
    } else if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty) {
      imageProvider = NetworkImage(thumbnailUrl!);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 0.8,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF).withValues(alpha: 0.05),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.1),
                  Colors.transparent,
                ],
              ),
            ),
            child: Row(
              children: [
                // 1. 缩略图区域
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFF00C6FF).withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                    image: imageProvider != null
                        ? DecorationImage(
                            image: imageProvider,
                            fit: BoxFit.cover,
                          )
                        : null,
                    color: imageProvider == null
                        ? Colors.white.withValues(alpha: 0.1)
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00C6FF).withValues(alpha: 0.1),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: imageProvider == null
                      ? const Icon(
                          Icons.image_not_supported_outlined,
                          color: Colors.white24,
                        )
                      : null,
                ),
                const SizedBox(width: 16),

                // 2. 信息展示区域
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        creationTime,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(statusIcon, color: statusColor, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            status,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              shadows: [
                                Shadow(color: statusColor, blurRadius: 12),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 3. 按钮操作区域
                Column(
                  children: [
                    _buildActionButton(
                      label: '查看',
                      onPressed: onView,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00C6FF), Color(0xFF0072FF)],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildActionButton(
                      label: '删除',
                      onPressed: onDelete,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF4B2B), Color(0xFFFF416C)],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required VoidCallback onPressed,
    required Gradient gradient,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 72,
        height: 36,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: (gradient as LinearGradient).colors.first.withValues(
                alpha: 0.3,
              ),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
