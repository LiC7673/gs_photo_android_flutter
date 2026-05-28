import 'dart:ui';
import 'package:flutter/material.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.transparent, // 保持全局背景可见
      appBar: AppBar(
        title: Text(
          '个人中心',
          style: TextStyle(
            color: Colors.white, 
            fontWeight: FontWeight.bold,
            fontSize: screenWidth * 0.05,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(screenWidth * 0.05),
          child: Column(
          children: [
            // 1. 个人信息卡片 (基于原型图设计)
            _buildUserInfoCard(context),
            
            SizedBox(height: screenHeight * 0.03),
            
            // 2. 功能列表 (预留位)
            _buildMenuItem(context, Icons.history, '历史记录'),
            _buildMenuItem(context, Icons.settings_outlined, '通用设置'),
            _buildMenuItem(context, Icons.info_outline, '关于我们'),
            
            SizedBox(height: screenHeight * 0.06),
            
            // 3. 退出登录按钮
            _buildLogoutButton(context),
          ],
        ),
      ),
    ));
  }

  Widget _buildUserInfoCard(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

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
            padding: EdgeInsets.all(screenWidth * 0.05),
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
                  width: screenWidth * 0.18,
                  height: screenWidth * 0.18,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0072FF).withValues(alpha: 0.8),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0072FF).withValues(alpha: 0.3),
                        blurRadius: 15,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(Icons.person, size: screenWidth * 0.1, color: Colors.white),
                ),
                SizedBox(width: screenWidth * 0.06),
                // 信息展示区
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '个人 ID: GS_User888',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: screenWidth * 0.045,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.015),
                      GestureDetector(
                        onTap: () => debugPrint('点击：修改信息'),
                        child: Text(
                          '修改信息',
                          style: TextStyle(
                            color: const Color(0xFF00C6FF).withValues(alpha: 0.9),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.underline,
                          ),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          leading: Icon(icon, color: Colors.white.withValues(alpha: 0.7)),
          title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
          trailing: Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.3)),
          onTap: () => debugPrint('点击了：$title'),
        ),
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return OutlinedButton(
      onPressed: () => Navigator.of(context).pop(), // 简单返回登录页
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        '退出登录', 
        style: TextStyle(color: Colors.redAccent, fontSize: screenWidth * 0.04),
      ),
    );
  }
}
