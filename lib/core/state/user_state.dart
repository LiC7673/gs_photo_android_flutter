import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppUser {
  final int id;
  final String username;
  final String email;
  final String nickname;
  final bool isActive;
  final bool isAdmin;
  final int storageUsed;
  final int storageQuota;
  final int taskCount;
  final int taskQuota;
  final int gpuSecondsUsed;
  final int gpuQuota;
  final String createdAt;

  const AppUser({
    required this.id,
    required this.username,
    required this.email,
    required this.nickname,
    required this.isActive,
    required this.isAdmin,
    required this.storageUsed,
    required this.storageQuota,
    required this.taskCount,
    required this.taskQuota,
    required this.gpuSecondsUsed,
    required this.gpuQuota,
    required this.createdAt,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as int,
      username: json['username'] as String? ?? '',
      email: json['email'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? false,
      isAdmin: json['is_admin'] as bool? ?? false,
      storageUsed: json['storage_used'] as int? ?? 0,
      storageQuota: json['storage_quota'] as int? ?? 0,
      taskCount: json['task_count'] as int? ?? 0,
      taskQuota: json['task_quota'] as int? ?? 0,
      gpuSecondsUsed: json['gpu_seconds_used'] as int? ?? 0,
      gpuQuota: json['gpu_quota'] as int? ?? 0,
      createdAt: json['created_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'nickname': nickname,
      'is_active': isActive,
      'is_admin': isAdmin,
      'storage_used': storageUsed,
      'storage_quota': storageQuota,
      'task_count': taskCount,
      'task_quota': taskQuota,
      'gpu_seconds_used': gpuSecondsUsed,
      'gpu_quota': gpuQuota,
      'created_at': createdAt,
    };
  }

  String get displayName {
    if (nickname.trim().isNotEmpty) return nickname;
    return username;
  }
}

class AuthSession {
  final String accessToken;
  final String tokenType;
  final int expiresIn;
  final AppUser user;

  const AuthSession({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    required this.user,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['access_token'] as String,
      tokenType: json['token_type'] as String? ?? 'bearer',
      expiresIn: json['expires_in'] as int? ?? 0,
      user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}

class UserState with ChangeNotifier {
  static const String _tokenKey = 'auth.access_token';
  static const String _userKey = 'auth.user';

  // 单例模式，方便非 Widget 类访问
  static final UserState instance = UserState._internal();
  UserState._internal();
  factory UserState() => instance;

  AppUser? _user;
  String? _token;
  bool _isInitialized = false;

  AppUser? get user => _user;
  String? get username => _user?.username;
  String? get nickname => _user?.nickname;
  String? get token => _token;
  bool get isInitialized => _isInitialized;
  bool get isLoggedIn => _token != null && _user != null;

  Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    final userJson = prefs.getString(_userKey);
    if (userJson != null) {
      _user = AppUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
    }
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> saveSession(AuthSession session) async {
    _token = session.accessToken;
    _user = session.user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, session.accessToken);
    await prefs.setString(_userKey, jsonEncode(session.user.toJson()));
    notifyListeners();
  }

  Future<void> updateUser(AppUser user) async {
    _user = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
    notifyListeners();
  }

  Future<void> logout() async {
    _user = null;
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    notifyListeners();
  }
}
