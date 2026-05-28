import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
import '../state/user_state.dart';
import 'api_client.dart';

class AuthService {
  final ApiClient _client = ApiClient();

  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    debugPrint('[API] trigger auth.login username=$username');
    final response = await _client.post(
      ApiPaths.authLoginPath,
      data: {'username': username, 'password': password},
    );
    final session = AuthSession.fromJson(response.data);
    debugPrint('[API] result auth.login user=${session.user.username}');
    return session;
  }

  Future<AuthSession> register({
    required String username,
    required String email,
    required String password,
  }) async {
    debugPrint('[API] trigger auth.register username=$username email=$email');
    final response = await _client.post(
      ApiPaths.authRegisterPath,
      data: {'username': username, 'email': email, 'password': password},
    );
    final session = AuthSession.fromJson(response.data);
    debugPrint('[API] result auth.register user=${session.user.username}');
    return session;
  }

  Future<AppUser> fetchCurrentUser() async {
    debugPrint('[API] trigger auth.me');
    final response = await _client.get(ApiPaths.authMePath);
    final user = AppUser.fromJson(response.data);
    debugPrint('[API] result auth.me user=${user.username}');
    return user;
  }

  String errorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['detail'] != null) {
        return data['detail'].toString();
      }
      return error.message ?? '网络请求失败';
    }
    return error.toString();
  }
}
