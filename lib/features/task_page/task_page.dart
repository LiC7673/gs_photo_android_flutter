import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/router/route_config.dart';
import '../../core/state/task_state.dart';
import '../../core/widgets/task/task_item.dart';

class TaskPage extends StatelessWidget {
  const TaskPage({super.key});

  @override
  Widget build(BuildContext context) {
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
                onRefresh: taskState.restoreTasks,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 180),
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.assignment_outlined,
                            color: Colors.white24,
                            size: 64,
                          ),
                          SizedBox(height: 16),
                          Text(
                            '暂无任务',
                            style: TextStyle(
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
              onRefresh: taskState.restoreTasks,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 20, bottom: 20),
                itemCount: tasks.length,
                itemBuilder: (context, index) {
                  final task = tasks[index];
                  final localPath = task.files.isNotEmpty
                      ? task.files.first.localPath
                      : null;

                  return TaskItem(
                    title: task.title,
                    creationTime: _formatDateTime(task.createdAt),
                    status: taskState.getStatusDisplay(task.status),
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
        title: const Text('删除任务'),
        content: Text('确定要删除“$title”吗？此操作不可撤销。'),
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
    if (confirmed == true) {
      taskState.removeTask(taskId);
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
}
