import 'dart:io';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../config/upload_file_config.dart';
import 'dio_adapter.dart';
import 'upload_models.dart';

class UploadService {
  final DioAdapter _dioAdapter = DioAdapter();

  /// 获取文件 MIME 类型
  String _getMimeType(String filePath) {
    final extension = p.extension(filePath).toLowerCase().replaceFirst('.', '');
    switch (extension) {
      case 'mp4':
      case 'mov':
        return 'video/$extension';
      case 'jpg':
      case 'jpeg':
      case 'png':
        return 'image/$extension';
      case 'ply':
        return 'model/$extension';
      case 'zip':
      case 'json':
        return 'other/$extension';
      default:
        return 'other/$extension';
    }
  }

  /// 计算文件 SHA256 哈希
  Future<String> _calculateFileHash(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  /// 初始化上传
  Future<UploadInitResponse> initializeUpload(String filePath) async {
    final file = File(filePath);
    final fileName = p.basename(filePath);
    final fileSize = await file.length();
    debugPrint('[API] trigger initializeUpload file=$fileName size=$fileSize');
    final fileHash = await _calculateFileHash(file);
    final mimeType = _getMimeType(filePath);

    final request = UploadInitRequest(
      filename: fileName,
      fileSize: fileSize,
      chunkSize: UploadFileConfig.defaultChunkSize,
      mimeType: mimeType,
      fileHash: fileHash,
    );

    final response = await _dioAdapter.post(
      UploadFileConfig.getUploadInitUrl(),
      data: request.toJson(),
    );
    // final url = UploadFileConfig.getUploadInitUrl();
    // final bodyData = request.toJson();
    // final headers = _dioAdapter.options.headers;
    // // 👇 开始打印调试信息
    // debugPrint('========== 发起上传初始化请求 ==========');
    // debugPrint('➡️ [URL]: $url');
    // debugPrint('➡️ [Headers]: $headers');
    // // 使用 jsonEncode 可以把 Map 转成字符串，方便查看长串 JSON
    // debugPrint('➡️ [Body]: ${jsonEncode(bodyData)}');
    // debugPrint('➡️ [Reponse]: ${jsonEncode(response.data)}');
    // debugPrint('========================================');
    // // debugPrint()
    final result = UploadInitResponse.fromJson(response.data);
    debugPrint(
      '[API] result initializeUpload uploadId=${result.uploadId} '
      'chunks=${result.totalChunks}',
    );
    return result;
  }

  /// 上传分
  Future<ChunkResponse> uploadChunk({
    required String uploadId,
    required int chunkIndex,
    required List<int> chunkData,
  }) async {
    debugPrint(
      '[API] trigger uploadChunk uploadId=$uploadId '
      'chunkIndex=$chunkIndex size=${chunkData.length}',
    );
    final response = await _dioAdapter.put(
      UploadFileConfig.getUploadChunkUrl(uploadId),
      data: Stream.fromIterable([chunkData]),
      queryParameters: {'chunk_index': chunkIndex},
      options: Options(
        contentType: 'application/octet-stream',
        headers: {'Content-Length': chunkData.length},
      ),
    );

    final result = ChunkResponse.fromJson(response.data);
    debugPrint(
      '[API] result uploadChunk uploadId=$uploadId '
      'chunkIndex=$chunkIndex etag=${result.etag}',
    );
    return result;
  }

  /// 查询上传进度
  Future<UploadProgressResponse> checkProgress(String uploadId) async {
    debugPrint('[API] trigger checkUploadProgress uploadId=$uploadId');
    final response = await _dioAdapter.get(
      UploadFileConfig.getUploadProgressUrl(uploadId),
    );
    final result = UploadProgressResponse.fromJson(response.data);
    debugPrint('[API] result checkUploadProgress uploadId=$uploadId');
    return result;
  }

  /// 合并分片
  Future<MergeResponse> mergeChunks({
    required String uploadId,
    required int expectedSize,
    String? expectedHash,
    required List<MergeRequestPart> parts,
  }) async {
    debugPrint(
      '[API] trigger mergeChunks uploadId=$uploadId parts=${parts.length}',
    );
    final request = MergeRequest(
      expectedHash: expectedHash,
      expectedSize: expectedSize,
      parts: parts,
    );

    final response = await _dioAdapter.post(
      UploadFileConfig.getUploadMergeUrl(uploadId),
      data: request.toJson(),
    );

    final result = MergeResponse.fromJson(response.data);
    debugPrint(
      '[API] result mergeChunks uploadId=$uploadId '
      'fileId=${result.fileId} verified=${result.verified}',
    );
    return result;
  }

  /// 取消上传
  Future<void> cancelUpload(String fileId) async {
    debugPrint('[API] trigger cancelUpload fileId=$fileId');
    await _dioAdapter.post(UploadFileConfig.getUploadCancelUrl(fileId));
    debugPrint('[API] result cancelUpload fileId=$fileId');
  }

  /// 高层封装：完整上传文件流程
  Future<MergeResponse> uploadFile(
    String filePath, {
    Function(double)? onProgress,
  }) async {
    final file = File(filePath);
    final fileSize = await file.length();
    debugPrint(
      '[API] trigger uploadFile file=${p.basename(filePath)} size=$fileSize',
    );

    // 1. 初始化
    final initData = await initializeUpload(filePath);
    final uploadId = initData.uploadId;
    final chunkSize = initData.chunkSize;
    final totalChunks = initData.totalChunks;

    List<MergeRequestPart> parts = [];

    // 2. 分片上传
    final bytes = await file.readAsBytes();
    for (int i = 0; i < totalChunks; i++) {
      int start = i * chunkSize;
      int end = (i + 1) * chunkSize;
      if (end > fileSize) end = fileSize;

      final chunkData = bytes.sublist(start, end);

      // 可以先检查进度，实现断点续传（此处简化为直接上传）
      final chunkRes = await uploadChunk(
        uploadId: uploadId,
        chunkIndex: i,
        chunkData: chunkData,
      );

      parts.add(MergeRequestPart(chunkIndex: i, etag: chunkRes.etag));

      if (onProgress != null) {
        onProgress((i + 1) / totalChunks);
      }
    }

    // 3. 合并
    final fileHash = md5.convert(bytes).toString(); // 后端合并请求需要的是 MD5
    final result = await mergeChunks(
      uploadId: uploadId,
      expectedSize: fileSize,
      expectedHash: fileHash,
      parts: parts,
    );
    debugPrint(
      '[API] result uploadFile file=${p.basename(filePath)} '
      'storageKey=${result.storageKey}',
    );
    return result;
  }
}
