import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/network/reconstruction_models.dart';
import '../../core/network/reconstruction_service.dart';
import '../../core/router/route_config.dart';
import '../../core/services/session_prefetch_service.dart';
import '../../core/services/task_thumbnail_service.dart';
import '../../core/state/language_state.dart';
import '../../core/state/task_state.dart';
import '../../core/widgets/task/task_item.dart';

class TaskPage extends StatefulWidget {
  const TaskPage({super.key});

  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> {
  final ReconstructionService _reconstructionService = ReconstructionService();
  final TaskThumbnailService _thumbnailService = TaskThumbnailService.instance;
  final Map<String, String> _remoteThumbnailPaths = {};
  final Set<String> _downloadingThumbnailTaskIds = {};
  bool _loadingRemoteTasks = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshTasks());
    });
  }

  Future<void> _refreshTasks() async {
    final taskState = context.read<TaskState>();
    debugPrint(
      '[TaskPage] trigger refresh tasks local=${taskState.allTasks.length}',
    );
    await taskState.restoreTasks();
    if (!mounted) return;
    await _loadRemoteTasks();
  }

  Future<void> _loadRemoteTasks() async {
    if (_loadingRemoteTasks) return;
    setState(() => _loadingRemoteTasks = true);
    try {
      debugPrint('[TaskPage] trigger remote task list');
      final remoteTasks = await _reconstructionService.listTasks();
      if (!mounted) return;
      debugPrint(
        '[TaskPage] result remote task list count=${remoteTasks.length}',
      );
      _syncRemoteTasks(context.read<TaskState>(), remoteTasks);
    } catch (e) {
      debugPrint('[TaskPage] result remote task list failed error=$e');
    } finally {
      if (mounted) setState(() => _loadingRemoteTasks = false);
    }
  }

  void _syncRemoteTasks(
    TaskState taskState,
    List<ReconstructionTaskResponse> remoteTasks,
  ) {
    var changed = 0;
    for (final remoteTask in remoteTasks) {
      if (remoteTask.taskId.isEmpty) {
        debugPrint('[TaskPage] skip remote task because taskId is empty');
        continue;
      }
      taskState.upsertTask(_toProcessingTask(remoteTask, taskState));
      unawaited(_cacheTaskThumbnail(remoteTask));
      changed++;
    }
    debugPrint('[TaskPage] result synced remote tasks count=$changed');
  }

  ProcessingTask _toProcessingTask(
    ReconstructionTaskResponse remoteTask,
    TaskState taskState,
  ) {
    final existing = taskState.getTask(remoteTask.taskId);
    final resultFileId = remoteTask.resultFileId;
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
    final params = {
      ...?existing?.params,
      ...remoteTask.params,
      if (remoteTask.algorithm != null) 'algorithm': remoteTask.algorithm,
      'visibility': remoteTask.hasVisibility
          ? remoteTask.visibility
          : existing?.visibility ?? 'private',
      if (remoteTask.previewImageId != null)
        'preview_image_id': remoteTask.previewImageId,
      if (remoteTask.previewIds.isNotEmpty) 'preview_ids': remoteTask.previewIds,
      if (remoteTask.inputFileIds.isNotEmpty)
        'input_file_ids': remoteTask.inputFileIds,
    };
    final files =
        existing != null && existing.files.isNotEmpty
            ? existing.files
            : remoteTask.inputFileIds
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

    return ProcessingTask(
      taskId: remoteTask.taskId,
      title: remoteTask.title.isNotEmpty
          ? remoteTask.title
          : existing?.title ?? remoteTask.taskId,
      params: params,
      files: files,
      status: _mapServerStatus(remoteTask.status),
      visibility: remoteTask.hasVisibility
          ? remoteTask.visibility
          : existing?.visibility ?? 'private',
      progress: _normalizeProgress(remoteTask.progress),
      stage: remoteTask.currentStage.isNotEmpty
          ? remoteTask.currentStage
          : existing?.stage,
      createdAt: remoteTask.createdAt ?? existing?.createdAt ?? DateTime.now(),
      updatedAt: remoteTask.updatedAt ?? DateTime.now(),
      resultPly: resultPly,
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageState>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Consumer<TaskState>(
          builder: (context, taskState, child) {
            final tasks = taskState.allTasks;

            if (!taskState.isRestored) {
              return const Center(child: CircularProgressIndicator());
            }

            if (tasks.isEmpty) {
              return RefreshIndicator(
                onRefresh: _refreshTasks,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 180),
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.assignment_outlined,
                            color: Colors.white24,
                            size: 64,
                          ),
                          const SizedBox(height: 16),
                          if (_loadingRemoteTasks) ...[
                            const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(height: 12),
                          ],
                          Text(
                            context.tr('task.empty'),
                            style: const TextStyle(
                              color: Colors.white24,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: _refreshTasks,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 20, bottom: 20),
                itemCount: tasks.length,
                itemBuilder: (context, index) {
                  final task = tasks[index];
                  final localPath =
                      _thumbnailPath(task) ?? _remoteThumbnailPaths[task.taskId];

                  return TaskItem(
                    title: task.title,
                    creationTime: _formatDateTime(task.createdAt),
                    status: _statusText(context, task.status),
                    visibility: task.visibility,
                    statusIcon: _statusIcon(task.status),
                    statusColor: _statusColor(task.status),
                    localThumbnailPath: localPath,
                    onView: () => context.push(
                      '$taskTabPath/$taskDetailPath/${Uri.encodeComponent(task.taskId)}',
                    ),
                    onDelete: () => _confirmDeleteTask(
                      context,
                      taskState,
                      task.taskId,
                      task.title,
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
        '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
  }

  String? _thumbnailPath(ProcessingTask task) {
    return _thumbnailService.localThumbnailPath(task);
  }

  Future<void> _cacheTaskThumbnail(ReconstructionTaskResponse task) async {
    if (!_downloadingThumbnailTaskIds.add(task.taskId)) return;
    try {
      final file = await _thumbnailService.resolveForRemoteTask(
        task,
        outputDirectoryName: SessionPrefetchService.taskThumbnailDirectory,
      );
      if (!mounted || file == null || !await file.exists()) return;
      setState(() => _remoteThumbnailPaths[task.taskId] = file.path);
      debugPrint(
        '[TaskPage] result thumbnail cached taskId=${task.taskId} '
        'path=${file.path}',
      );
    } catch (e) {
      debugPrint(
        '[TaskPage] result thumbnail cache failed taskId=${task.taskId} '
        'error=$e',
      );
    } finally {
      _downloadingThumbnailTaskIds.remove(task.taskId);
    }
  }

  Future<void> _confirmDeleteTask(
    BuildContext context,
    TaskState taskState,
    String taskId,
    String title,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0B1026),
        title: Text(context.tr('task.delete.title')),
        content: Text(
          context.tr('task.delete.message', args: {'title': title}),
        ),
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
    if (confirmed == true) {
      if (taskId.startsWith('local_')) {
        debugPrint('[TaskPage] delete local-only task taskId=$taskId');
        taskState.removeTask(taskId);
        return;
      }

      debugPrint('[TaskPage] trigger delete remote task taskId=$taskId');
      final result = await _reconstructionService.deleteTask(taskId);
      if (!mounted) return;
      if (result?.deleted == true) {
        taskState.removeTask(taskId);
        debugPrint('[TaskPage] result delete remote task success taskId=$taskId');
        return;
      }

      debugPrint('[TaskPage] result delete remote task failed taskId=$taskId');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('task.delete.failed'))),
      );
    }
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

  double _normalizeProgress(double progress) {
    if (progress > 1) return (progress / 100).clamp(0, 1).toDouble();
    return progress.clamp(0, 1).toDouble();
  }
}
