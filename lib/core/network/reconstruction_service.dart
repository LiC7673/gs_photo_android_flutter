import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/api_config.dart';
import '../config/reconstruction_config.dart';
import 'download_service.dart';
import 'dio_adapter.dart';
import 'reconstruction_models.dart';
import 'upload_service.dart';

class ReconstructionService {
  final DioAdapter _adapter;
  final ReconstructionHook? onHook;

  Future<ReconstructionTaskResponse?> createTask(
    ReconstructionCreateTaskRequest request,
  ) async {
    final sanitizedRequest = ReconstructionCreateTaskRequest(
      title: request.title,
      params: _sanitizeAlgorithmParams(request.params, request.algorithm),
      algorithm: request.algorithm,
    );
    _emit('create:start', payload: sanitizedRequest.toJson());
    try {
      final response = await _adapter.post(
        ReconstructionConfig.getCreateTaskUrl(),
        data: sanitizedRequest.toJson(),
      );
      final result = ReconstructionTaskResponse.fromJson(
        _readObject(response.data),
      );
      _emit('create:success', taskId: result.taskId);
      return result;
    } on DioException catch (e) {
      _emitError('create:error', e);
      return null;
    } catch (e) {
      _emit('create:error', payload: {'error': e.toString()});
      return null;
    }
  }

  Future<ReconstructionStatusResponse?> setTaskVisibility({
    required String taskId,
    required String visibility,
  }) async {
    final normalized = visibility == 'public' ? 'public' : 'private';
    final path = ApiPaths.reconstructionVisibilityPath.replaceAll(
      '{task_id}',
      taskId,
    );
    _emit(
      'visibility:start',
      taskId: taskId,
      payload: {'visibility': normalized},
    );
    try {
      final response = await _adapter.patch(
        path,
        data: {'visibility': normalized},
      );
      debugPrint(
        '[API] success visibility raw taskId=$taskId data=${response.data}',
      );
      final result = ReconstructionStatusResponse.fromJson(
        _readObject(response.data),
      );
      _emit(
        'visibility:success',
        taskId: taskId,
        payload: {
          'visibility': result.visibility,
          'has_visibility': result.hasVisibility,
        },
      );
      return result;
    } on DioException catch (e) {
      _emitError('visibility:error', e, taskId: taskId);
      return null;
    } catch (e) {
      _emit(
        'visibility:error',
        taskId: taskId,
        payload: {'error': e.toString()},
      );
      return null;
    }
  }

  Future<ReconstructionStartResponse?> startWithUploadedImages({
    required String taskId,
    required ReconstructionStartUploadedRequest request,
  }) async {
    final sanitizedRequest = ReconstructionStartUploadedRequest(
      imageFileIds: request.imageFileIds,
      params: _sanitizeAlgorithmParams(request.params, request.algorithm),
      algorithm: request.algorithm,
      inputType: request.inputType,
    );
    _emit(
      'start_uploaded:start',
      taskId: taskId,
      payload: sanitizedRequest.toJson(),
    );
    try {
      final response = await _adapter.post(
        ReconstructionConfig.getStartUploadedUrl(taskId),
        data: sanitizedRequest.toJson(),
      );
      final result = ReconstructionStartResponse.fromJson(
        _readObject(response.data),
      );
      _emit('start_uploaded:success', taskId: result.taskId);
      return result;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        final fallback = await _tryLegacyStartUploadedPath(
          taskId: taskId,
          request: request,
        );
        if (fallback != null) return fallback;
      }
      _emitError('start_uploaded:error', e, taskId: taskId);
      return null;
    } catch (e) {
      _emit(
        'start_uploaded:error',
        taskId: taskId,
        payload: {'error': e.toString()},
      );
      return null;
    }
  }

  ReconstructionService({DioAdapter? adapter, this.onHook})
    : _adapter = adapter ?? DioAdapter();

  Future<ReconstructionStartResponse?> _tryLegacyStartUploadedPath({
    required String taskId,
    required ReconstructionStartUploadedRequest request,
  }) async {
    const legacyPath = 'reconstruction/tasks/{task_id}/start-uploaded';
    final path = legacyPath.replaceAll('{task_id}', taskId);
    final sanitizedRequest = ReconstructionStartUploadedRequest(
      imageFileIds: request.imageFileIds,
      params: _sanitizeAlgorithmParams(request.params, request.algorithm),
      algorithm: request.algorithm,
      inputType: request.inputType,
    );
    _emit(
      'start_uploaded_legacy:start',
      taskId: taskId,
      payload: sanitizedRequest.toJson(),
    );
    try {
      final response = await _adapter.post(
        path,
        data: sanitizedRequest.toJson(),
      );
      final result = ReconstructionStartResponse.fromJson(
        _readObject(response.data),
      );
      _emit('start_uploaded_legacy:success', taskId: result.taskId);
      return result;
    } on DioException catch (e) {
      _emitError('start_uploaded_legacy:error', e, taskId: taskId);
      return null;
    } catch (e) {
      _emit(
        'start_uploaded_legacy:error',
        taskId: taskId,
        payload: {'error': e.toString()},
      );
      return null;
    }
  }

  Future<ReconstructionStartResponse?> startWithLocalFiles({
    required List<String> filePaths,
    required Map<String, dynamic> params,
    String? algorithm,
    ProgressCallback? onSendProgress,
  }) async {
    _emit(
      'start_files:start',
      payload: {
        'file_count': filePaths.length,
        'algorithm': algorithm,
        'params': params,
      },
    );
    try {
      return _startWithUploadedFallback(
        filePaths: filePaths,
        params: params,
        algorithm: algorithm,
        onSendProgress: onSendProgress,
      );
    } catch (e) {
      _emit('start_files:error', payload: {'error': e.toString()});
      return null;
    }
  }

  Future<ReconstructionStartResponse?> _startWithUploadedFallback({
    required List<String> filePaths,
    required Map<String, dynamic> params,
    String? algorithm,
    ProgressCallback? onSendProgress,
  }) async {
    _emit(
      'start_files_fallback:start',
      payload: {'file_count': filePaths.length, 'algorithm': algorithm},
    );

    try {
      final createdTask = await createTask(
        ReconstructionCreateTaskRequest(
          title: (params['task_name'] ?? params['title'] ?? 'Untitled task')
              .toString(),
          params: params,
          algorithm: algorithm,
        ),
      );
      final taskId = createdTask?.taskId;
      if (taskId == null || taskId.isEmpty) {
        _emit('start_files_fallback:error', payload: {'error': 'no_task_id'});
        return null;
      }
      await _applyRequestedVisibility(taskId, params);

      final uploadService = UploadService();
      final fileIds = <String>[];
      for (var index = 0; index < filePaths.length; index++) {
        final uploaded = await uploadService.uploadFile(
          filePaths[index],
          onProgress: (fileProgress) {
            final total = filePaths.length * 2;
            final sent = (index + fileProgress) * 2;
            onSendProgress?.call((sent * 1000).round(), total * 1000);
          },
        );
        fileIds.add(uploaded.fileId);
      }

      onSendProgress?.call(filePaths.length * 2 - 1, filePaths.length * 2);
      final started = await startWithUploadedImages(
        taskId: taskId,
        request: ReconstructionStartUploadedRequest(
          imageFileIds: fileIds,
          params: params,
          algorithm: algorithm,
          inputType: _inputTypeForAlgorithm(algorithm, params),
        ),
      );
      if (started == null) {
        _emit(
          'start_files_fallback:error',
          taskId: taskId,
          payload: {'error': 'start_uploaded_failed'},
        );
        return null;
      }

      onSendProgress?.call(1, 1);
      _emit('start_files_fallback:success', taskId: started.taskId);
      return started;
    } catch (e) {
      _emit('start_files_fallback:error', payload: {'error': e.toString()});
      return null;
    }
  }

  /// 鑾峰彇鍙敤閲嶅缓绠楁硶
  Future<ReconstructionAlgorithmsResponse?> listAlgorithms() async {
    _emit('algorithms:start');
    try {
      final response = await _adapter.get(
        ApiPaths.reconstructionAlgorithmsPath,
      );
      final result = ReconstructionAlgorithmsResponse.fromJson(
        _readObject(response.data),
      );
      _emit(
        'algorithms:success',
        payload: {'default_algorithm': result.defaultAlgorithm},
      );
      return result;
    } on DioException catch (e) {
      _emitError('algorithms:error', e);
      return null;
    } catch (e) {
      _emit('algorithms:error', payload: {'error': e.toString()});
      return null;
    }
  }

  Future<ReconstructionAlgorithmsResponse?> listMeshAlgorithms() async {
    _emit('mesh_algorithms:start');
    try {
      final response = await _adapter.get(
        ApiPaths.reconstructionMeshAlgorithmsPath,
      );
      final result = ReconstructionAlgorithmsResponse.fromJson(
        _readObject(response.data),
      );
      _emit(
        'mesh_algorithms:success',
        payload: {'default_algorithm': result.defaultAlgorithm},
      );
      return result;
    } on DioException catch (e) {
      _emitError('mesh_algorithms:error', e);
      return null;
    } catch (e) {
      _emit('mesh_algorithms:error', payload: {'error': e.toString()});
      return null;
    }
  }

  /// 鍚姩閲嶅缓 (浣跨敤宸蹭笂浼犳枃浠?ID)
  Future<ReconstructionStartResponse?> startReconstruction({
    required List<String> fileIds,
    String? algorithm,
    Map<String, dynamic>? params,
  }) async {
    final rawParams = params ?? {};
    final sanitizedParams = _sanitizeAlgorithmParams(rawParams, algorithm);
    final taskTitle =
        (rawParams['task_name'] ?? rawParams['title'] ?? 'Untitled task')
            .toString();
    final request = ReconstructionStartUploadedRequest(
      imageFileIds: fileIds,
      params: sanitizedParams,
      algorithm: algorithm,
      inputType: _inputTypeForAlgorithm(algorithm, rawParams),
    );

    _emit('start:start', payload: request.toJson());
    try {
      final created = await createTask(
        ReconstructionCreateTaskRequest(
          title: taskTitle,
          params: sanitizedParams,
          algorithm: algorithm,
        ),
      );
      final taskId = created?.taskId;
      if (taskId == null || taskId.isEmpty) return null;
      await _applyRequestedVisibility(taskId, rawParams);
      final response = await _adapter.post(
        ApiPaths.reconstructionStartUploadedPath.replaceAll(
          '{task_id}',
          taskId,
        ),
        data: request.toJson(),
      );
      final result = ReconstructionStartResponse.fromJson(
        _readObject(response.data),
      );
      _emit('start:success', taskId: result.taskId);
      return result;
    } on DioException catch (e) {
      _emitError('start:error', e);
      return null;
    } catch (e) {
      _emit('start:error', payload: {'error': e.toString()});
      return null;
    }
  }

  Future<ReconstructionStartResponse?> startMeshReconstruction({
    required String taskId,
    required List<String> inputFileIds,
    required Map<String, dynamic> params,
    String algorithm = 'dash_gaussian_mesh',
  }) async {
    final request = ReconstructionMeshStartRequest(
      inputFileIds: inputFileIds,
      params: _sanitizeAlgorithmParams(params, algorithm),
      algorithm: algorithm,
    );
    final path = ApiPaths.reconstructionMeshStartPath.replaceAll(
      '{task_id}',
      taskId,
    );
    _emit('mesh_start:start', taskId: taskId, payload: request.toJson());
    try {
      final response = await _adapter.post(path, data: request.toJson());
      final result = ReconstructionStartResponse.fromJson(
        _readObject(response.data),
      );
      _emit('mesh_start:success', taskId: result.taskId);
      return result;
    } on DioException catch (e) {
      _emitError('mesh_start:error', e, taskId: taskId);
      return null;
    } catch (e) {
      _emit(
        'mesh_start:error',
        taskId: taskId,
        payload: {'error': e.toString()},
      );
      return null;
    }
  }

  /// 鏌ヨ閲嶅缓鐘舵€?
  Future<ReconstructionStatusResponse?> checkStatus(String taskId) async {
    _emit('status:start', taskId: taskId);
    try {
      final path = ApiPaths.reconstructionStatusPath.replaceAll(
        '{task_id}',
        taskId,
      );
      final response = await _adapter.get(path);
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
      return result;
    } on DioException catch (e) {
      _emitError('status:error', e, taskId: taskId);
      return null;
    } catch (e) {
      _emit('status:error', taskId: taskId, payload: {'error': e.toString()});
      return null;
    }
  }

  /// 鑾峰彇閲嶅缓鏃ュ織
  Future<ReconstructionLogsResponse?> getLogs(
    String taskId, {
    int tail = 100,
  }) async {
    _emit('logs:start', taskId: taskId, payload: {'tail': tail});
    try {
      final path = ApiPaths.reconstructionLogsPath.replaceAll(
        '{task_id}',
        taskId,
      );
      final response = await _adapter.get(
        path,
        queryParameters: {'tail': tail},
      );
      final result = ReconstructionLogsResponse.fromJson(
        _readObject(response.data),
      );
      _emit('logs:success', taskId: taskId);
      return result;
    } on DioException catch (e) {
      _emitError('logs:error', e, taskId: taskId);
      return null;
    } catch (e) {
      _emit('logs:error', taskId: taskId, payload: {'error': e.toString()});
      return null;
    }
  }

  /// 涓嬭浇閲嶅缓缁撴灉
  Future<File?> downloadResult(String taskId) async {
    _emit('download:start', taskId: taskId);
    try {
      final path = ApiPaths.reconstructionDownloadPath.replaceAll(
        '{task_id}',
        taskId,
      );
      final response = await _adapter.get(path);

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is String) {
          final file = await _downloadUrlToFile(
            data,
            outputDirectoryName: 'reconstruction_$taskId',
            saveFileName: 'reconstructed_$taskId.ply',
          );
          _emit(
            'download:success',
            taskId: taskId,
            payload: {'path': file.path},
          );
          return file;
        }
        if (data is List<int>) {
          final directory = await getApplicationDocumentsDirectory();
          final filePath = p.join(directory.path, 'reconstructed_$taskId.ply');
          final file = File(filePath);
          await file.writeAsBytes(data);
          _emit(
            'download:success',
            taskId: taskId,
            payload: {'path': filePath},
          );
          return file;
        }
      }
      return null;
    } on DioException catch (e) {
      _emitError('download:error', e, taskId: taskId);
      return null;
    } catch (e) {
      _emit('download:error', taskId: taskId, payload: {'error': e.toString()});
      return null;
    }
  }

  /// 鍙栨秷閲嶅缓浠诲姟
  Future<File?> downloadResultFile({
    required String resultFileId,
    required String taskId,
    ValueChanged<double>? onProgress,
  }) async {
    final file = await downloadFile(
      fileId: resultFileId,
      outputDirectoryName: 'reconstruction_$taskId',
      onProgress: onProgress,
    );
    return file ?? downloadResult(taskId);
  }

  Future<File?> downloadFile({
    required String fileId,
    String outputDirectoryName = 'downloads',
    String? saveFileName,
    ValueChanged<double>? onProgress,
  }) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final saveDirectory = p.join(directory.path, outputDirectoryName);
      final result = await DownloadService(dioAdapter: _adapter).downloadFile(
        fileId,
        saveDirectory: saveDirectory,
        saveFileName: saveFileName,
        onProgress: (received, total) {
          if (total <= 0) return;
          onProgress?.call((received / total).clamp(0, 1).toDouble());
        },
      );
      return result.file;
    } on DioException catch (e) {
      _emitError('download_file:error', e);
      return null;
    } catch (e) {
      _emit('download_file:error', payload: {'error': e.toString()});
      return null;
    }
  }

  Future<File> _downloadUrlToFile(
    String url, {
    required String outputDirectoryName,
    required String saveFileName,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final saveDirectory = Directory(
      p.join(directory.path, outputDirectoryName),
    );
    if (!await saveDirectory.exists()) {
      await saveDirectory.create(recursive: true);
    }
    final resolvedUrl = _resolveDownloadUrl(url);
    final filePath = p.join(saveDirectory.path, p.basename(saveFileName));
    await _adapter.dio.download(
      resolvedUrl,
      filePath,
      options: Options(responseType: ResponseType.bytes),
    );
    return File(filePath);
  }

  String _resolveDownloadUrl(String url) {
    final trimmed = url.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme) return trimmed;
    final base = Uri.parse(_adapter.options.baseUrl);
    if (trimmed.startsWith('/')) {
      return base.replace(path: trimmed).toString();
    }
    return base.resolve(trimmed).toString();
  }

  Future<ReconstructionCancelResponse?> cancelTask(String taskId) async {
    _emit('cancel:start', taskId: taskId);
    try {
      final path = ApiPaths.reconstructionCancelPath.replaceAll(
        '{task_id}',
        taskId,
      );
      final response = await _adapter.post(path);
      final result = ReconstructionCancelResponse.fromJson(
        _readObject(response.data),
      );
      _emit(
        'cancel:success',
        taskId: taskId,
        payload: {'cancelled': result.cancelled},
      );
      return result;
    } on DioException catch (e) {
      _emitError('cancel:error', e, taskId: taskId);
      return null;
    } catch (e) {
      _emit('cancel:error', taskId: taskId, payload: {'error': e.toString()});
      return null;
    }
  }

  Future<ReconstructionDeleteResponse?> deleteTask(String taskId) async {
    _emit('delete:start', taskId: taskId);
    try {
      final path = ApiPaths.reconstructionDeleteTaskPath.replaceAll(
        '{task_id}',
        taskId,
      );
      debugPrint('[API] trigger DELETE task path=$path');
      final response = await _adapter.delete(path);
      final result = ReconstructionDeleteResponse.fromJson(
        _readObject(response.data),
      );
      _emit(
        'delete:success',
        taskId: taskId,
        payload: {'deleted': result.deleted, 'status': result.status},
      );
      debugPrint(
        '[API] result delete task success taskId=${result.taskId} '
        'deleted=${result.deleted} status=${result.status}',
      );
      return result;
    } on DioException catch (e) {
      _emitError('delete:error', e, taskId: taskId);
      return null;
    } catch (e) {
      debugPrint('[API] result delete task failed taskId=$taskId error=$e');
      _emit('delete:error', taskId: taskId, payload: {'error': e.toString()});
      return null;
    }
  }

  /// 鑾峰彇鍏ㄥ眬浠诲姟鍒楄〃
  Future<List<ReconstructionTaskResponse>> listTasks() async {
    try {
      debugPrint('[API] trigger tasks:list path=${ApiPaths.taskListPath}');
      final response = await _adapter.get(ApiPaths.taskListPath);
      final tasks = _readTaskList(response.data);
      debugPrint(
        '[API] result tasks:list success count=${tasks.length} '
        'rawType=${response.data.runtimeType}',
      );
      if (tasks.isEmpty) {
        debugPrint('[API] result tasks:list empty raw=${response.data}');
      }
      return tasks;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        debugPrint(
          '[API] result tasks:list primary not_found path=${ApiPaths.taskListPath}',
        );
        return _listTasksFallback();
      }
      debugPrint(
        '[API] result tasks:list failed status=${e.response?.statusCode} '
        'data=${e.response?.data} error=${e.message}',
      );
      return [];
    } catch (e) {
      debugPrint('获取任务列表失败: $e');
      return [];
    }
  }

  Future<ReconstructionTaskResponse?> getTaskDetail(String taskId) async {
    final path = '${ApiPaths.reconstructionCreateTaskPath}/$taskId';
    try {
      debugPrint('[API] trigger tasks:detail path=$path');
      final response = await _adapter.get(path);
      final task = ReconstructionTaskResponse.fromJson(
        _readObject(response.data),
      );
      debugPrint(
        '[API] result tasks:detail success taskId=${task.taskId} '
        'previewIds=${task.previewIds.length} inputFileIds=${task.inputFileIds.length}',
      );
      if (task.inputFileIds.isEmpty) {
        debugPrint(
          '[API] result tasks:detail no input ids raw=${response.data}',
        );
      }
      return task;
    } on DioException catch (e) {
      debugPrint(
        '[API] result tasks:detail failed status=${e.response?.statusCode} '
        'data=${e.response?.data} error=${e.message}',
      );
      return null;
    } catch (e) {
      debugPrint('[API] result tasks:detail failed error=$e');
      return null;
    }
  }

  Future<List<ReconstructionTaskResponse>> _listTasksFallback() async {
    const fallbackPaths = ['reconstruction/tasks'];
    for (final path in fallbackPaths) {
      try {
        debugPrint('[API] trigger tasks:list fallback path=$path');
        final response = await _adapter.get(path);
        final tasks = _readTaskList(response.data);
        debugPrint(
          '[API] result tasks:list fallback success path=$path '
          'count=${tasks.length} rawType=${response.data.runtimeType}',
        );
        if (tasks.isEmpty) {
          debugPrint(
            '[API] result tasks:list fallback empty path=$path raw=${response.data}',
          );
        }
        return tasks;
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          debugPrint('[API] result tasks:list fallback path=$path not_found');
          continue;
        }
        debugPrint(
          '[API] result tasks:list fallback failed status=${e.response?.statusCode} '
          'data=${e.response?.data} error=${e.message}',
        );
        return [];
      } catch (e) {
        debugPrint('[API] result tasks:list fallback failed error=$e');
        return [];
      }
    }
    debugPrint('[API] result tasks:list unavailable, showing empty task list');
    return [];
  }

  Future<PublicReconstructionDiscoverPage> discoverPublicTasks({
    required int skip,
    required int limit,
  }) async {
    final page = (skip ~/ limit) + 1;
    final pageSize = limit.clamp(1, 10);
    debugPrint(
      '[API] trigger reconstruction:discover path=${ApiPaths.reconstructionDiscoverPath} '
      'page=$page page_size=$pageSize skip=$skip limit=$limit',
    );
    try {
      final response = await _adapter.get(
        ApiPaths.reconstructionDiscoverPath,
        queryParameters: {
          'page': page,
          'page_size': pageSize,
        },
      );
      debugPrint(
        '[API] success reconstruction:discover status=${response.statusCode} '
        'data=${_previewLog(response.data)}',
      );
      final parsed = PublicReconstructionDiscoverPage.fromResponse(
        response.data,
      );
      debugPrint(
        '[API] result reconstruction:discover parsed items=${parsed.items.length} '
        'total=${parsed.total} hasNext=${parsed.hasNext}',
      );
      return parsed;
    } on DioException catch (e) {
      if (e.response?.statusCode == 400 || e.response?.statusCode == 422) {
        try {
          debugPrint(
            '[API] trigger reconstruction:discover fallback skip=$skip '
            'limit=$pageSize reason_status=${e.response?.statusCode}',
          );
          final response = await _adapter.get(
            ApiPaths.reconstructionDiscoverPath,
            queryParameters: {'skip': skip, 'limit': pageSize},
          );
          debugPrint(
            '[API] success reconstruction:discover fallback '
            'status=${response.statusCode} data=${_previewLog(response.data)}',
          );
          final parsed = PublicReconstructionDiscoverPage.fromResponse(
            response.data,
          );
          debugPrint(
            '[API] result reconstruction:discover fallback parsed '
            'items=${parsed.items.length} total=${parsed.total} '
            'hasNext=${parsed.hasNext}',
          );
          return parsed;
        } catch (fallbackError) {
          debugPrint(
            '[API] result reconstruction:discover fallback failed '
            'error=$fallbackError',
          );
        }
      }
      debugPrint(
        '[API] result reconstruction:discover failed status=${e.response?.statusCode} '
        'data=${e.response?.data} error=${e.message}',
      );
      return const PublicReconstructionDiscoverPage(items: [], total: 0);
    } catch (e) {
      debugPrint('[API] result reconstruction:discover failed error=$e');
      return const PublicReconstructionDiscoverPage(items: [], total: 0);
    }
  }

  String _previewLog(Object? data) {
    final text = data.toString();
    if (text.length <= 1200) return text;
    return '${text.substring(0, 1200)}...';
  }

  List<ReconstructionTaskResponse> _readTaskList(Object? data) {
    final items = _extractTaskList(data);
    if (items.isEmpty && data is Map) {
      debugPrint(
        '[API] result tasks:list parsed empty keys=${data.keys.toList()}',
      );
    }
    return items
        .map((i) => ReconstructionTaskResponse.fromJson(_readObject(i)))
        .toList();
  }

  List _extractTaskList(Object? data) {
    if (data is List) return data;
    if (data is! Map) return const [];
    for (final key in const ['tasks', 'items', 'results', 'records']) {
      final value = data[key];
      if (value is List) return value;
    }
    final nested = data['data'];
    if (nested is List) return nested;
    if (nested is Map) return _extractTaskList(nested);
    return const [];
  }

  // --- 鍐呴儴杈呭姪鏂规硶 ---

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
    debugPrint(
      '[API] result $name failed status=${error.response?.statusCode} '
      'data=${error.response?.data} error=${error.message}',
    );
    _emit(name, taskId: taskId, payload: payload);
  }

  Map<String, dynamic> _sanitizeAlgorithmParams(
    Map<String, dynamic> params,
    String? algorithm,
  ) {
    final sanitized = Map<String, dynamic>.from(params);
    for (final key in const [
      'task_name',
      'title',
      'type',
      'resolution',
      'image_count',
      'input_count',
      'video_count',
      'algorithm',
      'images',
      'image_paths',
      'video_paths',
      'video_thumbnail_paths',
      'quality_report_path',
      'server_task_id',
      'source_task_id',
      'source_result_file_id',
      'input_type',
      'input_file_ids',
      'visibility',
    ]) {
      sanitized.remove(key);
    }

    if ((algorithm ?? '').toLowerCase() == 'anysplat') {
      for (final key in const [
        'scene_type',
        'reconstruction_type',
        'resolution_scale',
      ]) {
        sanitized.remove(key);
      }
    }
    sanitized.removeWhere((_, value) => value == null);
    return sanitized;
  }

  Future<void> _applyRequestedVisibility(
    String taskId,
    Map<String, dynamic> params,
  ) async {
    final visibility = params['visibility']?.toString();
    if (visibility != 'public' && visibility != 'private') return;
    await setTaskVisibility(taskId: taskId, visibility: visibility!);
  }

  String _inputTypeForAlgorithm(
    String? algorithm,
    Map<String, dynamic>? params,
  ) {
    final explicit = params?['input_type']?.toString().trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    if ((algorithm ?? '').toLowerCase() == 'dash_gaussian_mesh') return 'ply';
    return 'image';
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

class PublicReconstructionDiscoverPage {
  final List<PublicReconstructionTask> items;
  final int total;
  final bool? hasNext;

  const PublicReconstructionDiscoverPage({
    required this.items,
    required this.total,
    this.hasNext,
  });

  factory PublicReconstructionDiscoverPage.fromJson(Map<String, dynamic> json) {
    final rawItems =
        json['items'] ??
        json['tasks'] ??
        json['data'] ??
        json['results'] ??
        json['records'] ??
        json['list'] ??
        json['public_tasks'] ??
        const [];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map(
                (item) => PublicReconstructionTask.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList()
        : <PublicReconstructionTask>[];
    final totalValue = json['total'] ?? json['count'] ?? items.length;
    return PublicReconstructionDiscoverPage(
      items: items,
      total: totalValue is int
          ? totalValue
          : int.tryParse(totalValue.toString()) ?? items.length,
      hasNext: json['has_next'] is bool ? json['has_next'] as bool : null,
    );
  }

  factory PublicReconstructionDiscoverPage.fromResponse(Object? data) {
    if (data is List) {
      final items = data
          .whereType<Map>()
          .map(
            (item) => PublicReconstructionTask.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
      return PublicReconstructionDiscoverPage(
        items: items,
        total: items.length,
        hasNext: items.isNotEmpty,
      );
    }
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final nested = map['data'];
      if (nested is Map) {
        return PublicReconstructionDiscoverPage.fromJson(
          Map<String, dynamic>.from(nested),
        );
      }
      return PublicReconstructionDiscoverPage.fromJson(map);
    }
    return const PublicReconstructionDiscoverPage(items: [], total: 0);
  }
}

class PublicReconstructionTask {
  final String taskId;
  final String userId;
  final String ownerDisplayName;
  final String thumbnailUrl;
  final String? previewFileId;
  final List<String> previewFileIds;
  final List<String> inputFileIds;

  const PublicReconstructionTask({
    required this.taskId,
    required this.userId,
    this.ownerDisplayName = '',
    required this.thumbnailUrl,
    this.previewFileId,
    this.previewFileIds = const [],
    this.inputFileIds = const [],
  });

  factory PublicReconstructionTask.fromJson(Map<String, dynamic> json) {
    final thumbnail = _readFirstString(json, const [
      'thumbnail_url',
      'thumbnail',
      'preview_image_url',
      'preview_url',
      'cover_url',
      'image_url',
      'imageUrl',
      'thumbnailUrl',
      'cover',
    ]);
    final userId = _readFirstString(json, const [
      'user_id',
      'userId',
      'owner_id',
      'ownerId',
      'creator_id',
      'creatorId',
    ]);
    final ownerDisplayName = _readOwnerString(json, const [
      'username',
      'user_name',
      'nickname',
      'display_name',
      'owner_name',
      'creator_name',
      'author_name',
      'user',
      'owner',
      'creator',
      'author',
    ]);
    final taskId = json['task_id'] ?? json['taskId'] ?? json['id'] ?? '';
    final previewFileIds = _readStringList(
      json['preview_ids'] ?? json['previewIds'],
    );
    final previewFileId =
        previewFileIds.isNotEmpty ? previewFileIds.first : null;
    final inputFileIds = _readStringList(
      json['input_file_ids'] ??
          json['image_ids'] ??
          json['file_ids'] ??
          json['input_ids'],
    );
    debugPrint(
      '[API] result reconstruction:discover item taskId=$taskId '
      'userId=$userId owner=$ownerDisplayName previewFileId=$previewFileId '
      'previewIds=${previewFileIds.length} inputFileIds=${inputFileIds.length} '
      'thumbnail=${thumbnail.isNotEmpty}',
    );
    return PublicReconstructionTask(
      taskId: taskId.toString(),
      userId: userId,
      ownerDisplayName: ownerDisplayName,
      thumbnailUrl: thumbnail,
      previewFileId: previewFileId,
      previewFileIds: previewFileIds,
      inputFileIds: inputFileIds,
    );
  }

  static String _readFirstString(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value == null) continue;
      if (value is Map) {
        final nested = _readFirstString(
          Map<String, dynamic>.from(value),
          const ['url', 'file_url', 'download_url', 'thumbnail_url'],
        );
        if (nested.isNotEmpty) return nested;
      } else {
        final text = value.toString();
        if (text.isNotEmpty && text != 'null') return text;
      }
    }
    final files = json['files'] ?? json['assets'];
    if (files is List) {
      for (final file in files.whereType<Map>()) {
        final map = Map<String, dynamic>.from(file);
        final category = (map['category'] ?? map['type'] ?? '').toString();
        if (category.contains('preview') || category.contains('thumbnail')) {
          final nested = _readFirstString(map, const [
            'url',
            'file_url',
            'download_url',
            'thumbnail_url',
          ]);
          if (nested.isNotEmpty) return nested;
        }
      }
    }
    return '';
  }

  static String _readOwnerString(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value == null) continue;
      if (value is Map) {
        final nested = _readOwnerString(
          Map<String, dynamic>.from(value),
          const [
            'username',
            'user_name',
            'nickname',
            'display_name',
            'name',
            'id',
            'user_id',
          ],
        );
        if (nested.isNotEmpty) return nested;
      } else {
        final text = value.toString().trim();
        if (text.isNotEmpty && text != 'null') return text;
      }
    }
    return '';
  }

  static List<String> _readStringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty && item != 'null')
        .toList();
  }
}
