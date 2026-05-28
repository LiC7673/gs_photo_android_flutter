import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../../core/widgets/recommendation/recommendation_card.dart';

class RecommendationPage extends StatelessWidget {
  const RecommendationPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 模拟数据列表
    final List<Map<String, dynamic>> items = [
      {
        'title': '未来城市景观 3DGS',
        'userId': 'CyberArtist_01',
        'imageUrl':
            'https://images.unsplash.com/photo-1614850523296-d8c1af93d400?q=80&w=2070&auto=format&fit=crop',
        'height': 240.0,
      },
      {
        'title': '复古相机点云重建',
        'userId': 'VintageScanner',
        'imageUrl':
            'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?q=80&w=2072&auto=format&fit=crop',
        'height': 180.0,
      },
      {
        'title': '森林深处的光影',
        'userId': 'NatureCoder',
        'imageUrl':
            'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?q=80&w=2071&auto=format&fit=crop',
        'height': 300.0,
      },
      {
        'title': '室内家居布局渲染',
        'userId': 'InteriorAI',
        'imageUrl':
            'https://images.unsplash.com/photo-1618221195710-dd6b41faaea6?q=80&w=2000&auto=format&fit=crop',
        'height': 200.0,
      },
      {
        'title': '赛博朋克风格人像',
        'userId': 'NeonSoul',
        'imageUrl':
            'https://images.unsplash.com/photo-1550745165-9bc0b252726f?q=80&w=2070&auto=format&fit=crop',
        'height': 260.0,
      },
      {
        'title': '古代遗迹数字化保存',
        'userId': 'HistoryGuard',
        'imageUrl':
            'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?q=80&w=1974&auto=format&fit=crop',
        'height': 220.0,
      },
    ];

    return Scaffold(
      backgroundColor: Colors.transparent, // 保持全局背景可见
      appBar: AppBar(
        title: const Text(
          '发现灵感',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: MasonryGridView.count(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          crossAxisCount: 2, // 两列布局
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return RecommendationCard(
              title: item['title'],
              userId: item['userId'],
              imageUrl: item['imageUrl'],
              imageHeight: item['height'],
            );
          },
        ),
      ),
    );
  }
}
