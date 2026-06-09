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
import '../../core/widgets/background/sci_fi_background.dart';
import '../../core/widgets/buttons/gradient_button.dart';

class ReconstructionUploadPage extends StatefulWidget {
  final List<XFile>? images;
  final String? taskName;
  final Map<String, dynamic>? params;

  const ReconstructionUploadPage({
    super.key,
    this.images,
    this.taskName,
    this.params,
  });

  @override
  State<ReconstructionUploadPage> createState() =>
      _ReconstructionUploadPageState();
}

class _ReconstructionUploadPageState extends State<ReconstructionUploadPage> {
  final ReconstructionService _reconstructionService = ReconstructionService();
  final ImagePicker _picker = ImagePicker();

  List<XFile> _selectedImages = [];
  String _currentStatus = 'ready';
  String? _taskId;
  double _progress = 0.0;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    if (widget.images != null && widget.images!.isNotEmpty) {
      _selectedImages = List.from(widget.images!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startProcess();
      });
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() {
        _selectedImages = images;
      });
    }
  }

  Future<void> _startProcess() async {
    if (_selectedImages.isEmpty ||
        _currentStatus == 'creating' ||
        _currentStatus == 'uploading') {
      return;
    }

    debugPrint(
      '[API] trigger button=start_reconstruction images=${_selectedImages.length}',
    );

    final taskState = context.read<TaskState>();
    final localTaskId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final taskName = _taskName;
    final params = _buildReconstructionParams();
    final algorithm = await _resolveAvailableAlgorithm(
      _normalizeAlgorithm(params['algorithm']?.toString()),
    );
    params['algorithm'] = algorithm;
    final initialTask = ProcessingTask(
      taskId: localTaskId,
      title: taskName,
      params: params,
      files: _selectedImages.map(_storageFileFromImage).toList(),
      status: TaskStatus.uploadingFiles,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    taskState.upsertTask(initialTask);
    _safeSetState(() {
      _currentStatus = 'creating';
      _progress = 0;
      _taskId = null;
    });

    var activeTaskId = localTaskId;
    try {
      _safeSetState(() {
        _currentStatus = 'uploading';
        _progress = 0.05;
      });

      final started = await _reconstructionService.startWithLocalFiles(
        filePaths: _selectedImages.map((image) => image.path).toList(),
        params: params,
        algorithm: algorithm,
        onSendProgress: (sent, total) {
          if (total <= 0) return;
          final progress = (sent / total).clamp(0.0, 1.0).toDouble();
          _safeSetState(
            () => _progress = (progress * 0.85).clamp(0.05, 0.85).toDouble(),
          );
        },
      );

      if (started == null) {
        taskState.updateTaskStatus(localTaskId, TaskStatus.failed);
        _safeSetState(() => _currentStatus = 'failed');
        debugPrint(
          '[API] result button=start_reconstruction failed reason=submit_task',
        );
        return;
      }

      final serverTaskId = started.taskId;
      if (serverTaskId.isEmpty) {
        taskState.updateTaskStatus(localTaskId, TaskStatus.failed);
        _safeSetState(() => _currentStatus = 'failed');
        debugPrint(
          '[API] result button=start_reconstruction failed reason=no_task_id',
        );
        return;
      }

      taskState.replaceTaskId(
        localTaskId,
        initialTask.copyWith(
          taskId: serverTaskId,
          params: {...params, 'server_task_id': serverTaskId},
          files: _selectedImages
              .map(
                (image) => _storageFileFromImage(
                  image,
                ).copyWith(status: FileSyncStatus.synced),
              )
              .toList(),
          status: TaskStatus.processing,
          updatedAt: DateTime.now(),
        ),
      );
      activeTaskId = serverTaskId;

      taskState.updateTaskStatus(serverTaskId, TaskStatus.processing);
      _safeSetState(() {
        _taskId = serverTaskId;
        _currentStatus = 'processing';
        _progress = 0.95;
      });

      _startPolling(serverTaskId);
      debugPrint(
        '[API] result button=start_reconstruction taskId=$serverTaskId',
      );
    } catch (e) {
      debugPrint('[API] result button=start_reconstruction failed error=$e');
      taskState.updateTaskStatus(activeTaskId, TaskStatus.failed);
      _safeSetState(() => _currentStatus = 'failed');
    }
  }

  void _startPolling(String taskId) {
    final taskState = context.read<TaskState>();
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      final statusData = await _reconstructionService.checkStatus(taskId);
      if (statusData == null) return;

      _logTaskStatus('reconstruction_poll', statusData);

      final serverStatus = statusData.status;
      final taskStatus = _mapServerStatus(serverStatus);
      final progress = _normalizeProgress(statusData.progress);

      taskState.updateTaskProgress(
        taskId,
        progress ?? _progress,
        status: taskStatus,
        stage: statusData.currentStage,
      );
      if (taskStatus == TaskStatus.completed) {
        timer.cancel();
        _safeSetState(() {
          _currentStatus = 'downloading';
          _progress = (_progress).clamp(0.0, 0.98);
        });
        _downloadAndPreview(taskId, statusData);
        return;
      }

      if (taskStatus == TaskStatus.failed) {
        _logTaskStatus('reconstruction_failed', statusData);
        timer.cancel();
        _safeSetState(() => _currentStatus = 'failed');
        return;
      }

      _safeSetState(() {
        _currentStatus = 'processing';
        if (progress != null) {
          _progress = progress.clamp(0.0, 1.0);
        } else if (_progress < 0.9) {
          _progress += 0.05;
        }
      });
    });
  }

  Future<void> _downloadAndPreview(
    String taskId,
    ReconstructionStatusResponse statusData,
  ) async {
    debugPrint('[API] result reconstruction_completed taskId=$taskId');
    final resultFileId = statusData.resultFileId;
    if (resultFileId == null || resultFileId.isEmpty) {
      _logTaskStatus('reconstruction_completed_without_result_file', statusData);
      debugPrint(
        '[API] result downloadResultFile failed reason=no_result_file_id '
        'taskId=$taskId',
      );
      if (!mounted) return;
      context.read<TaskState>().updateTaskStatus(taskId, TaskStatus.completed);
      _safeSetState(() {
        _currentStatus = 'completed';
        _progress = 1.0;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text(context.tr('upload.result.noFile'))),
      );
      return;
    }

    final file = await _reconstructionService.downloadResultFile(
      resultFileId: resultFileId,
      taskId: taskId,
      onProgress: (downloadProgress) {
        _safeSetState(() {
          _progress = (0.95 + downloadProgress * 0.05).clamp(0.95, 1.0);
        });
      },
    );

    if (!mounted) return;

    if (file == null) {
      _logTaskStatus('reconstruction_download_failed_after_completed', statusData);
      context.read<TaskState>().updateTaskStatus(taskId, TaskStatus.completed);
      _safeSetState(() {
        _currentStatus = 'completed';
        _progress = 1.0;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text(context.tr('upload.result.downloadFailed'))),
      );
      return;
    }

    final fileSize = await file.length();
    if (!mounted) return;

    final resultPly = StorageFile(
      fileId: resultFileId,
      localPath: file.path,
      status: FileSyncStatus.synced,
      md5: '',
      size: fileSize,
    );
    final taskState = context.read<TaskState>();
    final task = taskState.getTask(taskId);
    if (task != null) {
      taskState.upsertTask(
        task.copyWith(
          status: TaskStatus.completed,
          resultPly: resultPly,
          updatedAt: DateTime.now(),
        ),
      );
    }

    _safeSetState(() {
      _currentStatus = 'completed';
      _progress = 1.0;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.tr('upload.result.opening'))));
    context.push('$homeTabPath/$localViewerPath', extra: file.path);
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

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  String get _taskName {
    final name = widget.taskName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return context.tr('home.task.untitled');
  }

  Map<String, dynamic> _buildReconstructionParams() {
    final raw = Map<String, dynamic>.from(widget.params ?? const {});
    raw.remove('images');
    raw['task_name'] = _taskName;
    raw['algorithm'] = _normalizeAlgorithm(raw['algorithm']?.toString());
    return raw;
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
      debugPrint(
        '[API] result algorithm_fallback requested=$requestedAlgorithm '
        'fallback=$defaultAlgorithm',
      );
      return defaultAlgorithm;
    }

    final fallback = availableAlgorithms.first;
    debugPrint(
      '[API] result algorithm_fallback requested=$requestedAlgorithm '
      'fallback=$fallback',
    );
    return fallback;
  }

  StorageFile _storageFileFromImage(XFile image) {
    final file = File(image.path);
    final size = file.existsSync() ? file.lengthSync() : 0;
    return StorageFile(
      fileId: image.name.isNotEmpty ? image.name : image.path,
      localPath: image.path,
      status: FileSyncStatus.localOnly,
      md5: '',
      size: size,
    );
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

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageState>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          context.tr('upload.title'),
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => context.go(homeTabPath),
        ),
      ),
      body: SciFiBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 80),
                  if (_currentStatus == 'ready') ...[
                    const Icon(
                      Icons.cloud_upload_outlined,
                      size: 80,
                      color: Color(0xFF00C6FF),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _selectedImages.isEmpty
                          ? context.tr('upload.pickPrompt')
                          : context.tr(
                              'upload.selectedImages',
                              args: {'count': _selectedImages.length},
                            ),
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 40),
                    ElevatedButton(
                      onPressed: _pickImages,
                      child: Text(context.tr('upload.pickImages')),
                    ),
                    const SizedBox(height: 20),
                    if (_selectedImages.isNotEmpty)
                      GradientButton(
                        label: context.tr('upload.start'),
                        onPressed: _startProcess,
                        height: 56,
                      ),
                  ] else ...[
                    _buildStatusUI(context),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusUI(BuildContext context) {
    var message = '';
    var icon = Icons.sync;
    var color = const Color(0xFF00C6FF);

    switch (_currentStatus) {
      case 'creating':
        message = context.tr('upload.stage.creating');
        icon = Icons.add_task;
        break;
      case 'uploading':
        message = context.tr('upload.stage.uploading');
        icon = Icons.cloud_upload;
        break;
      case 'submitting':
        message = context.tr('upload.stage.submitting');
        icon = Icons.send;
        break;
      case 'processing':
        message = context.tr('upload.stage.processing');
        icon = Icons.memory;
        break;
      case 'downloading':
        message = context.tr('upload.stage.downloading');
        icon = Icons.download;
        break;
      case 'completed':
        message = context.tr('upload.stage.completed');
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case 'failed':
        message = context.tr('upload.stage.failed');
        icon = Icons.error;
        color = Colors.red;
        break;
    }

    return Column(
      children: [
        Icon(icon, size: 80, color: color),
        const SizedBox(height: 32),
        Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 40),
        LinearProgressIndicator(
          value: _progress,
          backgroundColor: Colors.white10,
          color: color,
          minHeight: 8,
        ),
        const SizedBox(height: 20),
        Text(
          '${(_progress * 100).toInt()}%',
          style: TextStyle(color: color, fontSize: 16),
        ),
        if (_taskId != null) ...[
          const SizedBox(height: 12),
          Text(
            context.tr('upload.taskId', args: {'id': _taskId}),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
        if (_currentStatus == 'failed')
          TextButton(
            onPressed: () => setState(() => _currentStatus = 'ready'),
            child: Text(
              context.tr('common.retry'),
              style: const TextStyle(color: Colors.white70),
            ),
          ),
      ],
    );
  }
}
