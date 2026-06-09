import 'package:dio/dio.dart';

import '../config/api_config.dart';
import '../models/user_models.dart';
import '../state/user_state.dart';
import 'dio_adapter.dart';

class AuthService {
  final DioAdapter _adapter = DioAdapter();

  Future<AuthSession> register(
    String username,
    String password, {
    String? email,
    String? fullName,
  }) async {
    final response = await _adapter.post(
      ApiPaths.authRegisterPath,
      data: {
        'username': username,
        'password': password,
        'email': email,
        'full_name': fullName,
      }..removeWhere((key, value) => value == null),
    );
    return _buildSession(TokenResponse.fromJson(response.data));
  }

  Future<AuthSession> login(String username, String password) async {
    final response = await _adapter.post(
      ApiPaths.authLoginPath,
      data: {
        'username': username,
        'password': password,
      },
    );
    return _buildSession(TokenResponse.fromJson(response.data));
  }

  Future<UserResponse> getMe({String? accessToken}) async {
    final response = await _adapter.get(
      ApiPaths.authMePath,
      options: accessToken == null
          ? null
          : Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    return UserResponse.fromJson(response.data);
  }

  Future<AppUser> fetchCurrentUser() async => _toAppUser(await getMe());

  Future<AvatarResponse> updateAvatar(String? avatarFileId) async {
    final response = await _adapter.put(
      'users/update_avatar',
      data: {'avatar_file_id': avatarFileId},
    );
    return AvatarResponse.fromJson(_readObject(response.data));
  }

  String errorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final detail = data['detail'] ?? data['message'] ?? data['error'];
        if (detail != null) return detail.toString();
      }
      return error.message ?? error.toString();
    }
    return error.toString();
  }

  Future<AuthSession> _buildSession(TokenResponse token) async {
    final user = await getMe(accessToken: token.accessToken);
    return AuthSession(
      accessToken: token.accessToken,
      tokenType: token.tokenType,
      expiresIn: 0,
      user: _toAppUser(user),
    );
  }

  AppUser _toAppUser(UserResponse user) {
    return AppUser(
      id: user.id,
      username: user.username,
      email: user.email ?? '',
      nickname: user.nickname ?? user.fullName ?? user.username,
      isActive: user.isActive,
      isAdmin: user.isSuperuser,
      storageUsed: 0,
      storageQuota: 0,
      taskCount: 0,
      taskQuota: 0,
      gpuSecondsUsed: 0,
      gpuQuota: 0,
      createdAt: '',
      avatarFileId: user.avatarFileId,
      avatarThumbnailFileId: user.avatarThumbnailFileId,
    );
  }

  Map<String, dynamic> _readObject(Object? data) {
    if (data is! Map) return const <String, dynamic>{};
    final map = Map<String, dynamic>.from(data);
    for (final key in const ['data', 'avatar', 'result']) {
      final nested = map[key];
      if (nested is Map) return Map<String, dynamic>.from(nested);
    }
    return map;
  }
}

class AvatarResponse {
  final String? avatarFileId;
  final String? avatarThumbnailFileId;
  final String createdAt;

  const AvatarResponse({
    required this.avatarFileId,
    required this.avatarThumbnailFileId,
    required this.createdAt,
  });

  factory AvatarResponse.fromJson(Map<String, dynamic> json) {
    return AvatarResponse(
      avatarFileId: json['avatar_file_id']?.toString(),
      avatarThumbnailFileId: json['avatar_thumbnail_file_id']?.toString(),
      createdAt: json['created_at']?.toString() ?? '',
    );
  }
}
