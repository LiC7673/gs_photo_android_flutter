import 'package:flutter/material.dart';

/// 任务状态枚举
enum TaskStatus {
  draft, // 草稿状态（正在选择图片，尚未提交）
  uploadingFiles, // 正在上传文件队列
  pending, // 文件就绪，等待服务器调度
  processing, // 服务器正在计算/重建中
  completed, // 任务完成
  failed, // 任务失败
}

/// 文件同步状态枚举
enum FileSyncStatus {
  localOnly, // 仅在本地（待上传）
  uploading, // 正在上传
  synced, // 本地和云端一致（已上传）
  downloading, // 正在从云端下载到本地
  cloudOnly, // 仅在云端（本地被清理或在新设备登录）
}

/// 文件存储模型
class StorageFile {
  final String fileId; // 文件唯一标识
  final String? localPath; // 本地绝对路径或相对路径
  final String? remoteUrl; // 对象存储访问链接
  final FileSyncStatus status;
  final String md5; // 用于校验文件完整性
  final int size; // 文件大小 (bytes)

  StorageFile({
    required this.fileId,
    this.localPath,
    this.remoteUrl,
    required this.status,
    required this.md5,
    required this.size,
  });

  /// 检查本地是否可用
  bool get isLocalAvailable =>
      localPath != null &&
      (status == FileSyncStatus.synced || status == FileSyncStatus.localOnly);

  StorageFile copyWith({
    String? localPath,
    String? remoteUrl,
    FileSyncStatus? status,
  }) {
    return StorageFile(
      fileId: fileId,
      localPath: localPath ?? this.localPath,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      status: status ?? this.status,
      md5: md5,
      size: size,
    );
  }
}

/// 处理中的任务模型
class ProcessingTask {
  final String taskId;
  final String title;
  final Map<String, dynamic> params;
  final List<StorageFile> files;
  final TaskStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // 修复 1：将其声明为可空类型（加问号），因为任务刚创建时没有结果文件
  final StorageFile? resultPly;

  ProcessingTask({
    required this.taskId,
    required this.title,
    required this.params,
    required this.files,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    this.resultPly, // 修复 2：将其加入构造函数
  });

  ProcessingTask copyWith({
    TaskStatus? status,
    List<StorageFile>? files,
    DateTime? updatedAt,
    StorageFile? resultPly, // 修复 3：在 copyWith 中提供修改它的入口
  }) {
    return ProcessingTask(
      taskId: taskId,
      title: title,
      params: params,
      files: files ?? this.files,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      resultPly: resultPly ?? this.resultPly, // 修复 4：保留原有值或更新新值
    );
  }
}

/// 全局任务状态管理
class TaskState extends ChangeNotifier {
  final Map<String, ProcessingTask> _tasks = {};

  /// 获取所有任务列表 (按创建时间倒序)
  List<ProcessingTask> get allTasks {
    final list = _tasks.values.toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// 获取特定状态的任务
  List<ProcessingTask> getTasksByStatus(TaskStatus status) {
    return _tasks.values.where((t) => t.status == status).toList();
  }

  /// 获取单个任务
  ProcessingTask? getTask(String taskId) => _tasks[taskId];

  /// 添加或更新任务
  void upsertTask(ProcessingTask task) {
    _tasks[task.taskId] = task;
    notifyListeners();
  }

  /// 快速更新任务状态
  void updateTaskStatus(String taskId, TaskStatus status) {
    final task = _tasks[taskId];
    if (task != null) {
      _tasks[taskId] = task.copyWith(status: status, updatedAt: DateTime.now());
      notifyListeners();
    }
  }

  /// 更新任务中的文件状态
  void updateFileStatus(
    String taskId,
    String fileId,
    FileSyncStatus status, {
    String? remoteUrl,
  }) {
    final task = _tasks[taskId];
    if (task != null) {
      final fileIndex = task.files.indexWhere((f) => f.fileId == fileId);
      if (fileIndex != -1) {
        final updatedFiles = List<StorageFile>.from(task.files);
        updatedFiles[fileIndex] = updatedFiles[fileIndex].copyWith(
          status: status,
          remoteUrl: remoteUrl,
        );
        _tasks[taskId] = task.copyWith(
          files: updatedFiles,
          updatedAt: DateTime.now(),
        );
        notifyListeners();
      }
    }
  }

  /// 删除任务
  void removeTask(String taskId) {
    _tasks.remove(taskId);
    notifyListeners();
  }

  /// 转换状态为中文字符串
  String getStatusDisplay(TaskStatus status) {
    switch (status) {
      case TaskStatus.draft:
        return '草稿';
      case TaskStatus.uploadingFiles:
        return '正在上传';
      case TaskStatus.pending:
        return '等待中';
      case TaskStatus.processing:
        return '重建中';
      case TaskStatus.completed:
        return '已完成';
      case TaskStatus.failed:
        return '失败';
    }
  }
}
