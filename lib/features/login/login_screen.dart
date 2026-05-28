import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/background/sci_fi_background.dart';
import '../../core/widgets/buttons/glass_button.dart';
import '../../core/widgets/buttons/gradient_button.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/route_config.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final ApiClient _apiClient = ApiClient();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入用户名和密码')));
      return;
    }
    setState(() => _isLoading = true);
    context.go(homeTabPath);
  }

  //   try {
  //     // TODO: 实现真实的登录鉴权逻辑
  //     debugPrint('登录尝试: $username');
  //
  //     // 模拟请求延迟
  //     await Future.delayed(const Duration(milliseconds: 500));
  //
  //     if (mounted) {
  //       // 直接跳转到主程序的导航包装器
  //       Navigator.of(context).pushReplacement(
  //         MaterialPageRoute(builder: (context) => const MainNavigationWrapper()),
  //       );
  //     }
  //   } catch (e) {
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(content: Text('登录失败: $e')),
  //       );
  //     }
  //   } finally {
  //     if (mounted) setState(() => _isLoading = false);
  //   }
  // }
  //
  Future<void> _handleRegister() async {
    setState(() => _isLoading = true);
    try {
      // 注册时也发送 "login in" 作为测试
      final response = await _apiClient.post(
        '/register',
        data: {"message": "login in"},
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('注册成功: ${response.data}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('请求失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SciFiBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '欢迎登录',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 48),

                  // 用户名输入框
                  _buildTextField(
                    controller: _usernameController,
                    hint: '用户名',
                    icon: Icons.person_outline,
                  ),
                  const SizedBox(height: 20),

                  // 密码输入框
                  _buildTextField(
                    controller: _passwordController,
                    hint: '密码',
                    icon: Icons.lock_outline,
                    isPassword: true,
                  ),
                  const SizedBox(height: 32),

                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  else ...[
                    GradientButton(
                      label: '登 录',
                      onPressed: _handleLogin,
                      height: 56,
                    ),
                    const SizedBox(height: 20),
                    GlassButton(
                      label: '注 册',
                      onPressed: _handleRegister,
                      height: 56,
                    ),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
          prefixIcon: Icon(icon, color: Colors.white),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}
