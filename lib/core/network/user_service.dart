import 'dio_adapter.dart';
import '../config/api_config.dart';
import '../models/user_models.dart';

class UserService {
  final DioAdapter _adapter = DioAdapter();

  /// 获取当前用户信息
  Future<UserResponse> getProfile() async {
    final response = await _adapter.get(ApiPaths.userMePath);
    return UserResponse.fromJson(response.data);
  }

  /// 更新当前用户信息
  Future<UserResponse> updateProfile(UserUpdate update) async {
    final response = await _adapter.put(
      ApiPaths.userMePath,
      data: update.toJson(),
    );
    return UserResponse.fromJson(response.data);
  }

  /// 获取用户使用统计
  Future<String> getUsage() async {
    final response = await _adapter.get(ApiPaths.userUsagePath);
    return response.data.toString();
  }

  /// 更新用户配额 (管理员)
  Future<void> updateQuota(int userId, Map<String, dynamic> quota) async {
    final path = ApiPaths.userQuotaPath.replaceAll('{user_id}', userId.toString());
    await _adapter.put(path, data: quota);
  }
}
