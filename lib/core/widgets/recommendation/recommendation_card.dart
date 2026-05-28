import 'dart:ui';
import 'package:flutter/material.dart';

class RecommendationCard extends StatelessWidget {
  final String title;
  final String userId;
  final String imageUrl;
  final double imageHeight;

  const RecommendationCard({
    super.key,
    required this.title,
    required this.userId,
    required this.imageUrl,
    this.imageHeight = 200.0,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      margin: EdgeInsets.all(screenWidth * 0.02),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 0.8,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            color: const Color(0xFFFFFFFF).withValues(alpha: 0.05),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 图片区域
                Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: imageHeight,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: imageHeight,
                      color: Colors.grey[900],
                      child: const Icon(Icons.broken_image, color: Colors.white24),
                    );
                  },
                ),
                Padding(
                  padding: EdgeInsets.all(screenWidth * 0.03),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: screenWidth * 0.038,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: screenWidth * 0.015),
                      Row(
                        children: [
                          Icon(
                            Icons.account_circle_outlined,
                            size: screenWidth * 0.035,
                            color: const Color(0xFF00C6FF),
                          ),
                          SizedBox(width: screenWidth * 0.01),
                          Expanded(
                            child: Text(
                              userId,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
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
