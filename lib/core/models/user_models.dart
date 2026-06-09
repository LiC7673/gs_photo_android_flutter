class TokenResponse {
  final String accessToken;
  final String tokenType;

  TokenResponse({required this.accessToken, required this.tokenType});

  factory TokenResponse.fromJson(Map<String, dynamic> json) => TokenResponse(
    accessToken: json['access_token'],
    tokenType: json['token_type'],
  );
}

class UserResponse {
  final int id;
  final String username;
  final String? email;
  final String? fullName;
  final String? nickname;
  final String? avatarFileId;
  final String? avatarThumbnailFileId;
  final bool isActive;
  final bool isSuperuser;

  UserResponse({
    required this.id,
    required this.username,
    this.email,
    this.fullName,
    this.nickname,
    this.avatarFileId,
    this.avatarThumbnailFileId,
    required this.isActive,
    required this.isSuperuser,
  });

  factory UserResponse.fromJson(Map<String, dynamic> json) => UserResponse(
    id: json['id'],
    username: json['username'],
    email: json['email'],
    fullName: json['full_name'],
    nickname: json['nickname'],
    avatarFileId: json['avatar_file_id']?.toString(),
    avatarThumbnailFileId: json['avatar_thumbnail_file_id']?.toString(),
    isActive: json['is_active'] ?? true,
    isSuperuser: json['is_superuser'] ?? false,
  );
}

class UserUpdate {
  final String? email;
  final String? fullName;
  final String? password;

  UserUpdate({this.email, this.fullName, this.password});

  Map<String, dynamic> toJson() => {
    if (email != null) 'email': email,
    if (fullName != null) 'full_name': fullName,
    if (password != null) 'password': password,
  };
}
