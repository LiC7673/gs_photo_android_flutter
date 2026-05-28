import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TaskStatus {
  draft,
  uploadingFiles,
  pending,
  processing,
  completed,
  failed,
}

enum FileSyncStatus { localOnly, uploading, synced, downloading, cloudOnly }

class StorageFile {
  final String fileId;
  final String? localPath;
  final String? remoteUrl;
  final FileSyncStatus status;
  final String md5;
  final int size;

  StorageFile({
    required this.fileId,
    this.localPath,
    this.remoteUrl,
    required this.status,
    required this.md5,
    required this.size,
  });

  bool get isLocalAvailable =>
      localPath != null &&
      (status == FileSyncStatus.synced || status == FileSyncStatus.localOnly);

  StorageFile copyWith({
    String? fileId,
    String? localPath,
    String? remoteUrl,
    FileSyncStatus? status,
    String? md5,
    int? size,
  }) {
    return StorageFile(
      fileId: fileId ?? this.fileId,
      localPath: localPath ?? this.localPath,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      status: status ?? this.status,
      md5: md5 ?? this.md5,
      size: size ?? this.size,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'file_id': fileId,
      'local_path': localPath,
      'remote_url': remoteUrl,
      'status': status.name,
      'md5': md5,
      'size': size,
    };
  }

  factory StorageFile.fromJson(Map<String, dynamic> json) {
    return StorageFile(
      fileId: json['file_id'] as String? ?? '',
      localPath: json['local_path'] as String?,
      remoteUrl: json['remote_url'] as String?,
      status: _enumByName(
        FileSyncStatus.values,
        json['status'] as String?,
        FileSyncStatus.localOnly,
      ),
      md5: json['md5'] as String? ?? '',
      size: json['size'] as int? ?? 0,
    );
  }
}

class ProcessingTask {
  final String taskId;
  final String title;
  final Map<String, dynamic> params;
  final List<StorageFile> files;
  final TaskStatus status;
  final double progress;
  final String? stage;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final StorageFile? resultPly;

  ProcessingTask({
    required this.taskId,
    required this.title,
    required this.params,
    required this.files,
    required this.status,
    this.progress = 0,
    this.stage,
    required this.createdAt,
    this.updatedAt,
    this.resultPly,
  });

  ProcessingTask copyWith({
    String? taskId,
    String? title,
    Map<String, dynamic>? params,
    TaskStatus? status,
    double? progress,
    String? stage,
    List<StorageFile>? files,
    DateTime? updatedAt,
    StorageFile? resultPly,
  }) {
    return ProcessingTask(
      taskId: taskId ?? this.taskId,
      title: title ?? this.title,
      params: params ?? this.params,
      files: files ?? this.files,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      stage: stage ?? this.stage,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      resultPly: resultPly ?? this.resultPly,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'task_id': taskId,
      'title': title,
      'params': params,
      'files': files.map((file) => file.toJson()).toList(),
      'status': status.name,
      'progress': progress,
      'stage': stage,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'result_ply': resultPly?.toJson(),
    };
  }

  factory ProcessingTask.fromJson(Map<String, dynamic> json) {
    return ProcessingTask(
      taskId: json['task_id'] as String? ?? '',
      title: json['title'] as String? ?? '未命名任务',
      params: Map<String, dynamic>.from(json['params'] as Map? ?? const {}),
      files: (json['files'] as List? ?? const [])
          .whereType<Map>()
          .map((file) => StorageFile.fromJson(Map<String, dynamic>.from(file)))
          .toList(),
      status: _enumByName(
        TaskStatus.values,
        json['status'] as String?,
        TaskStatus.draft,
      ),
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      stage: json['stage'] as String?,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
      resultPly: json['result_ply'] is Map
          ? StorageFile.fromJson(
              Map<String, dynamic>.from(json['result_ply'] as Map),
            )
          : null,
    );
  }
}

class TaskState extends ChangeNotifier {
  static const String _tasksKey = 'tasks.processing';

  final Map<String, ProcessingTask> _tasks = {};
  bool _isRestored = false;

  TaskState() {
    unawaited(restoreTasks());
  }

  bool get isRestored => _isRestored;

  List<ProcessingTask> get allTasks {
    final list = _tasks.values.toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  List<ProcessingTask> getTasksByStatus(TaskStatus status) {
    return _tasks.values.where((task) => task.status == status).toList();
  }

  ProcessingTask? getTask(String taskId) => _tasks[taskId];

  Future<void> restoreTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tasksKey);
    try {
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List;
        final restoredTasks = Map<String, ProcessingTask>.fromEntries(
          decoded
              .whereType<Map>()
              .map(
                (json) =>
                    ProcessingTask.fromJson(Map<String, dynamic>.from(json)),
              )
              .where((task) => task.taskId.isNotEmpty)
              .map((task) => MapEntry(task.taskId, task)),
        );
        restoredTasks.addAll(_tasks);
        _tasks
          ..clear()
          ..addAll(restoredTasks);
      }
    } catch (e) {
      debugPrint('[TaskState] restore tasks failed: $e');
    }
    _isRestored = true;
    notifyListeners();
  }

  void upsertTask(ProcessingTask task) {
    _tasks[task.taskId] = task;
    _persistTasks();
    notifyListeners();
  }

  void replaceTaskId(String oldTaskId, ProcessingTask task) {
    _tasks.remove(oldTaskId);
    _tasks[task.taskId] = task;
    _persistTasks();
    notifyListeners();
  }

  void updateTaskStatus(String taskId, TaskStatus status) {
    final task = _tasks[taskId];
    if (task != null) {
      _tasks[taskId] = task.copyWith(status: status, updatedAt: DateTime.now());
      _persistTasks();
      notifyListeners();
    }
  }

  void updateTaskProgress(
    String taskId,
    double progress, {
    TaskStatus? status,
    String? stage,
  }) {
    final task = _tasks[taskId];
    if (task != null) {
      _tasks[taskId] = task.copyWith(
        status: status,
        progress: progress.clamp(0, 1),
        stage: stage,
        updatedAt: DateTime.now(),
      );
      _persistTasks();
      notifyListeners();
    }
  }

  void updateFileStatus(
    String taskId,
    String fileId,
    FileSyncStatus status, {
    String? remoteUrl,
  }) {
    final task = _tasks[taskId];
    if (task != null) {
      final fileIndex = task.files.indexWhere((file) => file.fileId == fileId);
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
        _persistTasks();
        notifyListeners();
      }
    }
  }

  void removeTask(String taskId) {
    _tasks.remove(taskId);
    _persistTasks();
    notifyListeners();
  }

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

  void _persistTasks() {
    unawaited(_saveTasks());
  }

  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(allTasks.map((task) => task.toJson()).toList());
    await prefs.setString(_tasksKey, encoded);
  }
}

T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}
