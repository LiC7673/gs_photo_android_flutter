import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/network/auth_service.dart';
import '../../core/router/route_config.dart';
import '../../core/services/session_prefetch_service.dart';
import '../../core/state/language_state.dart';
import '../../core/state/task_state.dart';
import '../../core/state/user_state.dart';
import '../../core/widgets/background/sci_fi_background.dart';
import '../../core/widgets/buttons/gradient_button.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (username.isEmpty || email.isEmpty || password.isEmpty) {
      _showMessage(context.tr('auth.register.empty'));
      return;
    }
    if (password.length < 6) {
      _showMessage(context.tr('auth.register.shortPassword'));
      return;
    }
    if (password != confirmPassword) {
      _showMessage(context.tr('auth.register.passwordMismatch'));
      return;
    }

    setState(() => _isLoading = true);
    try {
      debugPrint('[API] trigger button=register');
      final session = await _authService.register(
        username,
        password,
        email: email,
      );
      await context.read<TaskState>().clearTasks();
      await UserState.instance.saveSession(session);
      unawaited(SessionPrefetchService.instance.start());
      if (!mounted) return;
      debugPrint('[API] result button=register route=$homeTabPath');
      context.go(homeTabPath);
    } catch (e) {
      if (!mounted) return;
      final message = _authService.errorMessage(e);
      debugPrint('[API] result button=register failed error=$message');
      _showMessage(
        context.tr('auth.register.failed', args: {'message': message}),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _backToLogin() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(loginPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageState>();
    return Scaffold(
      body: SciFiBackground(
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 8,
                left: 12,
                child: IconButton(
                  onPressed: _isLoading ? null : _backToLogin,
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 72,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          context.tr('auth.register.title'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.tr('auth.register.subtitle'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.62),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 34),
                        _RegisterTextField(
                          controller: _usernameController,
                          hint: context.tr('auth.username'),
                          icon: Icons.person_outline_rounded,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 14),
                        _RegisterTextField(
                          controller: _emailController,
                          hint: context.tr('auth.email'),
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 14),
                        _RegisterTextField(
                          controller: _passwordController,
                          hint: context.tr('auth.password'),
                          icon: Icons.lock_outline_rounded,
                          obscureText: true,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 14),
                        _RegisterTextField(
                          controller: _confirmPasswordController,
                          hint: context.tr('auth.confirmPassword'),
                          icon: Icons.verified_user_outlined,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) {
                            if (!_isLoading) unawaited(_handleRegister());
                          },
                        ),
                        const SizedBox(height: 28),
                        if (_isLoading)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: CircularProgressIndicator(
                                color: Color(0xFF00C6FF),
                              ),
                            ),
                          )
                        else
                          GradientButton(
                            label: context.tr('auth.register.button'),
                            onPressed: _handleRegister,
                            height: 56,
                          ),
                        const SizedBox(height: 20),
                        TextButton(
                          onPressed: _isLoading ? null : _backToLogin,
                          child: Text(context.tr('auth.register.back')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegisterTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  const _RegisterTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.48)),
          prefixIcon: Icon(icon, color: Colors.white70),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}
