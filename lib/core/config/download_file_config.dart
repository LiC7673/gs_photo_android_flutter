import 'api_config.dart';

class DownloadFileConfig {
  static String getFileDetailUrl(String fileId) =>
      ApiPaths.fileDetailPath.replaceAll('{file_id}', fileId);

  static String getFileUrlUrl(String fileId) =>
      ApiPaths.fileUrlPath.replaceAll('{file_id}', fileId);

  static String getFileDownloadInitUrl(String fileId) =>
      ApiPaths.fileDownloadInitPath.replaceAll('{file_id}', fileId);

  static String getFileDownloadChunkUrl(String fileId) =>
      ApiPaths.fileDownloadChunkPath.replaceAll('{file_id}', fileId);

  static String getFileDownloadCompleteUrl(String downloadId) =>
      ApiPaths.fileDownloadCompletePath.replaceAll(
        '{download_id}',
        downloadId,
      );

  static String getFileArchiveUrl(String fileId) =>
      ApiPaths.fileArchivePath.replaceAll('{file_id}', fileId);

  static String getFileDeleteUrl(String fileId) =>
      ApiPaths.fileDeletePath.replaceAll('{file_id}', fileId);
}
