import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/api_config.dart';
import '../config/reconstruction_config.dart';
import 'dio_adapter.dart';
import 'reconstruction_models.dart';

class ReconstructionService {
  final DioAdapter _adapter;
  final ReconstructionHook? onHook;

  ReconstructionService({DioAdapter? adapter, this.onHook})
    : _adapter = adapter ?? DioAdapter();

  Future<ReconstructionTaskResponse?> createTask(
    ReconstructionCreateTaskRequest request,
  ) async {
    _emit('create_task:start', payload: request.toJson());
    debugPrint('[API] trigger createReconstructionTask');
    try {
      final response = await _adapter.post(
        ReconstructionConfig.getCreateTaskUrl(),
        data: request.toJson(),
      );
      final result = ReconstructionTaskResponse.fromJson(
        _readObject(response.data),
      );
      _emit('create_task:success', taskId: result.taskId);
      debugPrint(
        '[API] result createReconstructionTask taskId=${result.taskId}',
      );
      return result;
    } on DioException catch (e) {
      _emitError('create_task:error', e);
      return null;
    } catch (e) {
      _emit('create_task:error', payload: {'error': e.toString()});
      debugPrint('[API] result createReconstructionTask failed error=$e');
      return null;
    }
  }

  Future<ReconstructionStartResponse?> startWithUploadedImages({
    required String taskId,
    required ReconstructionStartUploadedRequest request,
  }) async {
    _emit('start_uploaded:start', taskId: taskId, payload: request.toJson());
    debugPrint(
      '[API] trigger startReconstructionWithUploadedImages taskId=$taskId',
    );
    try {
      final response = await _adapter.post(
        ReconstructionConfig.getStartUploadedUrl(taskId),
        data: request.toJson(),
      );
      final result = ReconstructionStartResponse.fromJson(
        _readObject(response.data),
      );
      _emit('start_uploaded:success', taskId: result.taskId);
      debugPrint(
        '[API] result startReconstructionWithUploadedImages '
        'taskId=${result.taskId} status=${result.status}',
      );
      return result;
    } on DioException catch (e) {
      _emitError('start_uploaded:error', e, taskId: taskId);
      return null;
    } catch (e) {
      _emit(
        'start_uploaded:error',
        taskId: taskId,
        payload: {'error': e.toString()},
      );
      debugPrint(
        '[API] result startReconstructionWithUploadedImages failed error=$e',
      );
      return null;
    }
  }

  Future<ReconstructionStatusResponse?> checkStatus(String taskId) async {
    _emit('status:start', taskId: taskId);
    debugPrint('[API] trigger checkReconstructionStatus taskId=$taskId');
    try {
      final response = await _adapter.get(
        ReconstructionConfig.getStatusUrl(taskId),
      );
      final result = ReconstructionStatusResponse.fromJson(
        _readObject(response.data),
      );
      _emit(
        'status:success',
        taskId: taskId,
        payload: {
          'status': result.status,
          'progress': result.progress,
          'current_stage': result.currentStage,
        },
      );
      debugPrint(
        '[API] result checkReconstructionStatus taskId=$taskId '
        'status=${result.status}',
      );
      return result;
    } on DioException catch (e) {
      _emitError('status:error', e, taskId: taskId);
      return null;
    } catch (e) {
      _emit('status:error', taskId: taskId, payload: {'error': e.toString()});
      debugPrint('[API] result checkReconstructionStatus failed error=$e');
      return null;
    }
  }

  Future<ReconstructionCancelResponse?> cancelTask(String taskId) async {
    _emit('cancel:start', taskId: taskId);
    debugPrint('[API] trigger cancelReconstruction taskId=$taskId');
    try {
      final response = await _adapter.post(
        ReconstructionConfig.getCancelUrl(taskId),
      );
      final result = ReconstructionCancelResponse.fromJson(
        _readObject(response.data),
      );
      _emit(
        'cancel:success',
        taskId: taskId,
        payload: {'cancelled': result.cancelled, 'status': result.status},
      );
      debugPrint(
        '[API] result cancelReconstruction taskId=$taskId '
        'cancelled=${result.cancelled}',
      );
      return result;
    } on DioException catch (e) {
      _emitError('cancel:error', e, taskId: taskId);
      return null;
    } catch (e) {
      _emit('cancel:error', taskId: taskId, payload: {'error': e.toString()});
      debugPrint('[API] result cancelReconstruction failed error=$e');
      return null;
    }
  }

  Future<ReconstructionLogsResponse?> getLogs(
    String taskId, {
    int tail = 4000,
  }) async {
    _emit('logs:start', taskId: taskId, payload: {'tail': tail});
    debugPrint('[API] trigger getReconstructionLogs taskId=$taskId');
    try {
      final response = await _adapter.get(
        ReconstructionConfig.getLogsUrl(taskId),
        queryParameters: {'tail': tail},
      );
      final result = ReconstructionLogsResponse.fromJson(
        _readObject(response.data),
      );
      _emit('logs:success', taskId: taskId);
      debugPrint('[API] result getReconstructionLogs taskId=$taskId');
      return result;
    } on DioException catch (e) {
      _emitError('logs:error', e, taskId: taskId);
      return null;
    } catch (e) {
      _emit('logs:error', taskId: taskId, payload: {'error': e.toString()});
      debugPrint('[API] result getReconstructionLogs failed error=$e');
      return null;
    }
  }

  Future<ReconstructionAlgorithmsResponse?> listAlgorithms() async {
    _emit('algorithms:start');
    debugPrint('[API] trigger listReconstructionAlgorithms');
    try {
      final response = await _adapter.get(
        ReconstructionConfig.getAlgorithmsUrl(),
      );
      final result = ReconstructionAlgorithmsResponse.fromJson(
        _readObject(response.data),
      );
      _emit(
        'algorithms:success',
        payload: {'default_algorithm': result.defaultAlgorithm},
      );
      debugPrint('[API] result listReconstructionAlgorithms');
      return result;
    } on DioException catch (e) {
      _emitError('algorithms:error', e);
      return null;
    } catch (e) {
      _emit('algorithms:error', payload: {'error': e.toString()});
      debugPrint('[API] result listReconstructionAlgorithms failed error=$e');
      return null;
    }
  }

  Future<File?> downloadResult(String taskId) async {
    _emit('download:start', taskId: taskId);
    debugPrint('[API] trigger downloadReconstructionResult taskId=$taskId');
    try {
      final response = await _adapter.get(
        ReconstructionConfig.getDownloadUrl(taskId),
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.statusCode == 200) {
        final directory = await getApplicationDocumentsDirectory();
        final filePath = p.join(directory.path, 'reconstructed_$taskId.ply');
        final file = File(filePath);
        await file.writeAsBytes(response.data);
        _emit('download:success', taskId: taskId, payload: {'path': filePath});
        debugPrint(
          '[API] result downloadReconstructionResult taskId=$taskId '
          'path=$filePath',
        );
        return file;
      }
      _emit(
        'download:error',
        taskId: taskId,
        payload: {'status_code': response.statusCode},
      );
      debugPrint(
        '[API] result downloadReconstructionResult taskId=$taskId '
        'status=${response.statusCode}',
      );
      return null;
    } on DioException catch (e) {
      _emitError('download:error', e, taskId: taskId);
      return null;
    } catch (e) {
      _emit('download:error', taskId: taskId, payload: {'error': e.toString()});
      debugPrint('[API] result downloadReconstructionResult failed error=$e');
      return null;
    }
  }

  Future<File?> downloadResultFile({
    required String resultFileId,
    String? taskId,
    void Function(double progress)? onProgress,
  }) async {
    return downloadFile(
      fileId: resultFileId,
      taskId: taskId,
      outputDirectoryName: 'results',
      outputFilename: taskId == null ? null : '$taskId.obj',
      onProgress: onProgress,
    );
  }

  Future<File?> downloadFile({
    required String fileId,
    String? taskId,
    String outputDirectoryName = 'downloads',
    String? outputFilename,
    void Function(double progress)? onProgress,
  }) async {
    _emit('file_download:start', taskId: taskId, payload: {'file_id': fileId});
    debugPrint('[API] trigger downloadFile fileId=$fileId');

    try {
      final initResponse = await _adapter.post(
        _fileDownloadInitUrl(fileId),
        data: const <String, dynamic>{},
      );
      final initData = _readObject(initResponse.data);
      final downloadId = (initData['download_id'] ?? '').toString();
      if (downloadId.isEmpty) {
        throw StateError('download_id is empty');
      }

      final filename = _safeFilename(
        outputFilename ?? (initData['filename'] as String?) ?? '$fileId.bin',
      );
      final totalChunks =
          (initData['total_chunks'] as num?)?.toInt() ??
          _calculateTotalChunks(initData);
      if (totalChunks <= 0) {
        throw StateError('total_chunks is invalid: $totalChunks');
      }

      final directory = await getApplicationDocumentsDirectory();
      final outputDir = Directory(p.join(directory.path, outputDirectoryName));
      await outputDir.create(recursive: true);
      final file = File(p.join(outputDir.path, filename));
      final sink = file.openWrite();

      try {
        for (var index = 0; index < totalChunks; index++) {
          final chunkResponse = await _adapter.get<List<int>>(
            _fileDownloadChunkUrl(fileId),
            queryParameters: {'download_id': downloadId, 'chunk_index': index},
            options: Options(responseType: ResponseType.bytes),
          );
          final bytes = chunkResponse.data ?? const <int>[];
          sink.add(bytes);

          final progress = (index + 1) / totalChunks;
          onProgress?.call(progress);
          debugPrint(
            '[API] result downloadResultFile chunk=${index + 1}/$totalChunks '
            'bytes=${bytes.length}',
          );
        }
      } finally {
        await sink.close();
      }

      await getFileDownloadProgress(downloadId, taskId: taskId);

      _emit(
        'file_download:success',
        taskId: taskId,
        payload: {
          'file_id': fileId,
          'download_id': downloadId,
          'path': file.path,
        },
      );
      debugPrint('[API] result downloadFile fileId=$fileId path=${file.path}');
      return file;
    } on DioException catch (e) {
      _emitError('file_download:error', e, taskId: taskId);
      return null;
    } catch (e) {
      _emit(
        'file_download:error',
        taskId: taskId,
        payload: {'file_id': fileId, 'error': e.toString()},
      );
      debugPrint('[API] result downloadFile failed error=$e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getFileDownloadProgress(
    String downloadId, {
    String? taskId,
  }) async {
    _emit(
      'file_download_progress:start',
      taskId: taskId,
      payload: {'download_id': downloadId},
    );
    debugPrint('[API] trigger getFileDownloadProgress downloadId=$downloadId');
    try {
      final response = await _adapter.get(_fileDownloadProgressUrl(downloadId));
      final progress = _readObject(response.data);
      _emit(
        'file_download_progress:success',
        taskId: taskId,
        payload: progress,
      );
      debugPrint(
        '[API] result getFileDownloadProgress downloadId=$downloadId '
        'progress=$progress',
      );
      return progress;
    } on DioException catch (e) {
      _emitError('file_download_progress:error', e, taskId: taskId);
      return null;
    } catch (e) {
      _emit(
        'file_download_progress:error',
        taskId: taskId,
        payload: {'download_id': downloadId, 'error': e.toString()},
      );
      debugPrint('[API] result getFileDownloadProgress failed error=$e');
      return null;
    }
  }

  String _fileDownloadInitUrl(String fileId) =>
      ApiPaths.fileDownloadInitPath.replaceAll('{file_id}', fileId);

  String _fileDownloadChunkUrl(String fileId) =>
      ApiPaths.fileDownloadChunkPath.replaceAll('{file_id}', fileId);

  String _fileDownloadProgressUrl(String downloadId) =>
      ApiPaths.fileDownloadProgressPath.replaceAll('{download_id}', downloadId);

  int _calculateTotalChunks(Map<String, dynamic> data) {
    final fileSize = (data['file_size'] as num?)?.toInt();
    final chunkSize = (data['chunk_size'] as num?)?.toInt();
    if (fileSize == null || chunkSize == null || chunkSize <= 0) return 0;
    return (fileSize + chunkSize - 1) ~/ chunkSize;
  }

  String _safeFilename(String filename) {
    final normalized = filename.trim().isEmpty
        ? 'reconstruction.ply'
        : filename;
    return normalized.replaceAll(RegExp(r'[^\w.\-]+'), '_');
  }

  void _emit(
    String name, {
    String? taskId,
    Map<String, dynamic> payload = const {},
  }) {
    onHook?.call(
      ReconstructionHookEvent(name: name, taskId: taskId, payload: payload),
    );
  }

  void _emitError(String name, DioException error, {String? taskId}) {
    final payload = {
      'status_code': error.response?.statusCode,
      'response': error.response?.data,
      'message': error.message,
    };
    _emit(name, taskId: taskId, payload: payload);
    debugPrint(
      '[API] result $name failed status=${error.response?.statusCode} '
      'data=${error.response?.data} error=$error',
    );
  }

  Map<String, dynamic> _readObject(Object? data) {
    if (data is! Map) return const <String, dynamic>{};
    final map = Map<String, dynamic>.from(data);
    for (final key in const ['data', 'task', 'result']) {
      final nested = map[key];
      if (nested is Map) return Map<String, dynamic>.from(nested);
    }
    return map;
  }
}
