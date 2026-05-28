import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/router/route_config.dart';
import '../../core/state/user_state.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, // 保持全局背景可见
      appBar: AppBar(
        title: const Text(
          '个人中心',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // 1. 个人信息卡片 (基于原型图设计)
              _buildUserInfoCard(context),

              const SizedBox(height: 24),

              // 2. 功能列表 (预留位)
              _buildMenuItem(Icons.history, '历史记录'),
              _buildMenuItem(Icons.settings_outlined, '通用设置'),
              _buildMenuItem(Icons.info_outline, '关于我们'),

              const SizedBox(height: 48),

              // 3. 退出登录按钮
              _buildLogoutButton(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserInfoCard(BuildContext context) {
    final user = context.watch<UserState>().user;
    final displayName = user?.displayName ?? '未登录';
    final email = user?.email ?? '';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 0.8,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(20),
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
                // 蓝色头像圆圈
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0072FF).withValues(alpha: 0.8),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0072FF).withValues(alpha: 0.3),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.person,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 24),
                // 信息展示区
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        email,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
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

  Widget _buildMenuItem(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          leading: Icon(icon, color: Colors.white.withValues(alpha: 0.7)),
          title: Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          trailing: Icon(
            Icons.chevron_right,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          onTap: () => debugPrint('点击了：$title'),
        ),
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return OutlinedButton(
      onPressed: () async {
        await UserState.instance.logout();
        if (context.mounted) context.go(loginPath);
      },
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: const Text(
        '退出登录',
        style: TextStyle(color: Colors.redAccent, fontSize: 16),
      ),
    );
  }
}
