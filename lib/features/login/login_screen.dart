import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/auth_service.dart';
import '../../core/widgets/background/sci_fi_background.dart';
import '../../core/widgets/buttons/glass_button.dart';
import '../../core/widgets/buttons/gradient_button.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/route_config.dart';
import '../../core/state/user_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    debugPrint('[API] trigger button=login');
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      debugPrint('[API] result button=login skipped reason=empty_credentials');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入用户名和密码')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final session = await _authService.login(
        username: username,
        password: password,
      );
      await UserState.instance.saveSession(session);
      if (!mounted) return;
      debugPrint('[API] result button=login route=$homeTabPath');
      context.go(homeTabPath);
    } catch (e) {
      if (!mounted) return;
      final message = _authService.errorMessage(e);
      debugPrint('[API] result button=login failed error=$message');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('登录失败: $message')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
    debugPrint('[API] trigger button=register');
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || email.isEmpty || password.isEmpty) {
      debugPrint('[API] result button=register skipped reason=empty_fields');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入用户名、邮箱和密码')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final session = await _authService.register(
        username: username,
        email: email,
        password: password,
      );
      await UserState.instance.saveSession(session);

      if (mounted) {
        debugPrint('[API] result button=register success');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('注册成功')));
        context.go(homeTabPath);
      }
    } catch (e) {
      if (mounted) {
        final message = _authService.errorMessage(e);
        debugPrint('[API] result button=register failed error=$message');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('注册失败: $message')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<UserState>();

    if (userState.isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(homeTabPath);
      });
    }

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

                  _buildTextField(
                    controller: _emailController,
                    hint: '邮箱（注册时必填）',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
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
    TextInputType? keyboardType,
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
        keyboardType: keyboardType,
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
