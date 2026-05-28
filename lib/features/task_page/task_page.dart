import 'package:flutter/material.dart';

class TaskPage extends StatelessWidget {
  const TaskPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();

    // return Scaffold(
    //   backgroundColor: Colors.transparent,
    //   body: SafeArea(
    //     child: Consumer<TaskState>(
    //       builder: (context, taskState, child) {
    //         final tasks = taskState.allTasks;
    //
    //         if (tasks.isEmpty) {
    //           return const Center(
    //             child: Column(
    //               mainAxisAlignment: MainAxisAlignment.center,
    //               children: [
    //                 Icon(Icons.assignment_outlined, color: Colors.white24, size: 64),
    //                 SizedBox(height: 16),
    //                 Text(
    //                   '暂无任务',
    //                   style: TextStyle(color: Colors.white24, fontSize: 18),
    //                 ),
    //               ],
    //             ),
    //           );
    //         }
    //
    //         return ListView.builder(
    //           padding: const EdgeInsets.only(top: 20, bottom: 20),
    //           itemCount: tasks.length,
    //           itemBuilder: (context, index) {
    //             final task = tasks[index];
    //             // 选取第一张本地图片作为缩略图
    //             final localPath = task.files.isNotEmpty ? task.files.first.localPath : null;
    //
    //             return TaskItem(
    //               title: task.title,
    //               creationTime: _formatDateTime(task.createdAt),
    //               // status: taskState.getStatusDisplay(task.status),
    //               status: taskState.getStatusDisplay(task.status),
    //               localThumbnailPath: localPath,
    //               onView: () => debugPrint('查看任务: ${task.taskId}'),
    //               onDelete: () => taskState.removeTask(task.taskId),
    //             );
    //           },
    //         );
    //       },
    //     ),
    //   ),
    // );
  }
}
