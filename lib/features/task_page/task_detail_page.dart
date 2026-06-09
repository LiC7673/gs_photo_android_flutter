import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/network/reconstruction_models.dart';
import '../../core/network/reconstruction_service.dart';
import '../../core/router/route_config.dart';
import '../../core/state/language_state.dart';
import '../../core/state/task_state.dart';
import '../../core/utils/video_metadata.dart';

class TaskDetailPage extends StatefulWidget {
  final String taskId;
  final List<XFile>? initialImages;
  final List<String>? initialVideos;

  const TaskDetailPage({
    super.key,
    required this.taskId,
    this.initialImages,
    this.initialVideos,
  });

  @override
  State<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<TaskDetailPage> {
  final ReconstructionService _reconstructionService = ReconstructionService();
  Timer? _statusTimer;
  bool _started = false;
  bool _startingMesh = false;
  bool _loadingRemoteTask = false;
  bool _downloadingInputFiles = false;
  bool _updatingVisibility = false;
  String _activeTaskId = '';

  @override
  void initState() {
    super.initState();
    _activeTaskId = widget.taskId;
    final images = widget.initialImages ?? const <XFile>[];
    final videos = widget.initialVideos ?? const <String>[];
    if (images.isNotEmpty || videos.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_startTask(images: images, videos: videos));
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final task = context.read<TaskState>().getTask(_activeTaskId);
        if (task == null) {
          unawaited(_loadRemoteTask(_activeTaskId));
        } else if (_shouldPoll(task)) {
          _startPolling(task.taskId);
        } else if (task.status == TaskStatus.completed &&
            task.resultPly == null) {
          unawaited(_loadRemoteTask(task.taskId));
        }
      });
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _startTask({
    required List<XFile> images,
    required List<String> videos,
  }) async {
    if (_started) return;
    _started = true;

    final taskState = context.read<TaskState>();
    final localTask = taskState.getTask(_activeTaskId);
    if (localTask == null) return;

    try {
      final validationError = await _validateUploadInputs(
        images: images,
        videos: videos,
      );
      if (validationError != null) {
        taskState.updateTaskProgress(
          _activeTaskId,
          localTask.progress,
          status: TaskStatus.failed,
          stage: validationError,
        );
        return;
      }

      taskState.updateTaskProgress(
        _activeTaskId,
        0.02,
        status: TaskStatus.pending,
        stage: 'Preparing reconstruction task',
      );

      final params = Map<String, dynamic>.from(localTask.params);
      final algorithm = await _resolveAvailableAlgorithm(
        _normalizeAlgorithm(params['algorithm']?.toString()),
      );
      params['algorithm'] = algorithm;

      final uploadItems = <_UploadItem>[
        ...images.map((image) => _UploadItem.image(image)),
        ...videos.map((videoPath) => _UploadItem.video(videoPath)),
      ];
      final imagePaths = images.map((image) => image.path).toList();
      final videoPaths = List<String>.from(videos);
      final filePaths = uploadItems.map((item) => item.path).toList();
      final localFiles = uploadItems
          .map((item) => item.toStorageFile())
          .toList();

      taskState.upsertTask(
        localTask.copyWith(
          params: {
            ...params,
            'image_paths': imagePaths,
            if (videoPaths.isNotEmpty) 'video_paths': videoPaths,
          },
          files: localFiles,
          status: TaskStatus.uploadingFiles,
          progress: 0.05,
          stage: 'Uploading assets',
          updatedAt: DateTime.now(),
        ),
      );

      taskState.updateTaskProgress(
        _activeTaskId,
        0.08,
        status: TaskStatus.uploadingFiles,
        stage: 'Submitting reconstruction assets',
      );
      final started = await _reconstructionService.startWithLocalFiles(
        filePaths: filePaths,
        params: params,
        algorithm: algorithm,
        onSendProgress: (sent, total) {
          if (total <= 0) return;
          final progress = (sent / total).clamp(0.0, 1.0).toDouble();
          taskState.updateTaskProgress(
            _activeTaskId,
            (0.08 + progress * 0.5).clamp(0.08, 0.58).toDouble(),
            status: TaskStatus.uploadingFiles,
            stage: 'Uploading assets',
          );
        },
      );
      if (started == null) {
        taskState.updateTaskProgress(
          _activeTaskId,
          0.58,
          status: TaskStatus.failed,
          stage: 'Submit reconstruction task failed',
        );
        return;
      }

      final serverTaskId = started.taskId;
      if (serverTaskId.isEmpty) {
        taskState.updateTaskProgress(
          _activeTaskId,
          0.58,
          status: TaskStatus.failed,
          stage: 'Server did not return task id',
        );
        return;
      }

      final taskBeforeReplace = taskState.getTask(_activeTaskId) ?? localTask;
      taskState.replaceTaskId(
        _activeTaskId,
        taskBeforeReplace.copyWith(
          taskId: serverTaskId,
          params: {
            ...params,
            'server_task_id': serverTaskId,
            'image_paths': imagePaths,
            if (videoPaths.isNotEmpty) 'video_paths': videoPaths,
          },
          files: localFiles
              .map((file) => file.copyWith(status: FileSyncStatus.synced))
              .toList(),
          status: TaskStatus.processing,
          progress: 0.62,
          stage: 'Algorithm is reconstructing',
          updatedAt: DateTime.now(),
        ),
      );
      _activeTaskId = serverTaskId;

      taskState.updateTaskProgress(
        _activeTaskId,
        0.62,
        status: TaskStatus.processing,
        stage: 'Algorithm is reconstructing',
      );
      _startPolling(_activeTaskId);
    } catch (e) {
      debugPrint('[API] result task_detail_start failed error=$e');
      taskState.updateTaskProgress(
        _activeTaskId,
        taskState.getTask(_activeTaskId)?.progress ?? 0,
        status: TaskStatus.failed,
        stage: 'Task execution failed: $e',
      );
    }
  }

  Future<String?> _validateUploadInputs({
    required List<XFile> images,
    required List<String> videos,
  }) async {
    if (images.isEmpty && videos.isEmpty) {
      return 'No images or video selected';
    }
    if (images.length >= 6) return null;
    if (videos.isEmpty) {
      return 'Need at least 6 images, or one video with more than 6 frames';
    }
    for (final videoPath in videos) {
      if (!File(videoPath).existsSync()) {
        return 'Video file does not exist';
      }
      final frameCount = await VideoMetadata.frameCount(videoPath);
      if (frameCount == null) {
        return 'Unable to read video frame count';
      }
      if (frameCount <= 6) {
        return 'Video is too short: $frameCount frames';
      }
    }
    return null;
  }

  void _startPolling(String taskId) {
    _statusTimer?.cancel();
    unawaited(_pollStatus(taskId));
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      unawaited(_pollStatus(taskId));
    });
  }

  Future<void> _pollStatus(String taskId) async {
    if (!mounted) return;
    final taskState = context.read<TaskState>();
    final task = taskState.getTask(taskId);
    if (task == null || !_shouldPoll(task)) {
      _statusTimer?.cancel();
      return;
    }

    final statusData = await _reconstructionService.checkStatus(taskId);
    if (statusData == null) return;

    _logTaskStatus('task_detail_poll', statusData);

    final taskStatus = _mapServerStatus(statusData.status);
    final serverProgress = _normalizeProgress(statusData.progress);
    final meshPending = _isMeshPending(statusData) || _hasLocalMeshPending(task);
    final staleCompletedWhileMeshPending =
        taskStatus == TaskStatus.completed && meshPending;
    final progress = staleCompletedWhileMeshPending
        ? (taskState.getTask(taskId)?.progress ?? 0.0)
        : (serverProgress ?? (taskState.getTask(taskId)?.progress ?? 0.0));
    final effectiveStatus =
        taskStatus == TaskStatus.completed && meshPending
            ? TaskStatus.processing
            : taskStatus;

    _syncRemoteTask(statusData);
    taskState.updateTaskProgress(
      taskId,
      progress,
      status: effectiveStatus,
      stage: statusData.currentStage ?? context.tr('task.stage.processing'),
    );

    if (taskStatus == TaskStatus.completed && !meshPending) {
      _statusTimer?.cancel();
      await _downloadResult(taskId, statusData);
    } else if (taskStatus == TaskStatus.failed) {
      _logTaskStatus('task_detail_failed', statusData);
      _statusTimer?.cancel();
    }
  }

  Future<void> _refreshTask() async {
    final task = context.read<TaskState>().getTask(_activeTaskId);
    if (task == null) {
      await _loadRemoteTask(_activeTaskId);
      return;
    }
    if (task.taskId.startsWith('local_')) return;
    await _pollStatus(task.taskId);
  }

  Future<void> _loadRemoteTask(String taskId) async {
    setState(() => _loadingRemoteTask = true);
    try {
      final statusData = await _reconstructionService.checkStatus(taskId);
      if (!mounted || statusData == null) return;
      _syncRemoteTask(statusData);
      final taskStatus = _mapServerStatus(statusData.status);
      final localTask = context.read<TaskState>().getTask(taskId);
      if ((taskStatus != TaskStatus.completed ||
              _isMeshPending(statusData) ||
              _hasLocalMeshPending(localTask)) &&
          taskStatus != TaskStatus.failed) {
        _startPolling(taskId);
      }
    } finally {
      if (mounted) setState(() => _loadingRemoteTask = false);
    }
  }

  void _syncRemoteTask(ReconstructionStatusResponse statusData) {
    final taskState = context.read<TaskState>();
    final taskStatus = _mapServerStatus(statusData.status);
    final gaussianResultFile = _selectGaussianResultFile(statusData);
    final meshResultFile = _selectMeshResultFile(statusData);
    final resultFileId = gaussianResultFile?.fileId ?? statusData.plyId;
    final meshResultFileId = meshResultFile?.fileId;
    final existing = taskState.getTask(statusData.taskId);
    final resultPly = resultFileId == null || resultFileId.isEmpty
        ? existing?.resultPly
        : (existing?.resultPly?.fileId == resultFileId
              ? existing?.resultPly
              : StorageFile(
                  fileId: resultFileId,
                  localPath: null,
                  status: FileSyncStatus.cloudOnly,
                  md5: '',
                  size: 0,
                ));
    final resultMesh = meshResultFileId == null || meshResultFileId.isEmpty
        ? existing?.resultMesh
        : (existing?.resultMesh?.fileId == meshResultFileId
              ? existing?.resultMesh
              : StorageFile(
                  fileId: meshResultFileId,
                  localPath: null,
                  status: FileSyncStatus.cloudOnly,
                  md5: '',
                  size: 0,
                ));
    final title = statusData.title.isNotEmpty
        ? statusData.title
        : existing?.title ?? statusData.taskId;
    final params = {
      ...?existing?.params,
      ...statusData.params,
      if (statusData.algorithm != null) 'algorithm': statusData.algorithm,
      if (statusData.inputFileIds.isNotEmpty)
        'input_file_ids': statusData.inputFileIds,
      if (statusData.inputKind.isNotEmpty) 'input_kind': statusData.inputKind,
      if (statusData.hasVisibility)
        'visibility': statusData.visibility
      else if (existing != null)
        'visibility': existing.visibility,
      if (statusData.gaussianAlgorithm != null)
        'gaussian_algorithm': statusData.gaussianAlgorithm,
      if (statusData.gaussianParams.isNotEmpty)
        'gaussian_params': statusData.gaussianParams,
      if (statusData.meshAlgorithm != null)
        'mesh_algorithm': statusData.meshAlgorithm,
      if (statusData.meshParams.isNotEmpty) 'mesh_params': statusData.meshParams,
    };

    final syncedFiles =
        existing != null && existing.files.isNotEmpty
            ? existing.files
            : statusData.inputFileIds
                  .map(
                    (fileId) => StorageFile(
                      fileId: fileId,
                      localPath: null,
                      status: FileSyncStatus.cloudOnly,
                      md5: '',
                      size: 0,
                    ),
                  )
                  .toList();

    taskState.upsertTask(
      ProcessingTask(
        taskId: statusData.taskId,
        title: title,
        params: params,
        files: syncedFiles,
        status: taskStatus,
        visibility: statusData.hasVisibility
            ? statusData.visibility
            : existing?.visibility ?? 'private',
        progress: _normalizeProgress(statusData.progress) ??
            existing?.progress ??
            (taskStatus == TaskStatus.completed ? 1 : 0),
        stage: statusData.currentStage ?? existing?.stage,
        createdAt: statusData.createdAt ?? existing?.createdAt ?? DateTime.now(),
        updatedAt: statusData.updatedAt ?? DateTime.now(),
        resultPly: resultPly,
        resultMesh: resultMesh,
      ),
    );
  }

  bool _isMeshPending(ReconstructionStatusResponse statusData) {
    final stage = (statusData.currentStage ?? '').toLowerCase();
    final status = statusData.status.toLowerCase();
    return statusData.meshAlgorithm != null &&
        _selectMeshResultFile(statusData) == null &&
        (status == 'pending' ||
            status == 'queued' ||
            status == 'processing' ||
            stage.contains('mesh'));
  }

  bool _hasLocalMeshPending(ProcessingTask? task) {
    if (task == null) return false;
    return (task.params['mesh_pending_algorithm'] ?? '').toString().isNotEmpty &&
        task.resultMesh == null;
  }

  ReconstructionResultFile? _selectGaussianResultFile(
    ReconstructionStatusResponse statusData,
  ) {
    final plyId = statusData.plyId;
    if (plyId != null && plyId.isNotEmpty) {
      return _resultFileById(statusData.resultFiles, plyId) ??
          ReconstructionResultFile(
            fileId: plyId,
            category: 'ply_model',
            fileType: 'model',
            mimeType: '',
            filename: '',
          );
    }
    for (final file in statusData.resultFiles) {
      if (_isMeshResultFile(file)) continue;
      if (_isGaussianResultFile(file)) return file;
    }
    final resultFileId = statusData.resultFileId;
    if (resultFileId == null || resultFileId.isEmpty) return null;
    final file = _resultFileById(statusData.resultFiles, resultFileId);
    if (file != null && _isMeshResultFile(file)) return null;
    return file ??
        ReconstructionResultFile(
          fileId: resultFileId,
          category: 'ply_model',
          fileType: 'model',
          mimeType: '',
          filename: '',
        );
  }

  ReconstructionResultFile? _selectMeshResultFile(
    ReconstructionStatusResponse statusData,
  ) {
    for (final file in statusData.resultFiles) {
      if (_isMeshResultFile(file)) return file;
    }
    final resultFileId = statusData.resultFileId;
    if (resultFileId == null || resultFileId.isEmpty) return null;
    final file = _resultFileById(statusData.resultFiles, resultFileId);
    if (file != null) return _isMeshResultFile(file) ? file : null;
    final stage = (statusData.currentStage ?? '').toLowerCase();
    if (statusData.meshAlgorithm != null &&
        statusData.status.toLowerCase() == 'completed' &&
        stage.contains('mesh')) {
      return ReconstructionResultFile(
        fileId: resultFileId,
        category: 'mesh_model',
        fileType: 'model',
        mimeType: '',
        filename: '',
      );
    }
    return null;
  }

  ReconstructionResultFile? _resultFileById(
    List<ReconstructionResultFile> files,
    String fileId,
  ) {
    for (final file in files) {
      if (file.fileId == fileId) return file;
    }
    return null;
  }

  bool _isGaussianResultFile(ReconstructionResultFile file) {
    final category = file.category.toLowerCase();
    final filename = file.filename.toLowerCase();
    return category.contains('ply') ||
        category.contains('splat') ||
        filename.endsWith('.ply') ||
        filename.endsWith('.splat');
  }

  bool _isMeshResultFile(ReconstructionResultFile file) {
    final category = file.category.toLowerCase();
    final filename = file.filename.toLowerCase();
    return category.contains('mesh') ||
        category.contains('glb') ||
        filename.endsWith('.obj') ||
        filename.endsWith('.glb') ||
        filename.endsWith('.fbx') ||
        filename.endsWith('.stl');
  }

  Future<void> _downloadResult(
    String taskId,
    ReconstructionStatusResponse statusData,
  ) async {
    final taskState = context.read<TaskState>();
    final meshResult = _selectMeshResultFile(statusData);
    final gaussianResult = _selectGaussianResultFile(statusData);
    final isMeshDownload = meshResult != null;
    final selectedResult = meshResult ?? gaussianResult;
    final resultFileId = selectedResult?.fileId;
    if (resultFileId == null || resultFileId.isEmpty) {
      _logTaskStatus('task_detail_completed_without_result_file', statusData);
      taskState.updateTaskProgress(
        taskId,
        1,
        status: TaskStatus.completed,
        stage: context.tr('task.stage.completedNoFileId'),
      );
      return;
    }

    taskState.updateTaskProgress(
      taskId,
      (taskState.getTask(taskId)?.progress ?? 0.95).clamp(0.0, 0.98),
      status: TaskStatus.processing,
      stage: context.tr('task.stage.downloading'),
    );
    final result = await _reconstructionService.downloadResultFile(
      resultFileId: resultFileId,
      taskId: taskId,
      onProgress: (downloadProgress) {
        taskState.updateTaskProgress(
          taskId,
          (0.98 + downloadProgress * 0.02).clamp(0.98, 1.0),
          status: TaskStatus.processing,
          stage: context.tr('task.stage.downloading'),
        );
      },
    );

    if (result == null) {
      _logTaskStatus('task_detail_download_failed_after_completed', statusData);
      taskState.updateTaskProgress(
        taskId,
        1,
        status: TaskStatus.completed,
        stage: context.tr('task.stage.downloadFailed'),
      );
      return;
    }

    final task = taskState.getTask(taskId);
    if (task != null) {
      final downloadedResult = StorageFile(
        fileId: resultFileId,
        localPath: result.path,
        status: FileSyncStatus.synced,
        md5: '',
        size: await result.length(),
      );
      taskState.upsertTask(
        task.copyWith(
          status: TaskStatus.completed,
          progress: 1,
          stage: context.tr('task.stage.completed'),
          resultPly: isMeshDownload ? task.resultPly : downloadedResult,
          resultMesh: isMeshDownload ? downloadedResult : task.resultMesh,
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  void _logTaskStatus(String tag, ReconstructionStatusResponse statusData) {
    final resultFiles = statusData.resultFiles
        .map(
          (file) =>
              '${file.fileId}:${file.filename}:${file.fileType}:${file.category}',
        )
        .toList();
    debugPrint(
      '[API] result $tag taskId=${statusData.taskId} '
      'status=${statusData.status} progress=${statusData.progress} '
      'stage=${statusData.currentStage} resultFileId=${statusData.resultFileId} '
      'errorCode=${statusData.errorCode} error=${statusData.error} '
      'resultFiles=$resultFiles',
    );
  }

  Future<void> _downloadInputFiles(ProcessingTask task) async {
    if (_downloadingInputFiles) return;
    setState(() => _downloadingInputFiles = true);
    final taskState = context.read<TaskState>();
    try {
      debugPrint('[TaskDetail] trigger download input files taskId=${task.taskId}');
      var files = List<StorageFile>.from(task.files);
      if (files.isEmpty) {
        final detail = await _reconstructionService.getTaskDetail(task.taskId);
        final inputFileIds = detail?.inputFileIds ?? const <String>[];
        debugPrint(
          '[TaskDetail] result task detail inputFileIds=${inputFileIds.length}',
        );
        files = inputFileIds
            .map(
              (fileId) => StorageFile(
                fileId: fileId,
                localPath: null,
                status: FileSyncStatus.cloudOnly,
                md5: '',
                size: 0,
              ),
            )
            .toList();
        if (files.isEmpty) {
          debugPrint(
            '[TaskDetail] result download input files skipped reason=no_image_ids',
          );
          return;
        }
      }

      final updatedFiles = <StorageFile>[];
      for (final file in files) {
        if (file.fileId.trim().isEmpty) continue;
        final existingPath = file.localPath;
        if (existingPath != null &&
            existingPath.isNotEmpty &&
            File(existingPath).existsSync()) {
          updatedFiles.add(file);
          continue;
        }
        try {
          debugPrint(
            '[TaskDetail] trigger download input file taskId=${task.taskId} '
            'fileId=${file.fileId}',
          );
          final downloaded = await _reconstructionService.downloadFile(
            fileId: file.fileId,
            outputDirectoryName: 'media',
          );
          if (downloaded == null) {
            updatedFiles.add(file);
            debugPrint(
              '[TaskDetail] result download input file failed fileId=${file.fileId}',
            );
            continue;
          }
          updatedFiles.add(
            file.copyWith(
              localPath: downloaded.path,
              status: FileSyncStatus.synced,
              size: await downloaded.length(),
            ),
          );
          debugPrint(
            '[TaskDetail] result download input file success fileId=${file.fileId} '
            'path=${downloaded.path}',
          );
        } catch (e) {
          updatedFiles.add(file);
          debugPrint(
            '[TaskDetail] result download input file failed fileId=${file.fileId} '
            'error=$e',
          );
        }
      }

      final latest = taskState.getTask(task.taskId) ?? task;
      taskState.upsertTask(
        latest.copyWith(files: updatedFiles, updatedAt: DateTime.now()),
      );
      debugPrint(
        '[TaskDetail] result download input files done taskId=${task.taskId} '
        'count=${updatedFiles.length}',
      );
    } finally {
      if (mounted) setState(() => _downloadingInputFiles = false);
    }
  }

  Future<void> _setTaskVisibility(ProcessingTask task, bool isPublic) async {
    if (_updatingVisibility || task.taskId.startsWith('local_')) return;
    final visibility = isPublic ? 'public' : 'private';
    debugPrint(
      '[TaskDetail] trigger visibility update taskId=${task.taskId} '
      'from=${task.visibility} to=$visibility',
    );
    setState(() => _updatingVisibility = true);
    final taskState = context.read<TaskState>();
    taskState.upsertTask(
      task.copyWith(
        visibility: visibility,
        params: {...task.params, 'visibility': visibility},
        updatedAt: DateTime.now(),
      ),
    );
    try {
      final result = await _reconstructionService.setTaskVisibility(
        taskId: task.taskId,
        visibility: visibility,
      );
      if (!mounted) return;
      if (result == null) {
        debugPrint(
          '[TaskDetail] result visibility update failed keep_local=$visibility '
          'taskId=${task.taskId}',
        );
        return;
      }
      if (result.hasVisibility && result.visibility != visibility) {
        debugPrint(
          '[TaskDetail] result visibility mismatch requested=$visibility '
          'server=${result.visibility} taskId=${task.taskId}',
        );
      }
      final appliedVisibility = visibility;
      taskState.upsertTask(
        (taskState.getTask(task.taskId) ?? task).copyWith(
          visibility: appliedVisibility,
          params: {
            ...(taskState.getTask(task.taskId) ?? task).params,
            'visibility': appliedVisibility,
          },
          updatedAt: DateTime.now(),
        ),
      );
    } finally {
      if (mounted) setState(() => _updatingVisibility = false);
    }
  }

  Future<void> _startMeshTask(
    ProcessingTask sourceTask, {
    Map<String, dynamic>? params,
  }) async {
    if (_startingMesh) return;
    final taskState = context.read<TaskState>();
    final taskId = sourceTask.taskId;
    final requestedMeshAlgorithm =
        params?['algorithm']?.toString() ?? 'dash_gaussian_mesh';
    final meshAlgorithm = await _resolveAvailableMeshAlgorithm(
      requestedMeshAlgorithm,
    );
    final inputFileIds = await _meshInputFileIdsForAlgorithm(
      sourceTask,
      meshAlgorithm,
    );
    if (inputFileIds.isEmpty) {
      debugPrint(
        '[TaskDetail] result mesh_start skipped taskId=$taskId '
        'algorithm=$meshAlgorithm reason=no_original_input_files',
      );
      taskState.upsertTask(
        sourceTask.copyWith(
          status: sourceTask.status,
          progress: sourceTask.progress,
          stage: context.tr('task.mesh.startFailed'),
          updatedAt: DateTime.now(),
        ),
      );
      return;
    }

    final meshParams = _usesOriginalInputsForMesh(meshAlgorithm)
        ? <String, dynamic>{}
        : (Map<String, dynamic>.from(params ?? _defaultMeshParams())
            ..remove('algorithm'));
    final resultFileId = sourceTask.resultPly?.fileId.trim() ?? '';
    final pendingParams = {
      ...sourceTask.params,
      'mesh_pending_algorithm': meshAlgorithm,
      'mesh_pending_params': meshParams,
      'mesh_input_file_ids': inputFileIds,
      if (resultFileId.isNotEmpty) 'source_result_file_id': resultFileId,
    };

    setState(() => _startingMesh = true);
    taskState.upsertTask(
      sourceTask.copyWith(
        params: pendingParams,
        status: TaskStatus.processing,
        progress: 0,
        stage: context.tr('task.mesh.creating'),
        updatedAt: DateTime.now(),
      ),
    );

    try {
      debugPrint(
        '[TaskDetail] trigger mesh_start taskId=$taskId '
        'algorithm=$meshAlgorithm inputFileIds=$inputFileIds params=$meshParams',
      );
      final started = await _reconstructionService.startMeshReconstruction(
        taskId: taskId,
        inputFileIds: inputFileIds,
        algorithm: meshAlgorithm,
        params: meshParams,
      );

      if (!mounted) return;
      if (started == null || started.taskId.isEmpty) {
        taskState.upsertTask(
          sourceTask.copyWith(
            status: sourceTask.status,
            progress: sourceTask.progress,
            stage: context.tr('task.mesh.startFailed'),
            updatedAt: DateTime.now(),
          ),
        );
        return;
      }

      taskState.upsertTask(
        (taskState.getTask(taskId) ?? sourceTask).copyWith(
          params: {
            ...(taskState.getTask(taskId) ?? sourceTask).params,
            'mesh_algorithm': meshAlgorithm,
            'mesh_params': meshParams,
          },
          status: TaskStatus.processing,
          progress: 0,
          stage: context.tr('task.mesh.processing'),
          updatedAt: DateTime.now(),
        ),
      );
      setState(() => _activeTaskId = taskId);
      _startPolling(taskId);
    } catch (e) {
      debugPrint('[API] result mesh_start failed error=$e');
      taskState.upsertTask(
        sourceTask.copyWith(
          status: sourceTask.status,
          progress: sourceTask.progress,
          stage: context.tr('task.mesh.startFailed'),
          updatedAt: DateTime.now(),
        ),
      );
    } finally {
      if (mounted) setState(() => _startingMesh = false);
    }
  }

  Map<String, dynamic> _defaultMeshParams() {
    return {
      'radius': 10,
      'cluster_voxel_size': 0.05,
      'keep_largest': true,
      'iteration': 30000,
      'views': 'train',
      'voxel_size': 0.02,
      'sdf_trunc': 0.36,
      'alpha_threshold': 0.35,
      'max_depth': 25,
      'depth_quantile': 0.9,
      'mask_erode': 2,
    };
  }

  bool _usesOriginalInputsForMesh(String algorithm) {
    final normalized = algorithm.toLowerCase().replaceAll('-', '_');
    return normalized.contains('hunyuan');
  }

  Future<List<String>> _meshInputFileIdsForAlgorithm(
    ProcessingTask task,
    String algorithm,
  ) async {
    if (!_usesOriginalInputsForMesh(algorithm)) {
      final resultFileId = task.resultPly?.fileId.trim() ?? '';
      if (resultFileId.isEmpty) {
        debugPrint(
          '[TaskDetail] result mesh_start input skipped taskId=${task.taskId} '
          'algorithm=$algorithm reason=no_ply_result',
        );
        return const [];
      }
      return [resultFileId];
    }

    final localIds = _readStringListFromAny(
      task.params['input_file_ids'] ??
          task.params['image_ids'] ??
          task.params['file_ids'] ??
          task.params['input_ids'],
    );
    if (localIds.isNotEmpty) return localIds;

    final fileIds = task.files
        .map((file) => file.fileId.trim())
        .where((fileId) => fileId.isNotEmpty)
        .toList();
    if (fileIds.isNotEmpty) return fileIds;

    final detail = await _reconstructionService.getTaskDetail(task.taskId);
    final remoteIds = detail?.inputFileIds ?? const <String>[];
    debugPrint(
      '[TaskDetail] result mesh_start input detail taskId=${task.taskId} '
      'algorithm=$algorithm inputFileIds=${remoteIds.length}',
    );
    return remoteIds;
  }

  List<String> _readStringListFromAny(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty && item != 'null')
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageState>();
    return Consumer<TaskState>(
      builder: (context, taskState, child) {
        final task =
            taskState.getTask(_activeTaskId) ??
            taskState.getTask(widget.taskId);

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text(
              context.tr('task.detail.title'),
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () => context.go(homeTabPath),
            ),
          ),
          body: SafeArea(
            child: task == null
                ? Center(
                    child: _loadingRemoteTask
                        ? const CircularProgressIndicator(
                            color: Color(0xFF00C6FF),
                          )
                        : Text(
                            context.tr('task.detail.notFound'),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                  )
                : RefreshIndicator(
                    onRefresh: _refreshTask,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      children: [
                        _Header(
                          task: task,
                          status: _statusText(context, task.status),
                        ),
                        const SizedBox(height: 24),
                        _InfoSection(task: task),
                        const SizedBox(height: 24),
                        _VisibilitySection(
                          task: task,
                          updating: _updatingVisibility,
                          onChanged: (isPublic) =>
                              _setTaskVisibility(task, isPublic),
                        ),
                        const SizedBox(height: 24),
                        _ResultSection(
                          task: task,
                          startingMesh: _startingMesh,
                          defaultMeshParams: _defaultMeshParams(),
                          onStartMesh: (params) =>
                              _startMeshTask(task, params: params),
                        ),
                        const SizedBox(height: 24),
                        _FilesSection(
                          files: task.files,
                          downloading: _downloadingInputFiles,
                          onDownloadInputs: () => _downloadInputFiles(task),
                        ),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }

  Future<String> _resolveAvailableAlgorithm(String requestedAlgorithm) async {
    final algorithms = await _reconstructionService.listAlgorithms();
    final availableAlgorithms =
        algorithms?.algorithms
            .where(
              (algorithm) => algorithm.available && algorithm.name.isNotEmpty,
            )
            .map((algorithm) => algorithm.name)
            .toSet() ??
        const <String>{};
    if (availableAlgorithms.isEmpty ||
        availableAlgorithms.contains(requestedAlgorithm)) {
      return requestedAlgorithm;
    }
    final defaultAlgorithm = algorithms?.defaultAlgorithm;
    if (defaultAlgorithm != null &&
        availableAlgorithms.contains(defaultAlgorithm)) {
      return defaultAlgorithm;
    }
    return availableAlgorithms.first;
  }

  Future<String> _resolveAvailableMeshAlgorithm(String requestedAlgorithm) async {
    final algorithms = await _reconstructionService.listMeshAlgorithms();
    final availableAlgorithms =
        algorithms?.algorithms
            .where(
              (algorithm) => algorithm.available && algorithm.name.isNotEmpty,
            )
            .map((algorithm) => algorithm.name)
            .toSet() ??
        const <String>{};
    if (availableAlgorithms.isEmpty ||
        availableAlgorithms.contains(requestedAlgorithm)) {
      return requestedAlgorithm;
    }
    final defaultAlgorithm = algorithms?.defaultAlgorithm;
    if (defaultAlgorithm != null &&
        availableAlgorithms.contains(defaultAlgorithm)) {
      return defaultAlgorithm;
    }
    return availableAlgorithms.first;
  }

  String _normalizeAlgorithm(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'anysplat':
        return 'anysplat';
      case 'dash_gaussian':
      case 'dash gaussian':
      case 'dash-gaussian':
        return 'dash_gaussian';
      case 'hunyuan3d':
      case 'hunyuan 3d':
      case 'hunyuan-3d':
        return 'hunyuan3d';
      case 'segment_then_splat':
      case 'segment then splat':
      case 'segment-then-splat':
        return 'segment_then_splat';
      case 'vggt_omega':
      case 'vggt omega':
      case 'vggt-omega':
        return 'vggt_omega';
      default:
        return 'anysplat';
    }
  }

  TaskStatus _mapServerStatus(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'partial_completed':
        return TaskStatus.completed;
      case 'failed':
      case 'cancelled':
        return TaskStatus.failed;
      case 'processing':
      case 'manual_review':
        return TaskStatus.processing;
      case 'pending':
      case 'queued':
      default:
        return TaskStatus.pending;
    }
  }

  double? _normalizeProgress(Object? value) {
    if (value is! num) return null;
    final progress = value.toDouble();
    if (progress > 1) return progress / 100;
    return progress;
  }

  bool _shouldPoll(ProcessingTask task) {
    final meshPending =
        (task.params['mesh_pending_algorithm'] ?? '').toString().isNotEmpty &&
            task.resultMesh == null;
    if ((task.status == TaskStatus.completed && !meshPending) ||
        task.status == TaskStatus.failed) {
      return false;
    }
    return !task.taskId.startsWith('local_');
  }

  String _statusText(BuildContext context, TaskStatus status) {
    switch (status) {
      case TaskStatus.draft:
        return context.tr('task.status.draft');
      case TaskStatus.uploadingFiles:
        return context.tr('task.status.uploading');
      case TaskStatus.pending:
        return context.tr('home.status.pending');
      case TaskStatus.processing:
        return context.tr('home.status.processing');
      case TaskStatus.completed:
        return context.tr('home.status.completed');
      case TaskStatus.failed:
        return context.tr('home.status.failed');
    }
  }
}

class _UploadItem {
  final String path;
  final bool isVideo;
  final String label;

  const _UploadItem({
    required this.path,
    required this.isVideo,
    required this.label,
  });

  factory _UploadItem.image(XFile image) {
    return _UploadItem(path: image.path, isVideo: false, label: 'image');
  }

  factory _UploadItem.video(String path) {
    return _UploadItem(path: path, isVideo: true, label: 'video');
  }

  StorageFile toStorageFile() {
    final file = File(path);
    return StorageFile(
      fileId: path.split(Platform.pathSeparator).last,
      localPath: path,
      status: FileSyncStatus.localOnly,
      md5: '',
      size: file.existsSync() ? file.lengthSync() : 0,
    );
  }
}

class _Header extends StatelessWidget {
  final ProcessingTask task;
  final String status;

  const _Header({required this.task, required this.status});

  @override
  Widget build(BuildContext context) {
    final progress = task.progress.clamp(0, 1).toDouble();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                _statusIcon(task.status),
                color: _statusColor(task.status),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                status,
                style: TextStyle(
                  color: _statusColor(task.status),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (task.status != TaskStatus.completed) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.white10,
              color: const Color(0xFF00C6FF),
            ),
            const SizedBox(height: 8),
            Text(
              '${((progress) * 100).round()}%  ${task.stage ?? ''}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final ProcessingTask task;

  const _InfoSection({required this.task});

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: context.tr('task.info.title'),
      children: [
        _InfoRow(label: context.tr('task.info.id'), value: task.taskId),
        _InfoRow(
          label: context.tr('task.info.createdAt'),
          value: _formatDateTime(task.createdAt),
        ),
        if (task.updatedAt != null)
          _InfoRow(
            label: context.tr('task.info.updatedAt'),
            value: _formatDateTime(task.updatedAt!),
          ),
        _InfoRow(label: context.tr('task.info.assetCount'), value: '${task.files.length}'),
      ],
    );
  }
}

class _VisibilitySection extends StatelessWidget {
  final ProcessingTask task;
  final bool updating;
  final ValueChanged<bool> onChanged;

  const _VisibilitySection({
    required this.task,
    required this.updating,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isPublic = task.visibility == 'public';
    return _Section(
      title: context.tr('task.visibility.title'),
      children: [
        Row(
          children: [
            Icon(
              isPublic ? Icons.public : Icons.lock_outline,
              color: const Color(0xFF00C6FF),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr(
                      isPublic
                          ? 'task.visibility.public'
                          : 'task.visibility.private',
                    ),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    context.tr(
                      isPublic
                          ? 'task.visibility.publicHint'
                          : 'task.visibility.privateHint',
                    ),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (updating)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Switch(
                value: isPublic,
                activeColor: const Color(0xFF00C6FF),
                onChanged: task.taskId.startsWith('local_') ? null : onChanged,
              ),
          ],
        ),
      ],
    );
  }
}

class _ResultSection extends StatefulWidget {
  final ProcessingTask task;
  final bool startingMesh;
  final Map<String, dynamic> defaultMeshParams;
  final ValueChanged<Map<String, dynamic>> onStartMesh;

  const _ResultSection({
    required this.task,
    required this.startingMesh,
    required this.defaultMeshParams,
    required this.onStartMesh,
  });

  @override
  State<_ResultSection> createState() => _ResultSectionState();
}

class _ResultSectionState extends State<_ResultSection> {
  final ReconstructionService _service = ReconstructionService();
  String? _localPath;
  int? _fileSize;
  String? _meshLocalPath;
  int? _meshFileSize;
  bool _downloading = false;
  bool _downloadingMesh = false;
  bool _showMeshParams = false;
  bool _loadingMeshAlgorithms = false;
  String _selectedMeshAlgorithm = 'dash_gaussian_mesh';
  List<ReconstructionAlgorithm> _meshAlgorithms = const [];
  late final Map<String, TextEditingController> _meshParamControllers;
  late bool _keepLargest;

  ProcessingTask get task => widget.task;

  @override
  void initState() {
    super.initState();
    _meshParamControllers = {
      for (final entry in widget.defaultMeshParams.entries)
        if (entry.value is! bool)
          entry.key: TextEditingController(text: entry.value.toString()),
    };
    _keepLargest = widget.defaultMeshParams['keep_largest'] == true;
    _syncFromTask();
    unawaited(_loadMeshAlgorithms());
  }

  @override
  void dispose() {
    for (final controller in _meshParamControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ResultSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.resultPly?.localPath !=
            widget.task.resultPly?.localPath ||
        oldWidget.task.resultPly?.size != widget.task.resultPly?.size) {
      _syncFromTask();
    }
    if (oldWidget.task.resultMesh?.localPath !=
            widget.task.resultMesh?.localPath ||
        oldWidget.task.resultMesh?.size != widget.task.resultMesh?.size) {
      _syncFromTask();
    }
  }

  void _syncFromTask() {
    _localPath = task.resultPly?.localPath;
    _fileSize = task.resultPly?.size;
    final path = _localPath;
    if (path != null && File(path).existsSync()) {
      _fileSize = File(path).lengthSync();
    }
    _meshLocalPath = task.resultMesh?.localPath;
    _meshFileSize = task.resultMesh?.size;
    final meshPath = _meshLocalPath;
    if (meshPath != null && File(meshPath).existsSync()) {
      _meshFileSize = File(meshPath).lengthSync();
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = task.resultPly;
    final meshResult = task.resultMesh;
    final canOpen =
        _localPath != null &&
        _localPath!.isNotEmpty &&
        File(_localPath!).existsSync();
    final canOpenMesh =
        _meshLocalPath != null &&
        _meshLocalPath!.isNotEmpty &&
        File(_meshLocalPath!).existsSync();
    final canDownload = result != null && result.fileId.isNotEmpty;
    final canDownloadMesh = meshResult != null && meshResult.fileId.isNotEmpty;
    final meshAlgorithm = (task.params['mesh_algorithm'] ?? '').toString();
    final pendingMeshAlgorithm =
        (task.params['mesh_pending_algorithm'] ?? '').toString();
    final meshInProgress =
        widget.startingMesh ||
        (pendingMeshAlgorithm.isNotEmpty && meshResult == null) ||
        (meshAlgorithm.isNotEmpty &&
            meshResult == null &&
            task.status != TaskStatus.completed);
    final canStartMesh =
        canDownload &&
        task.status == TaskStatus.completed &&
        meshAlgorithm.isEmpty &&
        pendingMeshAlgorithm.isEmpty &&
        !meshInProgress;

    return _Section(
      title: context.tr('task.result.title'),
      children: [
        _InfoRow(
          label: context.tr('task.result.file'),
          value: canOpen ? _localPath! : context.tr('task.result.noLocalFile'),
        ),
        _InfoRow(
          label: context.tr('task.result.fileSize'),
          value: canOpen ? _formatBytes(_fileSize ?? 0) : '--',
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: canOpen
                      ? () => context.push(
                          '$homeTabPath/$localViewerPath',
                          extra: _localPath,
                        )
                      : null,
                  icon: const Icon(Icons.view_in_ar),
                  label: Text(context.tr('task.result.openViewer')),
                  style: _buttonStyle(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              tooltip: context.tr('task.result.deleteLocal'),
              onPressed: canOpen ? _deleteLocalResult : null,
              icon: const Icon(Icons.delete_outline),
              color: Colors.white,
            ),
            IconButton(
              tooltip: context.tr('task.result.redownload'),
              onPressed: canDownload && !_downloading ? _downloadResult : null,
              icon: _downloading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              color: Colors.white,
            ),
          ],
        ),
        if (canStartMesh) ...[
          const SizedBox(height: 12),
          _buildMeshParamPanel(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: widget.startingMesh
                  ? null
                  : () => widget.onStartMesh(_readMeshParams()),
              icon: widget.startingMesh
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.polyline_outlined),
              label: Text(context.tr('task.mesh.start')),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF00C6FF),
                side: BorderSide(
                  color: const Color(0xFF00C6FF).withValues(alpha: 0.45),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
        if (meshInProgress) ...[
          const SizedBox(height: 12),
          _MeshStatusPanel(progress: task.progress, stage: task.stage),
        ],
        if (meshResult != null) ...[
          const SizedBox(height: 18),
          _InfoRow(
            label: context.tr('task.mesh.result'),
            value: canOpenMesh
                ? _meshLocalPath!
                : context.tr('task.result.noLocalFile'),
          ),
          _InfoRow(
            label: context.tr('task.result.fileSize'),
            value: canOpenMesh ? _formatBytes(_meshFileSize ?? 0) : '--',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: canOpenMesh
                        ? () => context.push(
                              '$homeTabPath/$localViewerPath',
                              extra: _meshLocalPath,
                            )
                        : null,
                    icon: const Icon(Icons.view_in_ar),
                    label: Text(context.tr('task.mesh.open')),
                    style: _buttonStyle(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: context.tr('task.mesh.download'),
                onPressed: canDownloadMesh && !_downloadingMesh
                    ? _downloadMeshResult
                    : null,
                icon: _downloadingMesh
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download),
                color: Colors.white,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildMeshParamPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _showMeshParams = !_showMeshParams),
            child: Row(
              children: [
                const Icon(Icons.tune, color: Color(0xFF00C6FF), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('task.mesh.adjustParams'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  _showMeshParams
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: Colors.white70,
                ),
              ],
            ),
          ),
          if (_showMeshParams) ...[
            const SizedBox(height: 12),
            _buildMeshAlgorithmSelector(),
            const SizedBox(height: 12),
            ..._meshParamControllers.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('param.${entry.key}.label'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            context.tr('param.${entry.key}.desc'),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 104,
                      child: TextField(
                        controller: entry.value,
                        keyboardType: _keyboardTypeForMeshParam(entry.key),
                        textAlign: TextAlign.end,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          isDense: true,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color(0xFF00C6FF),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _keepLargest,
              onChanged: (value) => setState(() => _keepLargest = value),
              title: Text(
                context.tr('param.keep_largest.label'),
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                context.tr('param.keep_largest.desc'),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              activeColor: const Color(0xFF00C6FF),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMeshAlgorithmSelector() {
    final availableAlgorithms = _meshAlgorithms
        .where((algorithm) => algorithm.available && algorithm.name.isNotEmpty)
        .toList();
    if (_loadingMeshAlgorithms && availableAlgorithms.isEmpty) {
      return const SizedBox(
        height: 40,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (availableAlgorithms.isEmpty) {
      return const SizedBox.shrink();
    }
    return DropdownButtonFormField<String>(
      value: availableAlgorithms.any(
        (algorithm) => algorithm.name == _selectedMeshAlgorithm,
      )
          ? _selectedMeshAlgorithm
          : availableAlgorithms.first.name,
      dropdownColor: const Color(0xFF0B1026),
      decoration: InputDecoration(
        labelText: context.tr('task.mesh.algorithm'),
        labelStyle: const TextStyle(color: Colors.white70),
        isDense: true,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF00C6FF)),
        ),
      ),
      items: availableAlgorithms
          .map(
            (algorithm) => DropdownMenuItem<String>(
              value: algorithm.name,
              child: Text(
                algorithm.displayName.isEmpty
                    ? algorithm.name
                    : algorithm.displayName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value == null) return;
        setState(() => _selectedMeshAlgorithm = value);
      },
    );
  }

  Map<String, dynamic> _readMeshParams() {
    final params = <String, dynamic>{'keep_largest': _keepLargest};
    for (final entry in _meshParamControllers.entries) {
      final raw = entry.value.text.trim();
      final defaultValue = widget.defaultMeshParams[entry.key];
      if (defaultValue is int) {
        params[entry.key] = int.tryParse(raw) ?? defaultValue;
      } else if (defaultValue is double) {
        params[entry.key] = double.tryParse(raw) ?? defaultValue;
      } else {
        params[entry.key] = raw.isEmpty ? defaultValue : raw;
      }
    }
    params['algorithm'] = _selectedMeshAlgorithm;
    return params;
  }

  TextInputType _keyboardTypeForMeshParam(String key) {
    final defaultValue = widget.defaultMeshParams[key];
    if (defaultValue is num) {
      return const TextInputType.numberWithOptions(decimal: true);
    }
    return TextInputType.text;
  }

  Future<void> _loadMeshAlgorithms() async {
    setState(() => _loadingMeshAlgorithms = true);
    debugPrint('[TaskDetail] trigger load mesh algorithms');
    final algorithms = await _service.listMeshAlgorithms();
    if (!mounted) return;
    final available = algorithms?.algorithms
            .where((algorithm) => algorithm.available && algorithm.name.isNotEmpty)
            .toList() ??
        const <ReconstructionAlgorithm>[];
    setState(() {
      _meshAlgorithms = available;
      final defaultAlgorithm = algorithms?.defaultAlgorithm;
      if (defaultAlgorithm != null &&
          available.any((algorithm) => algorithm.name == defaultAlgorithm)) {
        _selectedMeshAlgorithm = defaultAlgorithm;
      } else if (available.isNotEmpty) {
        _selectedMeshAlgorithm = available.first.name;
      }
      _loadingMeshAlgorithms = false;
    });
    debugPrint(
      '[TaskDetail] result mesh algorithms count=${available.length} '
      'default=${algorithms?.defaultAlgorithm} '
      'selected=$_selectedMeshAlgorithm '
      'names=${available.map((algorithm) => algorithm.name).join(',')}',
    );
  }

  Future<void> _deleteLocalResult() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0B1026),
        title: Text(context.tr('task.result.deleteLocal')),
        content: Text(context.tr('task.result.deleteConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              context.tr('common.delete'),
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    final path = _localPath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
    if (!mounted) return;
    setState(() {
      _localPath = null;
      _fileSize = null;
    });
  }

  Future<void> _downloadResult() async {
    final result = task.resultPly;
    if (result == null) return;
    setState(() => _downloading = true);
    final file = await _service.downloadResultFile(
      resultFileId: result.fileId,
      taskId: task.taskId,
    );
    if (!mounted) return;
    if (file != null) {
      final fileSize = await file.length();
      if (!mounted) return;
      final updatedResult = result.copyWith(
        localPath: file.path,
        status: FileSyncStatus.synced,
        size: fileSize,
      );
      final taskState = context.read<TaskState>();
      taskState.upsertTask(
        task.copyWith(resultPly: updatedResult, updatedAt: DateTime.now()),
      );
      setState(() {
        _localPath = file.path;
        _fileSize = updatedResult.size;
        _downloading = false;
      });
      return;
    }
    setState(() => _downloading = false);
  }

  Future<void> _downloadMeshResult() async {
    final result = task.resultMesh;
    if (result == null) return;
    setState(() => _downloadingMesh = true);
    final file = await _service.downloadResultFile(
      resultFileId: result.fileId,
      taskId: task.taskId,
    );
    if (!mounted) return;
    if (file != null) {
      final fileSize = await file.length();
      if (!mounted) return;
      final updatedResult = result.copyWith(
        localPath: file.path,
        status: FileSyncStatus.synced,
        size: fileSize,
      );
      final taskState = context.read<TaskState>();
      taskState.upsertTask(
        task.copyWith(resultMesh: updatedResult, updatedAt: DateTime.now()),
      );
      setState(() {
        _meshLocalPath = file.path;
        _meshFileSize = updatedResult.size;
        _downloadingMesh = false;
      });
      return;
    }
    setState(() => _downloadingMesh = false);
  }
}

class _MeshStatusPanel extends StatelessWidget {
  final double progress;
  final String? stage;

  const _MeshStatusPanel({required this.progress, this.stage});

  @override
  Widget build(BuildContext context) {
    final value = progress.clamp(0, 1).toDouble();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF00C6FF).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF00C6FF).withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  stage ?? context.tr('task.mesh.processing'),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              Text(
                '${(value * 100).round()}%',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: value,
            minHeight: 5,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            color: const Color(0xFF00C6FF),
          ),
        ],
      ),
    );
  }
}

class _FilesSection extends StatelessWidget {
  final List<StorageFile> files;
  final bool downloading;
  final VoidCallback onDownloadInputs;

  const _FilesSection({
    required this.files,
    required this.downloading,
    required this.onDownloadInputs,
  });

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: context.tr('task.files.title'),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: downloading ? null : onDownloadInputs,
            icon: downloading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_for_offline_outlined),
            label: Text(
              downloading
                  ? context.tr('task.files.downloadingInputs')
                  : context.tr('task.files.downloadInputs'),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (files.isEmpty)
          Text(
            context.tr('task.files.empty'),
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          )
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: List.generate(
              files.length,
              (index) => _MediaTile(files: files, index: index),
            ),
          ),
      ],
    );
  }
}

class _MediaTile extends StatefulWidget {
  final List<StorageFile> files;
  final int index;

  const _MediaTile({required this.files, required this.index});

  StorageFile get file => files[index];

  @override
  State<_MediaTile> createState() => _MediaTileState();
}

class _MediaTileState extends State<_MediaTile> {
  String? _localPath;

  @override
  void initState() {
    super.initState();
    _localPath = widget.file.localPath;
  }

  bool get _hasLocalFile =>
      _localPath != null &&
      _localPath!.isNotEmpty &&
      File(_localPath!).existsSync();

  @override
  Widget build(BuildContext context) {
    final path = _localPath ?? '';
    final extension = path.split('.').last.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'webp'].contains(extension);
    final isVideo = ['mp4', 'mov', 'm4v'].contains(extension);

    return SizedBox(
      width: 96,
      child: GestureDetector(
        onTap: _hasLocalFile && isImage ? () => _previewImages(path) : null,
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            image: _hasLocalFile && isImage
                ? DecorationImage(
                    image: FileImage(File(path)),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: !_hasLocalFile || !isImage
              ? Center(
                  child: Icon(
                    isVideo
                        ? Icons.play_circle_outline
                        : Icons.insert_drive_file,
                    color: Colors.white54,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  void _previewImages(String currentPath) {
    final paths = <String>[];
    var initialIndex = 0;
    for (final file in widget.files) {
      final path = file == widget.file ? currentPath : file.localPath;
      if (path == null || path.isEmpty || !File(path).existsSync()) continue;
      final extension = path.split('.').last.toLowerCase();
      if (!['jpg', 'jpeg', 'png', 'webp'].contains(extension)) continue;
      if (path == currentPath) initialIndex = paths.length;
      paths.add(path);
    }
    if (paths.isEmpty) return;

    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: _ImagePreviewPager(paths: paths, initialIndex: initialIndex),
        );
      },
    );
  }
}

class _ImagePreviewPager extends StatefulWidget {
  final List<String> paths;
  final int initialIndex;

  const _ImagePreviewPager({required this.paths, required this.initialIndex});

  @override
  State<_ImagePreviewPager> createState() => _ImagePreviewPagerState();
}

class _ImagePreviewPagerState extends State<_ImagePreviewPager> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.paths.length,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              return InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Image.file(
                    File(widget.paths[index]),
                    fit: BoxFit.contain,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Text(
                '${_currentIndex + 1}/${widget.paths.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _panelDecoration() {
  return BoxDecoration(
    color: Colors.white.withValues(alpha: 0.06),
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
  );
}

IconData _statusIcon(TaskStatus status) {
  switch (status) {
    case TaskStatus.draft:
      return Icons.edit_note;
    case TaskStatus.uploadingFiles:
      return Icons.cloud_upload_outlined;
    case TaskStatus.pending:
      return Icons.schedule;
    case TaskStatus.processing:
      return Icons.memory;
    case TaskStatus.completed:
      return Icons.check_circle_outline;
    case TaskStatus.failed:
      return Icons.error_outline;
  }
}

Color _statusColor(TaskStatus status) {
  switch (status) {
    case TaskStatus.completed:
      return const Color(0xFF00FFC2);
    case TaskStatus.failed:
      return Colors.redAccent;
    case TaskStatus.uploadingFiles:
      return const Color(0xFF00C6FF);
    case TaskStatus.processing:
      return const Color(0xFFFFD166);
    case TaskStatus.pending:
    case TaskStatus.draft:
      return Colors.white70;
  }
}

String _formatDateTime(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(1)} GB';
}

ButtonStyle _buttonStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: const Color(0xFF00C6FF),
    foregroundColor: Colors.white,
    disabledBackgroundColor: Colors.white12,
    disabledForegroundColor: Colors.white38,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}
