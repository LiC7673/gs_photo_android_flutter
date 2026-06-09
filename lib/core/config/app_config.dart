class AppConfig {
  // 基础服务器地址

  // 路由配置

  static const String authLoginPath = '/auth/login';
  static const String authRegisterPath = '/auth/register';
  static const String reconstructionCreatePath = '/reconstruction/tasks';
  static const String reconstructionSubmitPath =
      '/reconstruction/start/{task_id}';
  static const String reconstructionStaPath = '/reconstruction/start';
  static const String reconstructionStatusPath = '/reconstruction/status';
  static const String reconstructionDownloadPath = '/reconstruction/download';

  // 图片上传接口路径
  static const String uploadPath = '/common/upload';

  // 分片上传接口路径

  // 模型预览接口路径 (预留)
  static const String previewPath = '/preview';
}
