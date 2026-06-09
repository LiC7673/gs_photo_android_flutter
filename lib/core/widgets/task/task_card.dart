import 'dart:ui';

import 'package:flutter/material.dart';

import '../../state/language_state.dart';

class TaskCard extends StatelessWidget {
  final String title;
  final String statusText;
  final double progress;
  final String timeRemaining;
  final String imageUrl;
  final Widget? leadingImage;
  final String headerText;
  final String footerText;
  final VoidCallback? onTap;

  const TaskCard({
    super.key,
    required this.title,
    required this.statusText,
    required this.progress,
    required this.timeRemaining,
    required this.imageUrl,
    this.leadingImage,
    this.headerText = '',
    this.footerText = '',
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final safeProgress = progress.clamp(0, 1).toDouble();
    final resolvedHeader = headerText.isEmpty
        ? context.tr('home.task.generic')
        : headerText;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF03081C).withValues(alpha: 0.6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    resolvedHeader,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: leadingImage ?? _buildNetworkImage(),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$statusText ${(safeProgress * 100).toInt()}%',
                              style: const TextStyle(
                                color: Color(0xFF00C6FF),
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 4,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: safeProgress,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(2),
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF00C6FF),
                                        Color(0xFF0072FF),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              footerText.isEmpty
                                  ? context.tr(
                                      'home.footer.updatedAt',
                                      args: {'time': timeRemaining},
                                    )
                                  : footerText,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildDecorativeRadar(),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNetworkImage() {
    return Image.network(
      imageUrl,
      width: 72,
      height: 72,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _buildImagePlaceholder(),
    );
  }

  static Widget buildImagePlaceholder() => _buildImagePlaceholder();

  static Widget _buildImagePlaceholder() {
    return Container(
      width: 72,
      height: 72,
      color: Colors.white.withValues(alpha: 0.08),
      child: const Icon(
        Icons.view_in_ar_outlined,
        color: Colors.white38,
      ),
    );
  }

  Widget _buildDecorativeRadar() {
    const radarSize = 48.0;
    return Container(
      width: radarSize,
      height: radarSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFF00C6FF).withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.radar,
            color: const Color(0xFF00C6FF).withValues(alpha: 0.5),
            size: 24,
          ),
          Transform.rotate(
            angle: 0.5,
            child: Container(
              width: 40,
              height: 1,
              color: const Color(0xFF00C6FF).withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}
