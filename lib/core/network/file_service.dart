import 'dio_adapter.dart';
import '../config/api_config.dart';
import '../models/file_models.dart';

class FileService {
  final DioAdapter _adapter = DioAdapter();

  /// 获取文件列表
  Future<FileListResponse> listFiles({
    String? category,
    String? fileHash,
    int? fileSize,
    int skip = 0,
    int limit = 100,
  }) async {
    final response = await _adapter.get(
      ApiPaths.fileListPath,
      queryParameters: {
        if (category != null) 'category': category,
        if (fileHash != null) 'file_hash': fileHash,
        if (fileSize != null) 'file_size': fileSize,
        'skip': skip,
        'limit': limit,
      },
    );
    return FileListResponse.fromJson(response.data);
  }

  /// 获取文件详情
  Future<FileResponse> getFileDetail(String fileId) async {
    final path = ApiPaths.fileDetailPath.replaceAll('{file_id}', fileId);
    final response = await _adapter.get(path);
    return FileResponse.fromJson(response.data);
  }

  /// 删除文件
  Future<void> deleteFile(String fileId) async {
    final path = ApiPaths.fileDeletePath.replaceAll('{file_id}', fileId);
    await _adapter.delete(path);
  }

  /// 获取文件访问 URL
  Future<FileUrlResponse> getFileUrl(String fileId) async {
    final path = ApiPaths.fileUrlPath.replaceAll('{file_id}', fileId);
    final response = await _adapter.get(path);
    return FileUrlResponse.fromJson(response.data);
  }

  /// 归档文件
  Future<void> archiveFile(String fileId) async {
    final path = ApiPaths.fileArchivePath.replaceAll('{file_id}', fileId);
    await _adapter.post(path);
  }
}
