import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/download_file_config.dart';
import 'dio_adapter.dart';
import 'download_models.dart';

class DownloadService {
  final DioAdapter _dioAdapter;
  final DownloadHook? onHook;

  DownloadService({DioAdapter? dioAdapter, this.onHook})
      : _dioAdapter = dioAdapter ?? DioAdapter();

  Future<DownloadFileInfo> getFileInfo(String fileId) async {
    _emit('file_info:start', fileId: fileId);
    debugPrint('[API] trigger getFileInfo fileId=$fileId');

    try {
      final response = await _dioAdapter.get(
        DownloadFileConfig.getFileDetailUrl(fileId),
      );
      final result = DownloadFileInfo.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );

      _emit(
        'file_info:success',
        fileId: fileId,
        payload: {'filename': result.filename, 'file_size': result.fileSize},
      );
      debugPrint(
        '[API] result getFileInfo fileId=$fileId filename=${result.filename}',
      );
      return result;
    } on DioException catch (e) {
      _emitError('file_info:error', e, fileId: fileId);
      rethrow;
    }
  }

  Future<DownloadUrlResponse> getFileUrl(String fileId) async {
    _emit('file_url:start', fileId: fileId);
    debugPrint('[API] trigger getFileUrl fileId=$fileId');

    try {
      final response = await _dioAdapter.get(
        DownloadFileConfig.getFileUrlUrl(fileId),
      );
      final result = DownloadUrlResponse.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );

      _emit(
        'file_url:success',
        fileId: fileId,
        payload: {'expires_in': result.expiresIn},
      );
      debugPrint('[API] result getFileUrl fileId=$fileId');
      return result;
    } on DioException catch (e) {
      _emitError('file_url:error', e, fileId: fileId);
      rethrow;
    }
  }

  Future<DownloadFileResult> downloadFile(
    String fileId, {
    String? saveDirectory,
    String? saveFileName,
    bool fetchInfo = true,
    ProgressCallback? onProgress,
  }) async {
    _emit('download:start', fileId: fileId);
    debugPrint('[API] trigger downloadFile fileId=$fileId');

    try {
      DownloadFileInfo? info;
      if (fetchInfo) {
        info = await getFileInfo(fileId);
      }

      final directoryPath = saveDirectory ?? await _defaultDownloadDirectory();
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final filename = _resolveFileName(fileId, saveFileName, info);
      final localPath = p.join(directory.path, filename);
      debugPrint(
        '[API] result downloadFile using chunk api fileId=$fileId '
        'filename=$filename',
      );
      return _downloadFileByChunks(
        fileId,
        localPath: localPath,
        info: info,
        onProgress: onProgress,
      );
    } on DioException catch (e) {
      _emitError('download:error', e, fileId: fileId);
      rethrow;
    } catch (e) {
      _emit('download:error', fileId: fileId, payload: {'error': e.toString()});
      rethrow;
    }
  }

  Future<DownloadFileResult> _downloadFileByChunks(
    String fileId, {
    required String localPath,
    DownloadFileInfo? info,
    ProgressCallback? onProgress,
  }) async {
    final initResponse = await _dioAdapter.post(
      DownloadFileConfig.getFileDownloadInitUrl(fileId),
      data: const {'chunk_size': 1048576},
    );
    final initRoot = Map<String, dynamic>.from(initResponse.data as Map);
    final initData = initRoot['data'] is Map
        ? Map<String, dynamic>.from(initRoot['data'] as Map)
        : initRoot;
    final downloadId = (initData['download_id'] ?? '').toString();
    final totalChunks = (initData['total_chunks'] as num?)?.toInt() ?? 0;
    final fileSize = (initData['file_size'] as num?)?.toInt() ??
        info?.fileSize ??
        0;
    if (downloadId.isEmpty || totalChunks <= 0) {
      throw StateError('Invalid download init response: $initData');
    }

    final file = File(localPath);
    final sink = file.openWrite();
    var receivedBytes = 0;
    var downloadedChunks = 0;
    try {
      for (var index = 0; index < totalChunks; index++) {
        final response = await _dioAdapter.get(
          DownloadFileConfig.getFileDownloadChunkUrl(fileId),
          queryParameters: {
            'download_id': downloadId,
            'chunk_index': index,
          },
          options: Options(responseType: ResponseType.bytes),
        );
        final chunk = _decodeChunkPayload(response.data);
        final bytes = chunk.bytes;
        sink.add(bytes);
        receivedBytes += bytes.length;
        downloadedChunks++;
        onProgress?.call(receivedBytes, fileSize);
      }
    } finally {
      await sink.close();
    }

    debugPrint(
      '[API] result download complete skipped fileId=$fileId '
      'reason=local_chunks_written chunks=$downloadedChunks',
    );

    final actualBytes = await file.length();
    _evictDownloadedImage(localPath);
    final result = DownloadFileResult(
      fileId: fileId,
      url: localPath,
      localPath: localPath,
      receivedBytes: actualBytes,
      totalBytes: fileSize > 0 ? fileSize : actualBytes,
      info: info,
    );
    _emit(
      'download:success',
      fileId: fileId,
      payload: {'local_path': localPath, 'total': result.totalBytes},
    );
    return result;
  }

  _DownloadedChunk _decodeChunkPayload(Object? data) {
    if (data is List<int>) {
      final text = _tryDecodeText(data);
      if (text != null && _looksWrappedChunk(text)) {
        return _decodeChunkPayload(text);
      }
      final decodedBase64 = text == null ? null : _tryDecodeBase64Text(text);
      if (decodedBase64 != null) return _DownloadedChunk(decodedBase64);
      return _DownloadedChunk(data);
    }
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final chunk = _decodeChunkPayload(
        map['data'] ?? map['chunk'] ?? map['content'] ?? map['bytes'],
      );
      return _DownloadedChunk(
        chunk.bytes,
        etag: map['etag']?.toString() ?? chunk.etag,
      );
    }
    if (data is String) {
      final trimmed = data.trim();
      if (_looksWrappedChunk(trimmed)) {
        final decoded = jsonDecode(trimmed);
        return _decodeChunkPayload(decoded);
      }
      try {
        return _DownloadedChunk(base64Decode(trimmed));
      } catch (_) {
        return _DownloadedChunk(utf8.encode(data));
      }
    }
    if (data is List) return _DownloadedChunk(data.whereType<int>().toList());
    throw StateError('Unsupported chunk response: ${data.runtimeType}');
  }

  bool _looksWrappedChunk(String text) {
    if (text.isEmpty) return false;
    return text.startsWith('{') ||
        text.startsWith('[') ||
        (text.startsWith('"') && text.endsWith('"'));
  }

  String? _tryDecodeText(List<int> bytes) {
    try {
      final text = utf8.decode(bytes, allowMalformed: false).trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  List<int>? _tryDecodeBase64Text(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), '');
    if (normalized.length < 16 || normalized.length % 4 != 0) return null;
    if (!RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(normalized)) return null;
    try {
      return base64Decode(normalized);
    } catch (_) {
      return null;
    }
  }

  Future<void> archiveFile(String fileId) async {
    _emit('archive:start', fileId: fileId);
    debugPrint('[API] trigger archiveFile fileId=$fileId');
    try {
      await _dioAdapter.post(DownloadFileConfig.getFileArchiveUrl(fileId));
      _emit('archive:success', fileId: fileId);
      debugPrint('[API] result archiveFile fileId=$fileId');
    } on DioException catch (e) {
      _emitError('archive:error', e, fileId: fileId);
      rethrow;
    }
  }

  Future<void> deleteFile(String fileId) async {
    _emit('delete:start', fileId: fileId);
    debugPrint('[API] trigger deleteFile fileId=$fileId');
    try {
      await _dioAdapter.delete(DownloadFileConfig.getFileDeleteUrl(fileId));
      _emit('delete:success', fileId: fileId);
      debugPrint('[API] result deleteFile fileId=$fileId');
    } on DioException catch (e) {
      _emitError('delete:error', e, fileId: fileId);
      rethrow;
    }
  }

  Future<String> _defaultDownloadDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    return p.join(directory.path, 'downloads');
  }

  String _resolveFileName(
    String fileId,
    String? saveFileName,
    DownloadFileInfo? info,
  ) {
    if (saveFileName != null && saveFileName.trim().isNotEmpty) {
      return p.basename(saveFileName.trim());
    }
    if (info != null && info.originalName.trim().isNotEmpty) {
      return p.basename(info.originalName.trim());
    }
    if (info != null && info.filename.trim().isNotEmpty) {
      return p.basename(info.filename.trim());
    }
    return 'download_$fileId';
  }

  void _evictDownloadedImage(String path) {
    PaintingBinding.instance.imageCache.evict(FileImage(File(path)));
  }

  void _emit(
    String name, {
    String? fileId,
    Map<String, dynamic> payload = const {},
  }) {
    onHook?.call(
      DownloadHookEvent(name: name, fileId: fileId, payload: payload),
    );
  }

  void _emitError(String name, DioException error, {String? fileId}) {
    _emit(
      name,
      fileId: fileId,
      payload: {
        'status_code': error.response?.statusCode,
        'response': error.response?.data,
        'message': error.message,
      },
    );
    debugPrint(
      '[API] result $name failed status=${error.response?.statusCode} '
      'data=${error.response?.data} error=$error',
    );
  }
}

class _DownloadedChunk {
  final List<int> bytes;
  final String? etag;

  const _DownloadedChunk(this.bytes, {this.etag});
}
