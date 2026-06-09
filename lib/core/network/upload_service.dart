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
      case 'jpeg':
      case 'jpg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
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
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// 初始化上传
  Future<UploadInitResponse> initializeUpload(
    String filePath, {
    String? fileHash,
  }) async {
    final file = File(filePath);
    final fileName = p.basename(filePath);
    final fileSize = await file.length();
    debugPrint('[API] trigger initializeUpload file=$fileName size=$fileSize');
    final resolvedFileHash = fileHash ?? await _calculateFileHash(file);
    final mimeType = _getMimeType(filePath);

    final request = UploadInitRequest(
      filename: fileName,
      fileSize: fileSize,
      chunkSize: UploadFileConfig.defaultChunkSize,
      mimeType: mimeType,
      fileHash: resolvedFileHash,
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
    final parsed = UploadInitResponse.fromJson(_readObject(response.data));
    final normalizedChunkSize = parsed.chunkSize > 0
        ? parsed.chunkSize
        : UploadFileConfig.defaultChunkSize;
    final normalizedTotalChunks = parsed.totalChunks > 0
        ? parsed.totalChunks
        : (fileSize / normalizedChunkSize).ceil();
    final result = UploadInitResponse(
      uploadId: parsed.uploadId,
      chunkSize: normalizedChunkSize,
      totalChunks: normalizedTotalChunks,
      expiresAt: parsed.expiresAt,
      alreadyUploaded: parsed.alreadyUploaded,
      fileId: parsed.fileId,
      imageId: parsed.imageId,
      fileHash: parsed.fileHash,
      storageKey: parsed.storageKey,
    );
    if (result.uploadId.isEmpty && !result.alreadyUploaded) {
      throw StateError('Invalid upload init response: ${response.data}');
    }
    debugPrint(
      '[API] result initializeUpload uploadId=${result.uploadId} '
      'chunks=${result.totalChunks} alreadyUploaded=${result.alreadyUploaded}',
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

    final result = ChunkResponse.fromJson(_readObject(response.data));
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
    final result = UploadProgressResponse.fromJson(_readObject(response.data));
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

    final result = MergeResponse.fromJson(_readObject(response.data));
    if (result.fileId.isEmpty) {
      throw StateError('Invalid upload merge response: ${response.data}');
    }
    debugPrint(
      '[API] result mergeChunks uploadId=$uploadId '
      'fileId=${result.fileId} verified=${result.verified}',
    );
    return result;
  }

  /// 取消上传
  Future<void> cancelUpload(String uploadId) async {
    debugPrint('[API] trigger cancelUpload uploadId=$uploadId');
    await _dioAdapter.post(UploadFileConfig.getUploadCancelUrl(uploadId));
    debugPrint('[API] result cancelUpload uploadId=$uploadId');
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
    final fileHash = await _calculateFileHash(file);
    final initData = await initializeUpload(filePath, fileHash: fileHash);
    if (initData.alreadyUploaded) {
      final fileId = initData.fileId.isNotEmpty
          ? initData.fileId
          : initData.imageId;
      if (fileId.isEmpty) {
        throw StateError(
          'Invalid already uploaded response: ${initData.toJson()}',
        );
      }
      onProgress?.call(1);
      debugPrint(
        '[API] result uploadFile reused file=${p.basename(filePath)} '
        'fileId=$fileId',
      );
      return MergeResponse(
        fileId: fileId,
        fileHash: initData.fileHash,
        storageKey: initData.storageKey,
        verified: true,
      );
    }

    final uploadId = initData.uploadId;
    final chunkSize = initData.chunkSize;
    final totalChunks = initData.totalChunks;

    List<MergeRequestPart> parts = [];

    // 2. 分片上传
    final reader = await file.open();
    try {
      for (int i = 0; i < totalChunks; i++) {
        final remaining = fileSize - (i * chunkSize);
        final readSize = remaining < chunkSize ? remaining : chunkSize;

        final chunkData = await reader.read(readSize);

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
    } finally {
      await reader.close();
    }

    // 3. 合并
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

  Map<String, dynamic> _readObject(Object? data) {
    if (data is! Map) return const <String, dynamic>{};
    final map = Map<String, dynamic>.from(data);
    for (final key in const ['data', 'file', 'upload', 'result']) {
      final nested = map[key];
      if (nested is Map) return Map<String, dynamic>.from(nested);
    }
    return map;
  }
}
