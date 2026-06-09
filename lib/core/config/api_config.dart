// api_config.dart
class ApiPaths {
  // A: 公共的 Server Head (例如你的 GS Server 主机地址)
  static const String baseUrl = 'http://211.87.232.134';
  static const int port =8888;
  // B, C: 具体的业务模块 (例如 3D相册模块)
  static const String albumList = '/album/list';
  static const String moduleCBase = '/core_features';

  // D, E: 具体的任务项 (例如拉取特定的 3DGS 渲染配置或切片数据)
  static const String renderTaskD = '/album/render/task_d';
  static const String renderTaskE = '/album/render/task_e';

  static const String publicHead = '/api/v1/';
  // 认证接口
  static const String authLoginPath = 'auth/login';
  static const String authRegisterPath = 'auth/register';
  static const String authMePath = 'auth/me';
  
  // 用户管理接口
  static const String userMePath = 'users/me';
  static const String userUsagePath = 'users/me/usage';
  static const String userQuotaPath = 'users/{user_id}/quota';

  //上传接口
  static const String uploadInitPath = 'upload/init';
  static const String uploadChunkPath = 'upload/{upload_id}/chunk';
  static const String uploadProgressPath = 'upload/{upload_id}/progress';
  static const String uploadMergePath = 'upload/{upload_id}/merge';
  static const String uploadCancelPath = 'upload/{upload_id}/cancel';

  // 文件管理接口
  static const String fileListPath = 'files';
  static const String fileDetailPath = 'files/{file_id}';
  static const String fileDeletePath = 'files/{file_id}';
  static const String fileUrlPath = 'files/{file_id}/url';
  static const String fileDownloadInitPath = 'files/{file_id}/download/init';
  static const String fileDownloadChunkPath = 'files/{file_id}/download/chunk';
  static const String fileDownloadCompletePath =
      'files/downloads/{download_id}/complete';
  static const String fileArchivePath = 'files/{file_id}/archive';

  // 重建接口
  static const String reconstructionAlgorithmsPath = 'reconstruction/algorithms';
  static const String reconstructionMeshAlgorithmsPath =
      'reconstruction/mesh/algorithms';
  static const String reconstructionCreateTaskPath = 'reconstruction/tasks';
  static const String reconstructionDeleteTaskPath =
      'reconstruction/tasks/{task_id}';
  static const String reconstructionVisibilityPath =
      'reconstruction/tasks/{task_id}/visibility';
  static const String reconstructionStartUploadedPath =
      'reconstruction/start/{task_id}';
  static const String reconstructionStartPath = 'reconstruction/start';
  static const String reconstructionMeshStartPath =
      'reconstruction/mesh/start/{task_id}';
  static const String reconstructionStatusPath = 'reconstruction/status/{task_id}';
  static const String reconstructionLogsPath = 'reconstruction/logs/{task_id}';
  static const String reconstructionDownloadPath = 'reconstruction/download/{task_id}';
  static const String reconstructionCancelPath = 'reconstruction/cancel/{task_id}';
  static const String reconstructionDiscoverPath = 'reconstruction/discover';
  static const String reconstructionDiagnosticsPath =
      'reconstruction/diagnostics/{task_id}';

  // 任务接口
  static const String taskListPath = reconstructionCreateTaskPath;
  // 超时时间配置 (单位：毫秒)
  static const int connectTimeout = 10000;
  static const int receiveTimeout = 300000;
}
