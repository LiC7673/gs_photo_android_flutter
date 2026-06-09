import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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
  final String? avatarFileId;
  final String? avatarThumbnailFileId;

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
    this.avatarFileId,
    this.avatarThumbnailFileId,
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
      avatarFileId: json['avatar_file_id']?.toString(),
      avatarThumbnailFileId: json['avatar_thumbnail_file_id']?.toString(),
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
      'avatar_file_id': avatarFileId,
      'avatar_thumbnail_file_id': avatarThumbnailFileId,
    };
  }

  AppUser copyWith({
    String? avatarFileId,
    String? avatarThumbnailFileId,
  }) {
    return AppUser(
      id: id,
      username: username,
      email: email,
      nickname: nickname,
      isActive: isActive,
      isAdmin: isAdmin,
      storageUsed: storageUsed,
      storageQuota: storageQuota,
      taskCount: taskCount,
      taskQuota: taskQuota,
      gpuSecondsUsed: gpuSecondsUsed,
      gpuQuota: gpuQuota,
      createdAt: createdAt,
      avatarFileId: avatarFileId ?? this.avatarFileId,
      avatarThumbnailFileId:
          avatarThumbnailFileId ?? this.avatarThumbnailFileId,
    );
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
  static const String _avatarOriginalKey = 'profile.avatar_original_path';
  static const String _avatarThumbKey = 'profile.avatar_thumb_path';

  // 单例模式，方便非 Widget 类访问
  static final UserState instance = UserState._internal();
  UserState._internal();
  factory UserState() => instance;

  AppUser? _user;
  String? _token;
  String? _avatarOriginalPath;
  String? _avatarThumbPath;
  bool _isInitialized = false;

  AppUser? get user => _user;
  String? get username => _user?.username;
  String? get nickname => _user?.nickname;
  String? get token => _token;
  String? get avatarOriginalPath => _avatarOriginalPath;
  String? get avatarThumbPath => _avatarThumbPath;
  bool get isInitialized => _isInitialized;
  bool get isLoggedIn => _token != null && _user != null;

  Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    final userJson = prefs.getString(_userKey);
    if (userJson != null) {
      _user = AppUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
    }
    _avatarOriginalPath = prefs.getString(_avatarOriginalKey);
    _avatarThumbPath = prefs.getString(_avatarThumbKey);
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

  Future<void> updateAvatarFromFile(String sourcePath) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw StateError('Avatar source file does not exist: $sourcePath');
    }

    final directory = await getApplicationDocumentsDirectory();
    final avatarDirectory = Directory(p.join(directory.path, 'avatars'));
    if (!await avatarDirectory.exists()) {
      await avatarDirectory.create(recursive: true);
    }

    final userId = _user?.id.toString() ?? 'guest';
    final extension = p.extension(sourcePath).toLowerCase();
    final normalizedExtension = extension.isEmpty ? '.jpg' : extension;
    final originalPath = p.join(
      avatarDirectory.path,
      '${userId}_avatar_original$normalizedExtension',
    );
    final thumbPath = p.join(avatarDirectory.path, '${userId}_avatar_thumb.jpg');

    await sourceFile.copy(originalPath);
    await _writeAvatarThumbnail(originalPath, thumbPath);
    _evictAvatarImageCache(originalPath);
    _evictAvatarImageCache(thumbPath);

    _avatarOriginalPath = originalPath;
    _avatarThumbPath = thumbPath;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_avatarOriginalKey, originalPath);
    await prefs.setString(_avatarThumbKey, thumbPath);
    notifyListeners();
  }

  Future<void> updateAvatarFromServer({
    required String? avatarFileId,
    required String? avatarThumbnailFileId,
    String? originalPath,
    String? thumbPath,
  }) async {
    final currentUser = _user;
    if (currentUser != null) {
      _user = currentUser.copyWith(
        avatarFileId: avatarFileId,
        avatarThumbnailFileId: avatarThumbnailFileId,
      );
    }

    if (originalPath != null) _avatarOriginalPath = originalPath;
    if (thumbPath != null) _avatarThumbPath = thumbPath;
    if (originalPath != null) _evictAvatarImageCache(originalPath);
    if (thumbPath != null) _evictAvatarImageCache(thumbPath);

    final prefs = await SharedPreferences.getInstance();
    if (_user != null) {
      await prefs.setString(_userKey, jsonEncode(_user!.toJson()));
    }
    if (_avatarOriginalPath != null) {
      await prefs.setString(_avatarOriginalKey, _avatarOriginalPath!);
    }
    if (_avatarThumbPath != null) {
      await prefs.setString(_avatarThumbKey, _avatarThumbPath!);
    }
    notifyListeners();
  }

  Future<void> updateAvatarLocalPaths({
    String? originalPath,
    String? thumbPath,
  }) async {
    if (originalPath != null) _avatarOriginalPath = originalPath;
    if (thumbPath != null) _avatarThumbPath = thumbPath;
    if (originalPath != null) _evictAvatarImageCache(originalPath);
    if (thumbPath != null) _evictAvatarImageCache(thumbPath);
    final prefs = await SharedPreferences.getInstance();
    if (originalPath != null) {
      await prefs.setString(_avatarOriginalKey, originalPath);
    }
    if (thumbPath != null) {
      await prefs.setString(_avatarThumbKey, thumbPath);
    }
    notifyListeners();
  }

  Future<void> clearAvatar() async {
    final original = _avatarOriginalPath;
    final thumb = _avatarThumbPath;
    _avatarOriginalPath = null;
    _avatarThumbPath = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_avatarOriginalKey);
    await prefs.remove(_avatarThumbKey);

    for (final path in [original, thumb]) {
      if (path == null || path.isEmpty) continue;
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
    notifyListeners();
  }

  Future<void> _writeAvatarThumbnail(
    String originalPath,
    String thumbPath,
  ) async {
    final bytes = await File(originalPath).readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) {
      await File(originalPath).copy(thumbPath);
      return;
    }

    final thumbnail = img.copyResizeCropSquare(image, size: 256);
    await File(thumbPath).writeAsBytes(img.encodeJpg(thumbnail, quality: 88));
  }

  void _evictAvatarImageCache(String path) {
    PaintingBinding.instance.imageCache.evict(FileImage(File(path)));
  }

  Future<void> logout() async {
    _user = null;
    _token = null;
    _avatarOriginalPath = null;
    _avatarThumbPath = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_avatarOriginalKey);
    await prefs.remove(_avatarThumbKey);
    notifyListeners();
  }
}
