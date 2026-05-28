import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/network/reconstruction_models.dart';
import '../../core/network/reconstruction_service.dart';
import '../../core/network/upload_service.dart';
import '../../core/router/route_config.dart';
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
  final UploadService _uploadService = UploadService();
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
      final createdTask = await _reconstructionService.createTask(
        ReconstructionCreateTaskRequest(
          title: taskName,
          params: params,
          algorithm: algorithm,
        ),
      );
      final serverTaskId = createdTask?.taskId;

      if (serverTaskId == null || serverTaskId.isEmpty) {
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
          status: TaskStatus.uploadingFiles,
          updatedAt: DateTime.now(),
        ),
      );
      activeTaskId = serverTaskId;

      _safeSetState(() {
        _taskId = serverTaskId;
        _currentStatus = 'uploading';
        _progress = 0.05;
      });

      final uploadedFiles = <StorageFile>[];
      final imageIds = <String>[];
      for (var index = 0; index < _selectedImages.length; index++) {
        final image = _selectedImages[index];
        final result = await _uploadService.uploadFile(
          image.path,
          onProgress: (fileProgress) {
            final progress = (index + fileProgress) / _selectedImages.length;
            _safeSetState(() => _progress = (progress * 0.8).clamp(0.05, 0.85));
          },
        );
        imageIds.add(result.fileId);
        uploadedFiles.add(
          _storageFileFromImage(image).copyWith(
            fileId: result.fileId,
            remoteUrl: result.storageKey,
            status: FileSyncStatus.synced,
            md5: result.fileHash,
          ),
        );
        taskState.upsertTask(
          initialTask.copyWith(
            taskId: serverTaskId,
            params: {
              ...params,
              'server_task_id': serverTaskId,
              'image_ids': imageIds,
            },
            files: [
              ...uploadedFiles,
              ..._selectedImages.skip(index + 1).map(_storageFileFromImage),
            ],
            status: TaskStatus.uploadingFiles,
            updatedAt: DateTime.now(),
          ),
        );
      }

      taskState.upsertTask(
        initialTask.copyWith(
          taskId: serverTaskId,
          params: {
            ...params,
            'server_task_id': serverTaskId,
            'image_ids': imageIds,
          },
          files: uploadedFiles,
          status: TaskStatus.pending,
          updatedAt: DateTime.now(),
        ),
      );

      _safeSetState(() {
        _currentStatus = 'submitting';
        _progress = 0.9;
      });

      final started = await _reconstructionService.startWithUploadedImages(
        taskId: serverTaskId,
        request: ReconstructionStartUploadedRequest(
          imageFileIds: imageIds,
          params: params,
          algorithm: algorithm,
        ),
      );

      if (started == null) {
        taskState.updateTaskStatus(serverTaskId, TaskStatus.failed);
        _safeSetState(() => _currentStatus = 'failed');
        debugPrint(
          '[API] result button=start_reconstruction failed reason=submit_task',
        );
        return;
      }

      taskState.updateTaskStatus(serverTaskId, TaskStatus.processing);
      _safeSetState(() {
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

      final serverStatus = statusData.status;
      final taskStatus = _mapServerStatus(serverStatus);
      final progress = _normalizeProgress(statusData.progress);

      taskState.updateTaskStatus(taskId, taskStatus);
      debugPrint(
        '[API] result reconstruction_poll taskId=$taskId status=$serverStatus',
      );

      if (taskStatus == TaskStatus.completed) {
        timer.cancel();
        _safeSetState(() {
          _currentStatus = 'downloading';
          _progress = 0.98;
        });
        _downloadAndPreview(taskId, statusData);
        return;
      }

      if (taskStatus == TaskStatus.failed) {
        timer.cancel();
        _safeSetState(() => _currentStatus = 'failed');
        return;
      }

      _safeSetState(() {
        _currentStatus = 'processing';
        if (progress != null) {
          _progress = progress.clamp(0.05, 0.95);
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
      debugPrint(
        '[API] result downloadResultFile failed reason=no_result_file_id '
        'taskId=$taskId',
      );
      if (!mounted) return;
      context.read<TaskState>().updateTaskStatus(taskId, TaskStatus.failed);
      _safeSetState(() => _currentStatus = 'failed');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('重建完成，但没有返回结果文件 ID')));
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
      context.read<TaskState>().updateTaskStatus(taskId, TaskStatus.failed);
      _safeSetState(() => _currentStatus = 'failed');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('重建完成，但结果下载失败')));
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
    ).showSnackBar(const SnackBar(content: Text('重建完成，正在打开渲染器')));
    context.push('$homeTabPath/$localViewerPath', extra: file.path);
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  String get _taskName {
    final name = widget.taskName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return '未命名任务';
  }

  Map<String, dynamic> _buildReconstructionParams() {
    final raw = Map<String, dynamic>.from(widget.params ?? const {});
    raw.remove('images');
    raw['task_name'] = _taskName;
    raw['image_count'] = _selectedImages.length;
    raw['type'] = raw['type'] ?? 'object';
    raw['resolution'] = raw['resolution'] ?? 0.5;
    raw['algorithm'] = _normalizeAlgorithm(raw['algorithm']?.toString());
    raw['cuda_device'] = raw['cuda_device'] ?? '1';
    raw['python_path'] =
        raw['python_path'] ?? '/data1/lzh/anaconda3/envs/anysplat/bin/python';
    raw['algorithm_path'] = raw['algorithm_path'] ?? '/data1/lzh/lzy/AnySplat';
    return raw;
  }

  String _normalizeAlgorithm(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'anysplat':
        return 'anysplat';
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('启动 3DGS 重建', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => context.pop(),
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
                          ? '请选择需要重建的图片'
                          : '已选择 ${_selectedImages.length} 张图片',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 40),
                    ElevatedButton(
                      onPressed: _pickImages,
                      child: const Text('从相册选择图片'),
                    ),
                    const SizedBox(height: 20),
                    if (_selectedImages.isNotEmpty)
                      GradientButton(
                        label: '开始上传并重建',
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
        message = '正在创建重建任务...';
        icon = Icons.add_task;
        break;
      case 'uploading':
        message = '正在上传图片素材...';
        icon = Icons.cloud_upload;
        break;
      case 'submitting':
        message = '正在提交图片到重建任务...';
        icon = Icons.send;
        break;
      case 'processing':
        message = '算法正在重建 3D 点云...';
        icon = Icons.memory;
        break;
      case 'downloading':
        message = '正在下载重建结果...';
        icon = Icons.download;
        break;
      case 'completed':
        message = '重建成功';
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case 'failed':
        message = '处理失败，请重试';
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
            '任务 ID: $_taskId',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
        if (_currentStatus == 'failed')
          TextButton(
            onPressed: () => setState(() => _currentStatus = 'ready'),
            child: const Text('返回重试', style: TextStyle(color: Colors.white70)),
          ),
      ],
    );
  }
}
