import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/widgets/buttons/gradient_button.dart';
import '../../core/widgets/buttons/square_glass_button.dart';
import '../../core/widgets/buttons/glass_button.dart';
import '../../core/widgets/carousel/custom_carousel.dart';
import '../../core/widgets/task/task_card.dart';
import '../../core/network/reconstruction_models.dart';
import '../../core/network/reconstruction_service.dart';
import '../../core/network/upload_service.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/route_config.dart';
import '../../core/services/session_prefetch_service.dart';
import '../../core/services/task_thumbnail_service.dart';
import '../../core/state/language_state.dart';
import '../../core/state/task_state.dart';
import 'dart:convert';
import 'dart:ui';
import 'dart:async';

import '../../core/network/upload_models.dart';
import 'package:provider/provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:io';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const String _fallbackTaskImage =
      'https://images.unsplash.com/photo-1513364776144-60967b0f800f?q=80&w=2071&auto=format&fit=crop';

  final ReconstructionService _reconstructionService = ReconstructionService();
  final UploadService _uploadService = UploadService();
  final TaskThumbnailService _thumbnailService = TaskThumbnailService.instance;
  final ImagePicker _picker = ImagePicker();
  final Map<String, Future<File?>> _thumbnailDownloadCache = {};
  Timer? _taskRefreshTimer;
  String _testResult = '';
  bool _isTesting = false;
  bool _loadingTasks = true;
  List<ReconstructionTaskResponse> _tasks = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadTasks());
  }

  @override
  void dispose() {
    _taskRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    debugPrint('[HomeTaskCard] trigger load remote tasks');
    final tasks = await _reconstructionService.listTasks();
    if (!mounted) return;
    debugPrint('[HomeTaskCard] result load remote tasks count=${tasks.length}');
    setState(() {
      _tasks = tasks;
      _loadingTasks = false;
    });
    _syncTaskRefreshTimer(_tasks.map((task) => task.status));
  }

  void _syncTaskRefreshTimer(Iterable<String> statuses) {
    final shouldPoll = statuses.any(_isUnfinished);
    if (!shouldPoll) {
      _taskRefreshTimer?.cancel();
      _taskRefreshTimer = null;
      return;
    }
    if (_taskRefreshTimer?.isActive == true) return;
    debugPrint('[HomeTaskCard] start polling task list');
    _taskRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_loadTasks());
    });
  }

  Future<void> _runUploadTest() async {
    debugPrint('[API] trigger button=test_upload_service');
    setState(() {
      _isTesting = true;
      _testResult = '姝ｅ湪閫夋嫨鍥剧墖...';
    });

    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) {
        setState(() {
          _isTesting = false;
          _testResult = '宸插彇娑堝浘鐗囬€夋嫨';
        });
        debugPrint(
          '[API] result button=test_upload_service skipped reason=no_file',
        );
        return;
      }

      final file = File(image.path);
      final fileSize = await file.length();
      final bytes = await file.readAsBytes();

      const encoder = JsonEncoder.withIndent('  ');
      String log = '--- [1/3] 鍒濆鍖栦笂浼?---\n';
      setState(() => _testResult = log);

      // 1. 鍒濆鍖?
      final fileHash = sha256.convert(bytes).toString();
      final initRes = await _uploadService.initializeUpload(
        image.path,
        fileHash: fileHash,
      );
      log += '鍒濆鍖栨垚鍔?\n${encoder.convert(initRes)}\n\n';
      setState(() => _testResult = log);

      final uploadId = initRes.uploadId;
      if (initRes.alreadyUploaded) {
        log +=
            'File already uploaded, file_id=${initRes.fileId.isNotEmpty ? initRes.fileId : initRes.imageId}\n';
        setState(() {
          _isTesting = false;
          _testResult = log;
        });
        return;
      }
      final chunkSize = initRes.chunkSize;
      final totalChunks = initRes.totalChunks;
      List<MergeRequestPart> parts = [];

      log += '--- [2/3] 鍒嗙墖涓婁紶 ($totalChunks) ---\n';
      setState(() => _testResult = log);

      // 2. 鍒嗙墖涓婁紶
      for (int i = 0; i < totalChunks; i++) {
        int start = i * chunkSize;
        int end = (i + 1) * chunkSize;
        if (end > fileSize) end = fileSize;
        final chunkData = bytes.sublist(start, end);

        final chunkRes = await _uploadService.uploadChunk(
          uploadId: uploadId,
          chunkIndex: i,
          chunkData: chunkData,
        );

        parts.add(MergeRequestPart(chunkIndex: i, etag: chunkRes.etag));
        log += '鍒嗙墖 $i 鎴愬姛: etag=${chunkRes.etag}\n';
        setState(() => _testResult = log);
      }

      log += '\n--- [3/3] 鍚堝苟鍒嗙墖 ---\n';
      setState(() => _testResult = log);

      // 3. 鍚堝苟
      final mergeRes = await _uploadService.mergeChunks(
        uploadId: uploadId,
        expectedSize: fileSize,
        expectedHash: fileHash,
        parts: parts,
      );

      log +=
          '鍚堝苟鎴愬姛:\n${encoder.convert({'file_id': mergeRes.fileId, 'file_hash': mergeRes.fileHash, 'storage_key': mergeRes.storageKey, 'verified': mergeRes.verified})}\n';

      setState(() {
        _isTesting = false;
        _testResult = log;
      });
      debugPrint('[API] result button=test_upload_service success');
    } catch (e) {
      setState(() {
        _isTesting = false;
        _testResult += '\n[ERROR] 鎿嶄綔澶辫触:\n$e';
      });
      debugPrint('[API] result button=test_upload_service failed error=$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageState>();
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.transparent, 
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CustomCarousel(
                images: const [
                  'https://images.unsplash.com/photo-1451187580459-43490279c0fa?q=80&w=2072&auto=format&fit=crop',
                  'https://images.unsplash.com/photo-1550745165-9bc0b252726f?q=80&w=2070&auto=format&fit=crop',
                  'https://images.unsplash.com/photo-1558591710-4b4a1ae0f04d?q=80&w=1887&auto=format&fit=crop',
                ],
                height: 180,
              ),
              const SizedBox(height: 24),
              GradientButton(
                label: '开始创建',
                onPressed: () async {
                  await context.push('$homeTabPath/$creationConfigPath');
                  if (mounted) unawaited(_loadTasks());
                },
                height: 56,
              ),
              _buildFeaturedTaskArea(),

              // --- 娴嬭瘯涓婁紶鏈嶅姟閮ㄥ垎 ---
              const SizedBox(height: 16),
              GlassButton(
                label: _isTesting ? 'Testing...' : 'Test Upload Service',
                icon: _isTesting ? Icons.sync : Icons.cloud_upload_outlined,
                onPressed: _isTesting ? () {} : _runUploadTest,
                height: 48,
                opacity: 0.1,
              ),
              if (_testResult.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildTestResultDisplay(),
              ],

              // -----------------------
              const SizedBox(height: 24),
              // 妯悜鎺掑垪鍥涗釜鏂瑰舰纾ㄧ爞鎸夐挳
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SquareGlassButton(
                    label: '拍摄引导',
                    icon: Icons.camera_alt_outlined,
                    onPressed: () {
                      context.push('$homeTabPath/$cameraGuidePath');
                    },
                    size: 76,
                  ),
                  SquareGlassButton(
                    label: '本地资产',
                    icon: Icons.auto_awesome_motion_outlined,
                    onPressed: () =>
                        context.push('$homeTabPath/$localViewerPath'),
                    size: 76,
                  ),
                  SquareGlassButton(
                    label: '云端同步',
                    icon: Icons.cloud_done_outlined,
                    onPressed: () => debugPrint('tap: cloud sync'),
                    size: 76,
                  ),
                  SquareGlassButton(
                    label: '帮助',
                    icon: Icons.help_outline_rounded,
                    onPressed: () => debugPrint('tap: help'),
                    size: 76,
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeaturedTaskArea() {
    final taskState = context.watch<TaskState>();
    final tasks = _mergeTaskViews(taskState);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncTaskRefreshTimer(tasks.map((task) => task.status));
    });

    if (_loadingTasks && tasks.isEmpty) {
      return Container(
        height: 136,
        margin: const EdgeInsets.symmetric(vertical: 12),
        decoration: _homePanelDecoration(),
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFF00C6FF)),
        ),
      );
    }

    final task = _selectFeaturedTask(tasks);
    if (task == null) {
      debugPrint(
        '[HomeTaskCard] show empty prompt remote=${_tasks.length} '
        'local=${taskState.allTasks.length}',
      );
      return _buildEmptyTaskPrompt();
    }

    return TaskCard(
      headerText: _cardHeaderForStatus(task.status),
      title: task.title.isEmpty ? context.tr('home.task.untitled') : task.title,
      statusText: _statusText(task.status),
      progress: _normalizeProgress(task.progress),
      timeRemaining: _formatTaskTime(task),
      footerText: _footerText(task),
      imageUrl: _fallbackTaskImage,
      leadingImage: _buildTaskCardImage(task),
      onTap: () async {
        await context.push(
          '$taskTabPath/$taskDetailPath/${Uri.encodeComponent(task.taskId)}',
        );
        if (mounted) unawaited(_loadTasks());
      },
    );
  }

  List<_HomeTaskView> _mergeTaskViews(TaskState taskState) {
    final merged = <String, _HomeTaskView>{};
    for (final task in taskState.allTasks) {
      merged[task.taskId] = _HomeTaskView.local(task);
    }
    for (final task in _tasks) {
      final localTask = taskState.getTask(task.taskId);
      if (_isLocalMeshRunning(localTask)) {
        merged[task.taskId] = _HomeTaskView.local(localTask!);
        continue;
      }
      merged[task.taskId] = _HomeTaskView.remote(
        task,
        localTask: localTask,
      );
    }
    final list = merged.values.toList();
    debugPrint(
      '[HomeTaskCard] merged tasks remote=${_tasks.length} '
      'local=${taskState.allTasks.length} total=${list.length}',
    );
    return list;
  }

  bool _isLocalMeshRunning(ProcessingTask? task) {
    if (task == null) return false;
    final pendingMesh = (task.params['mesh_pending_algorithm'] ?? '')
        .toString()
        .isNotEmpty;
    final startedMesh = (task.params['mesh_algorithm'] ?? '')
        .toString()
        .isNotEmpty;
    final hasMeshResult = task.resultMesh != null;
    return (pendingMesh || startedMesh) &&
        !hasMeshResult &&
        task.status == TaskStatus.processing;
  }

  Widget _buildTaskCardImage(_HomeTaskView task) {
    if (task.hasRemoteThumbnailCandidates) {
      final future = _thumbnailDownloadCache.putIfAbsent(
        task.taskId,
        () => _getOrDownloadTaskThumbnail(task),
      );
      return FutureBuilder<File?>(
        future: future,
        builder: (context, snapshot) {
          final file = snapshot.data;
          if (file != null && file.existsSync()) {
            return Image.file(file, width: 72, height: 72, fit: BoxFit.cover);
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return _buildImageLoading();
          }
          return _buildLocalTaskFallbackImage(task.localTask);
        },
      );
    }
    return _buildLocalTaskFallbackImage(task.localTask);
  }

  Future<File?> _getOrDownloadTaskThumbnail(_HomeTaskView task) async {
    return _thumbnailService.resolveFromFileIds(
      taskId: task.taskId,
      previewFileId: task.previewFileId,
      previewFileIds: task.previewFileIds,
      inputFileIds: task.inputFileIds,
      outputDirectoryName: SessionPrefetchService.taskThumbnailDirectory,
    );
  }

  Widget _buildLocalTaskFallbackImage(ProcessingTask? localTask) {
    final path = _localTaskThumbnailPath(localTask);
    if (path == null) return TaskCard.buildImagePlaceholder();
    final file = File(path);
    if (!file.existsSync()) return TaskCard.buildImagePlaceholder();
    return Image.file(file, width: 72, height: 72, fit: BoxFit.cover);
  }

  Widget _buildImageLoading() {
    return Container(
      width: 72,
      height: 72,
      color: Colors.white.withValues(alpha: 0.08),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Color(0xFF00C6FF),
        ),
      ),
    );
  }

  String? _localTaskThumbnailPath(ProcessingTask? task) {
    if (task == null) return null;
    return _thumbnailService.localThumbnailPath(task);
  }

  Widget _buildEmptyTaskPrompt() {
    return GestureDetector(
      onTap: () async {
        await context.push('$homeTabPath/$creationConfigPath');
        if (mounted) unawaited(_loadTasks());
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(18),
        decoration: _homePanelDecoration(),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF00C6FF), Color(0xFF0072FF)],
                ),
              ),
              child: const Icon(
                Icons.add_photo_alternate_outlined,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('home.noTask.title'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr('home.noTask.subtitle'),
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  _HomeTaskView? _selectFeaturedTask(List<_HomeTaskView> tasks) {
    if (tasks.isEmpty) return null;

    final unfinished = tasks.where((task) => _isUnfinished(task.status)).toList()
      ..sort((a, b) => _taskTimestamp(a).compareTo(_taskTimestamp(b)));
    if (unfinished.isNotEmpty) return unfinished.first;

    final completed = tasks.where((task) => _isCompleted(task.status)).toList()
      ..sort(
        (a, b) => _completionTimestamp(b).compareTo(_completionTimestamp(a)),
      );
    if (completed.isNotEmpty) return completed.first;

    final failed = tasks.where((task) => _isFailed(task.status)).toList()
      ..sort((a, b) => _taskTimestamp(b).compareTo(_taskTimestamp(a)));
    if (failed.isNotEmpty) return failed.first;

    return tasks.first;
  }

  bool _isUnfinished(String status) {
    final value = status.toLowerCase();
    return value == 'pending' ||
        value == 'queued' ||
        value == 'uploadingfiles' ||
        value == 'uploading_files' ||
        value == 'processing' ||
        value == 'manual_review';
  }

  bool _isCompleted(String status) {
    final value = status.toLowerCase();
    return value == 'completed' || value == 'partial_completed';
  }

  bool _isFailed(String status) {
    final value = status.toLowerCase();
    return value == 'failed' || value == 'cancelled';
  }

  DateTime _taskTimestamp(_HomeTaskView task) {
    return task.createdAt ??
        task.startedAt ??
        task.updatedAt ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  DateTime _completionTimestamp(_HomeTaskView task) {
    return task.completedAt ??
        task.updatedAt ??
        task.createdAt ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _cardHeaderForStatus(String status) {
    if (_isUnfinished(status)) return context.tr('home.task.current');
    if (_isCompleted(status)) return context.tr('home.task.recentCompleted');
    if (_isFailed(status)) return context.tr('home.task.recentFailed');
    return context.tr('home.task.generic');
  }

  String _statusText(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return context.tr('home.status.pending');
      case 'queued':
        return context.tr('home.status.queued');
      case 'uploadingfiles':
      case 'uploading_files':
        return context.tr('task.status.uploading');
      case 'processing':
        return context.tr('home.status.processing');
      case 'manual_review':
        return context.tr('home.status.manualReview');
      case 'completed':
      case 'partial_completed':
        return context.tr('home.status.completed');
      case 'cancelled':
        return context.tr('home.status.cancelled');
      case 'failed':
        return context.tr('home.status.failed');
      default:
        return status.isEmpty ? context.tr('home.status.unknown') : status;
    }
  }

  double _normalizeProgress(double progress) {
    if (progress > 1) return (progress / 100).clamp(0, 1).toDouble();
    return progress.clamp(0, 1).toDouble();
  }

  String _formatTaskTime(_HomeTaskView task) {
    final time = task.updatedAt ?? task.createdAt;
    if (time == null) return '--';
    return _formatDateTime(time);
  }

  String _footerText(_HomeTaskView task) {
    if (_isCompleted(task.status)) {
      return context.tr(
        'home.footer.completedAt',
        args: {'time': _formatTaskTime(task)},
      );
    }
    if (_isFailed(task.status)) {
      return task.errorMessage.isEmpty
          ? context.tr(
              'home.footer.failedAt',
              args: {'time': _formatTaskTime(task)},
            )
          : task.errorMessage;
    }
    return task.currentStage.isEmpty
        ? context.tr(
            'home.footer.updatedAt',
            args: {'time': _formatTaskTime(task)},
          )
        : task.currentStage;
  }

  String _formatDateTime(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
        '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
  }

  BoxDecoration _homePanelDecoration() {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      color: const Color(0xFF03081C).withValues(alpha: 0.54),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.18),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  Widget _buildTestResultDisplay() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '鏈嶅姟鍣ㄥ搷搴旀祴璇曠粨鏋?',
                style: TextStyle(
                  color: Color(0xFF00C6FF),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                _testResult,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeTaskView {
  final String taskId;
  final String title;
  final String status;
  final double progress;
  final String currentStage;
  final String errorMessage;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? previewFileId;
  final List<String> previewFileIds;
  final List<String> inputFileIds;
  final ProcessingTask? localTask;

  const _HomeTaskView({
    required this.taskId,
    required this.title,
    required this.status,
    required this.progress,
    required this.currentStage,
    required this.errorMessage,
    this.createdAt,
    this.updatedAt,
    this.startedAt,
    this.completedAt,
    this.previewFileId,
    this.previewFileIds = const [],
    this.inputFileIds = const [],
    this.localTask,
  });

  factory _HomeTaskView.remote(
    ReconstructionTaskResponse task, {
    ProcessingTask? localTask,
  }) {
    return _HomeTaskView(
      taskId: task.taskId,
      title: task.title,
      status: task.status,
      progress: task.progress,
      currentStage: task.currentStage,
      errorMessage: task.errorMessage,
      createdAt: task.createdAt,
      updatedAt: task.updatedAt,
      startedAt: task.startedAt,
      completedAt: task.completedAt,
      previewFileId: _cleanFileId(
        task.previewImageId ??
            (task.previewIds.isNotEmpty ? task.previewIds.first : null),
      ),
      previewFileIds: task.previewIds,
      inputFileIds: task.inputFileIds,
      localTask: localTask,
    );
  }

  factory _HomeTaskView.local(ProcessingTask task) {
    return _HomeTaskView(
      taskId: task.taskId,
      title: task.title,
      status: task.status.name,
      progress: task.progress,
      currentStage: task.stage ?? '',
      errorMessage: task.status == TaskStatus.failed ? task.stage ?? '' : '',
      createdAt: task.createdAt,
      updatedAt: task.updatedAt,
      previewFileId: _cleanFileId(task.params['preview_image_id']?.toString()),
      previewFileIds: _readStringList(task.params['preview_ids']),
      inputFileIds: [
        ..._readStringList(task.params['input_file_ids']),
        ...task.files.map((file) => file.fileId),
      ],
      localTask: task,
    );
  }

  bool get hasRemoteThumbnailCandidates {
    return previewFileId != null ||
        previewFileIds.isNotEmpty ||
        inputFileIds.isNotEmpty ||
        (taskId.isNotEmpty && !taskId.startsWith('local_'));
  }

  static String? _cleanFileId(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  static List<String> _readStringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty && item != 'null')
        .toList();
  }
}
