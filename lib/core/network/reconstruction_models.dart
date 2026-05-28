class ReconstructionCreateTaskRequest {
  final String title;
  final Map<String, dynamic> params;
  final String? algorithm;

  ReconstructionCreateTaskRequest({
    required this.title,
    required this.params,
    this.algorithm,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'task_name': title,
    'params': params,
    if (algorithm != null && algorithm!.isNotEmpty) 'algorithm': algorithm,
  };
}

class ReconstructionTaskResponse {
  final String taskId;
  final String title;
  final String status;
  final double progress;
  final String currentStage;
  final String errorMessage;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ReconstructionTaskResponse({
    required this.taskId,
    required this.title,
    required this.status,
    required this.progress,
    required this.currentStage,
    required this.errorMessage,
    this.createdAt,
    this.updatedAt,
  });

  factory ReconstructionTaskResponse.fromJson(Map<String, dynamic> json) {
    return ReconstructionTaskResponse(
      taskId: (json['task_id'] ?? json['id'] ?? '').toString(),
      title: json['title'] as String? ?? '',
      status: json['status'] as String? ?? '',
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      currentStage: json['current_stage'] as String? ?? '',
      errorMessage: json['error_message'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
    );
  }
}

class ReconstructionStartUploadedRequest {
  final List<String> imageFileIds;
  final Map<String, dynamic> params;
  final String? algorithm;

  ReconstructionStartUploadedRequest({
    required this.imageFileIds,
    required this.params,
    this.algorithm,
  });

  List<Object> get normalizedImageFileIds => imageFileIds
      .map<Object>((id) => int.tryParse(id) ?? id)
      .toList(growable: false);

  Map<String, dynamic> toJson() => {
    'file_ids': normalizedImageFileIds,
    'params': {...params, 'file_ids': normalizedImageFileIds},
    if (algorithm != null && algorithm!.isNotEmpty) 'algorithm': algorithm,
  };
}

class ReconstructionStartResponse {
  final String taskId;
  final String status;
  final String algorithm;
  final int imagesCount;
  final String? queueName;
  final String? celeryTaskId;

  ReconstructionStartResponse({
    required this.taskId,
    required this.status,
    required this.algorithm,
    required this.imagesCount,
    this.queueName,
    this.celeryTaskId,
  });

  factory ReconstructionStartResponse.fromJson(Map<String, dynamic> json) {
    return ReconstructionStartResponse(
      taskId: (json['task_id'] ?? json['id'] ?? '').toString(),
      status: json['status'] as String? ?? '',
      algorithm: json['algorithm'] as String? ?? '',
      imagesCount:
          (json['images_count'] as num?)?.toInt() ??
          (json['image_count'] as num?)?.toInt() ??
          0,
      queueName: json['queue_name'] as String?,
      celeryTaskId: json['celery_task_id'] as String?,
    );
  }
}

class ReconstructionStatusResponse {
  final String taskId;
  final String status;
  final String? algorithm;
  final String? currentStage;
  final double? progress;
  final int? imageCount;
  final String? errorCode;
  final String? error;
  final String? resultFileId;

  ReconstructionStatusResponse({
    required this.taskId,
    required this.status,
    this.algorithm,
    this.currentStage,
    this.progress,
    this.imageCount,
    this.errorCode,
    this.error,
    this.resultFileId,
  });

  factory ReconstructionStatusResponse.fromJson(Map<String, dynamic> json) {
    return ReconstructionStatusResponse(
      taskId: (json['task_id'] ?? '').toString(),
      status: json['status'] as String? ?? '',
      algorithm: json['algorithm'] as String?,
      currentStage: json['current_stage'] as String?,
      progress: (json['progress'] as num?)?.toDouble(),
      imageCount: (json['image_count'] as num?)?.toInt(),
      errorCode: json['error_code'] as String?,
      error: json['error'] as String?,
      resultFileId: json['result_file_id']?.toString(),
    );
  }
}

class ReconstructionCancelResponse {
  final String taskId;
  final String status;
  final bool cancelled;
  final String message;

  ReconstructionCancelResponse({
    required this.taskId,
    required this.status,
    required this.cancelled,
    required this.message,
  });

  factory ReconstructionCancelResponse.fromJson(Map<String, dynamic> json) {
    return ReconstructionCancelResponse(
      taskId: (json['task_id'] ?? '').toString(),
      status: json['status'] as String? ?? '',
      cancelled: json['cancelled'] as bool? ?? false,
      message: json['message'] as String? ?? '',
    );
  }
}

class ReconstructionLogsResponse {
  final String taskId;
  final String status;
  final String stdoutTail;
  final String stderrTail;
  final String runCommand;
  final String? error;

  ReconstructionLogsResponse({
    required this.taskId,
    required this.status,
    required this.stdoutTail,
    required this.stderrTail,
    required this.runCommand,
    this.error,
  });

  factory ReconstructionLogsResponse.fromJson(Map<String, dynamic> json) {
    return ReconstructionLogsResponse(
      taskId: (json['task_id'] ?? '').toString(),
      status: json['status'] as String? ?? '',
      stdoutTail: json['stdout_tail'] as String? ?? '',
      stderrTail: json['stderr_tail'] as String? ?? '',
      runCommand: json['run_command'] as String? ?? '',
      error: json['error'] as String?,
    );
  }
}

class ReconstructionAlgorithmsResponse {
  final List<ReconstructionAlgorithm> algorithms;
  final String defaultAlgorithm;

  ReconstructionAlgorithmsResponse({
    required this.algorithms,
    required this.defaultAlgorithm,
  });

  factory ReconstructionAlgorithmsResponse.fromJson(Map<String, dynamic> json) {
    return ReconstructionAlgorithmsResponse(
      algorithms: (json['algorithms'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => ReconstructionAlgorithm.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
      defaultAlgorithm: json['default_algorithm'] as String? ?? '',
    );
  }
}

class ReconstructionAlgorithm {
  final String name;
  final String displayName;
  final bool available;

  ReconstructionAlgorithm({
    required this.name,
    required this.displayName,
    required this.available,
  });

  factory ReconstructionAlgorithm.fromJson(Map<String, dynamic> json) {
    return ReconstructionAlgorithm(
      name: json['name'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      available: json['available'] as bool? ?? false,
    );
  }
}

class ReconstructionHookEvent {
  final String name;
  final String? taskId;
  final Map<String, dynamic> payload;

  ReconstructionHookEvent({
    required this.name,
    this.taskId,
    this.payload = const {},
  });
}

typedef ReconstructionHook = void Function(ReconstructionHookEvent event);
