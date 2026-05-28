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

class TaskDetailPage extends StatefulWidget {
  final String taskId;
  final List<XFile>? initialImages;

  const TaskDetailPage({super.key, required this.taskId, this.initialImages});

  @override
  State<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<TaskDetailPage> {
  final ReconstructionService _reconstructionService = ReconstructionService();
  final UploadService _uploadService = UploadService();
  Timer? _statusTimer;
  bool _started = false;
  String _activeTaskId = '';

  @override
  void initState() {
    super.initState();
    _activeTaskId = widget.taskId;
    if (widget.initialImages != null && widget.initialImages!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_startTask(widget.initialImages!));
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final task = context.read<TaskState>().getTask(_activeTaskId);
        if (task != null && _shouldPoll(task)) {
          _startPolling(task.taskId);
        }
      });
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _startTask(List<XFile> images) async {
    if (_started) return;
    _started = true;

    final taskState = context.read<TaskState>();
    final localTask = taskState.getTask(_activeTaskId);
    if (localTask == null) return;

    try {
      taskState.updateTaskProgress(
        _activeTaskId,
        0.02,
        status: TaskStatus.pending,
        stage: '正在创建重建任务',
      );

      final params = Map<String, dynamic>.from(localTask.params);
      final algorithm = await _resolveAvailableAlgorithm(
        _normalizeAlgorithm(params['algorithm']?.toString()),
      );
      params['algorithm'] = algorithm;

      final createdTask = await _reconstructionService.createTask(
        ReconstructionCreateTaskRequest(
          title: localTask.title,
          params: params,
          algorithm: algorithm,
        ),
      );
      final serverTaskId = createdTask?.taskId;
      if (serverTaskId == null || serverTaskId.isEmpty) {
        taskState.updateTaskProgress(
          _activeTaskId,
          localTask.progress,
          status: TaskStatus.failed,
          stage: '创建任务失败',
        );
        return;
      }

      final serverTask = localTask.copyWith(
        taskId: serverTaskId,
        params: {...params, 'server_task_id': serverTaskId},
        status: TaskStatus.uploadingFiles,
        progress: 0.05,
        stage: '正在上传素材',
        updatedAt: DateTime.now(),
      );
      taskState.replaceTaskId(_activeTaskId, serverTask);
      _activeTaskId = serverTaskId;

      final uploadedFiles = <StorageFile>[];
      final imageIds = <String>[];
      for (var index = 0; index < images.length; index++) {
        final image = images[index];
        final uploaded = await _uploadService.uploadFile(
          image.path,
          onProgress: (fileProgress) {
            final progress = (index + fileProgress) / images.length;
            taskState.updateTaskProgress(
              _activeTaskId,
              (0.05 + progress * 0.5).clamp(0.05, 0.55),
              status: TaskStatus.uploadingFiles,
              stage: '正在上传素材 ${index + 1}/${images.length}',
            );
          },
        );
        imageIds.add(uploaded.fileId);
        uploadedFiles.add(
          _storageFileFromImage(image).copyWith(
            fileId: uploaded.fileId,
            remoteUrl: uploaded.storageKey,
            status: FileSyncStatus.synced,
            md5: uploaded.fileHash,
          ),
        );
        final task = taskState.getTask(_activeTaskId);
        if (task != null) {
          taskState.upsertTask(
            task.copyWith(
              params: {...task.params, 'image_ids': imageIds},
              files: [
                ...uploadedFiles,
                ...images.skip(index + 1).map(_storageFileFromImage),
              ],
              updatedAt: DateTime.now(),
            ),
          );
        }
      }

      taskState.updateTaskProgress(
        _activeTaskId,
        0.58,
        status: TaskStatus.pending,
        stage: '正在提交重建任务',
      );
      final started = await _reconstructionService.startWithUploadedImages(
        taskId: _activeTaskId,
        request: ReconstructionStartUploadedRequest(
          imageFileIds: imageIds,
          params: params,
          algorithm: algorithm,
        ),
      );
      if (started == null) {
        taskState.updateTaskProgress(
          _activeTaskId,
          0.58,
          status: TaskStatus.failed,
          stage: '提交重建任务失败',
        );
        return;
      }

      taskState.updateTaskProgress(
        _activeTaskId,
        0.62,
        status: TaskStatus.processing,
        stage: '算法正在重建',
      );
      _startPolling(_activeTaskId);
    } catch (e) {
      debugPrint('[API] result task_detail_start failed error=$e');
      taskState.updateTaskProgress(
        _activeTaskId,
        taskState.getTask(_activeTaskId)?.progress ?? 0,
        status: TaskStatus.failed,
        stage: '任务执行失败',
      );
    }
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

    final taskStatus = _mapServerStatus(statusData.status);
    final serverProgress = _normalizeProgress(statusData.progress);
    final progress = serverProgress == null
        ? (taskState.getTask(taskId)?.progress ?? 0.62)
        : (0.62 + serverProgress * 0.28).clamp(0.62, 0.9);

    taskState.updateTaskProgress(
      taskId,
      progress,
      status: taskStatus,
      stage: statusData.currentStage ?? '算法正在重建',
    );

    if (taskStatus == TaskStatus.completed) {
      _statusTimer?.cancel();
      await _downloadResult(taskId, statusData);
    } else if (taskStatus == TaskStatus.failed) {
      _statusTimer?.cancel();
    }
  }

  Future<void> _refreshTask() async {
    final task = context.read<TaskState>().getTask(_activeTaskId);
    if (task == null || task.taskId.startsWith('local_')) return;
    await _pollStatus(task.taskId);
  }

  Future<void> _downloadResult(
    String taskId,
    ReconstructionStatusResponse statusData,
  ) async {
    final taskState = context.read<TaskState>();
    final resultFileId = statusData.resultFileId;
    if (resultFileId == null || resultFileId.isEmpty) {
      taskState.updateTaskProgress(
        taskId,
        0.9,
        status: TaskStatus.failed,
        stage: '缺少结果文件 ID',
      );
      return;
    }

    taskState.updateTaskProgress(
      taskId,
      0.9,
      status: TaskStatus.processing,
      stage: '正在下载重建结果',
    );
    final result = await _reconstructionService.downloadResultFile(
      resultFileId: resultFileId,
      taskId: taskId,
      onProgress: (downloadProgress) {
        taskState.updateTaskProgress(
          taskId,
          (0.9 + downloadProgress * 0.1).clamp(0.9, 1.0),
          status: TaskStatus.processing,
          stage: '正在下载重建结果',
        );
      },
    );

    if (result == null) {
      taskState.updateTaskProgress(
        taskId,
        0.9,
        status: TaskStatus.failed,
        stage: '结果下载失败',
      );
      return;
    }

    final task = taskState.getTask(taskId);
    if (task != null) {
      taskState.upsertTask(
        task.copyWith(
          status: TaskStatus.completed,
          progress: 1,
          stage: '重建完成',
          resultPly: StorageFile(
            fileId: resultFileId,
            localPath: result.path,
            status: FileSyncStatus.synced,
            md5: '',
            size: await result.length(),
          ),
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TaskState>(
      builder: (context, taskState, child) {
        final task =
            taskState.getTask(_activeTaskId) ??
            taskState.getTask(widget.taskId);

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('任务详情', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () => context.pop(),
            ),
          ),
          body: SafeArea(
            child: task == null
                ? const Center(
                    child: Text(
                      '任务不存在',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
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
                          status: taskState.getStatusDisplay(task.status),
                        ),
                        const SizedBox(height: 24),
                        _InfoSection(task: task),
                        const SizedBox(height: 24),
                        _ResultSection(task: task),
                        const SizedBox(height: 24),
                        _FilesSection(files: task.files),
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

  StorageFile _storageFileFromImage(XFile image) {
    final file = File(image.path);
    return StorageFile(
      fileId: image.name.isNotEmpty ? image.name : image.path,
      localPath: image.path,
      status: FileSyncStatus.localOnly,
      md5: '',
      size: file.existsSync() ? file.lengthSync() : 0,
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

  bool _shouldPoll(ProcessingTask task) {
    if (task.status == TaskStatus.completed ||
        task.status == TaskStatus.failed) {
      return false;
    }
    return !task.taskId.startsWith('local_');
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
      title: '基础信息',
      children: [
        _InfoRow(label: '任务 ID', value: task.taskId),
        _InfoRow(label: '创建时间', value: _formatDateTime(task.createdAt)),
        if (task.updatedAt != null)
          _InfoRow(label: '更新时间', value: _formatDateTime(task.updatedAt!)),
        _InfoRow(label: '素材数量', value: '${task.files.length}'),
      ],
    );
  }
}

class _ResultSection extends StatefulWidget {
  final ProcessingTask task;

  const _ResultSection({required this.task});

  @override
  State<_ResultSection> createState() => _ResultSectionState();
}

class _ResultSectionState extends State<_ResultSection> {
  final ReconstructionService _service = ReconstructionService();
  String? _localPath;
  int? _fileSize;
  bool _downloading = false;

  ProcessingTask get task => widget.task;

  @override
  void initState() {
    super.initState();
    _syncFromTask();
  }

  @override
  void didUpdateWidget(covariant _ResultSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.resultPly?.localPath !=
            widget.task.resultPly?.localPath ||
        oldWidget.task.resultPly?.size != widget.task.resultPly?.size) {
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
  }

  @override
  Widget build(BuildContext context) {
    final result = task.resultPly;
    final canOpen =
        _localPath != null &&
        _localPath!.isNotEmpty &&
        File(_localPath!).existsSync();
    final canDownload = result != null && result.fileId.isNotEmpty;

    return _Section(
      title: '重建结果',
      children: [
        _InfoRow(label: '结果文件', value: canOpen ? _localPath! : '暂无本地结果'),
        _InfoRow(
          label: '文件大小',
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
                  label: const Text('打开渲染器'),
                  style: _buttonStyle(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              tooltip: '删除本地结果',
              onPressed: canOpen ? _deleteLocalResult : null,
              icon: const Icon(Icons.delete_outline),
              color: Colors.white,
            ),
            IconButton(
              tooltip: '重新下载',
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
      ],
    );
  }

  Future<void> _deleteLocalResult() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0B1026),
        title: const Text('删除本地结果'),
        content: const Text('确定要删除本地重建结果文件吗？删除后可以重新下载。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除', style: TextStyle(color: Colors.redAccent)),
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
}

class _FilesSection extends StatelessWidget {
  final List<StorageFile> files;

  const _FilesSection({required this.files});

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '上传素材',
      children: [
        if (files.isEmpty)
          const Text(
            '暂无素材记录',
            style: TextStyle(color: Colors.white54, fontSize: 14),
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
  final ReconstructionService _service = ReconstructionService();
  String? _localPath;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _localPath = widget.file.localPath;
    if (!_hasLocalFile && widget.file.fileId.isNotEmpty) {
      unawaited(_download());
    }
  }

  bool get _hasLocalFile =>
      _localPath != null &&
      _localPath!.isNotEmpty &&
      File(_localPath!).existsSync();

  Future<void> _download() async {
    setState(() => _loading = true);
    final file = await _service.downloadFile(
      fileId: widget.file.fileId,
      outputDirectoryName: 'media',
    );
    if (!mounted) return;
    setState(() {
      _localPath = file?.path;
      _loading = false;
    });
  }

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
                  child: _loading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
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
