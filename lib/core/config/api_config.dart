// api_config.dart
class ApiPaths {
  // A: 公共的 Server Head (例如你的 GS Server 主机地址)
  static const String baseUrl = 'http://211.87.232.134';
  static const int port = 8000;
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
  static const String userProfilePath = 'users/me';
  //上传接口
  static const String uploadInitPath = 'upload/init';
  static const String uploadChunkPath = 'upload/{upload_id}/chunk';
  static const String uploadProgressPath = 'upload/{upload_id}/progress';
  static const String uploadMergePath = 'upload/{upload_id}/merge';
  static const String uploadCancelPath = 'upload/{file_id}/cancel';
  // 文件下载接口
  static const String fileDownloadInitPath = 'files/{file_id}/download/init';
  static const String fileDownloadChunkPath = 'files/{file_id}/download/chunk';
  static const String fileDownloadProgressPath =
      'files/downloads/{download_id}/progress';
  // 重建接口
  static const String reconstructionCreateTaskPath = 'reconstruction/tasks';
  static const String reconstructionStartUploadedPath =
      'reconstruction/start/{task_id}';
  static const String reconstructionStatusPath =
      'reconstruction/status/{task_id}';
  static const String reconstructionCancelPath =
      'reconstruction/cancel/{task_id}';
  static const String reconstructionLogsPath = 'reconstruction/logs/{task_id}';
  static const String reconstructionDiagnosticsPath =
      'reconstruction/diagnostics/{task_id}';
  static const String reconstructionDownloadPath =
      'reconstruction/download/{task_id}';
  static const String reconstructionAlgorithmsPath =
      'reconstruction/algorithms';
  // 超时时间配置 (单位：毫秒)
  static const int connectTimeout = 10000;
  static const int receiveTimeout = 300000;
}
