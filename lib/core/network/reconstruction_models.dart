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
    'params': params,
    if (algorithm != null && algorithm!.isNotEmpty) 'algorithm': algorithm,
  };
}

class ReconstructionTaskResponse {
  final String taskId;
  final String title;
  final String? algorithm;
  final Map<String, dynamic> params;
  final String status;
  final double progress;
  final String currentStage;
  final String errorMessage;
  final String visibility;
  final bool hasVisibility;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? previewImageId;
  final List<String> previewIds;
  final List<String> inputFileIds;
  final String? resultFileId;
  final List<ReconstructionResultFile> resultFiles;

  ReconstructionTaskResponse({
    required this.taskId,
    required this.title,
    this.algorithm,
    this.params = const {},
    required this.status,
    required this.progress,
    required this.currentStage,
    required this.errorMessage,
    this.visibility = 'private',
    this.hasVisibility = false,
    this.createdAt,
    this.updatedAt,
    this.startedAt,
    this.completedAt,
    this.previewImageId,
    this.previewIds = const [],
    this.inputFileIds = const [],
    this.resultFileId,
    this.resultFiles = const [],
  });

  factory ReconstructionTaskResponse.fromJson(Map<String, dynamic> json) {
    final params = Map<String, dynamic>.from(json['params'] as Map? ?? const {});
    final resultFiles = (json['result_files'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => ReconstructionResultFile.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList();
    return ReconstructionTaskResponse(
      taskId: (json['task_id'] ?? json['id'] ?? '').toString(),
      title: json['title'] as String? ?? '',
      algorithm: json['algorithm'] as String?,
      params: params,
      status: json['status'] as String? ?? '',
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      currentStage: json['current_stage'] as String? ?? '',
      errorMessage:
          (json['error_message'] ?? json['error'] ?? '').toString(),
      visibility: (json['visibility'] ?? params['visibility'] ?? 'private')
          .toString(),
      hasVisibility:
          json.containsKey('visibility') || params.containsKey('visibility'),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
      startedAt: DateTime.tryParse(json['started_at'] as String? ?? ''),
      completedAt: DateTime.tryParse(json['completed_at'] as String? ?? ''),
      previewImageId:
          (json['preview_image_id'] ??
                  params['preview_image_id'] ??
                  _firstString(json['preview_ids']) ??
                  _firstString(params['preview_ids']))
              ?.toString(),
      previewIds: _readStringList(json['preview_ids'] ?? params['preview_ids']),
      inputFileIds: _readStringList(
        json['image_ids'] ??
            json['input_file_ids'] ??
            json['file_ids'] ??
            json['input_ids'] ??
            params['image_ids'] ??
            params['input_file_ids'],
      ),
      resultFileId:
          (json['result_file_id'] ??
                  json['ply_id'] ??
                  _selectResultFileId(resultFiles))
              ?.toString(),
      resultFiles: resultFiles,
    );
  }

  static String? _firstString(Object? value) {
    if (value is List && value.isNotEmpty) return value.first?.toString();
    return null;
  }

  static List<String> _readStringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty && item != 'null')
        .toList();
  }

  static String? _selectResultFileId(List<ReconstructionResultFile> files) {
    return ReconstructionStatusResponse._selectResultFileId(files);
  }
}

class ReconstructionStartUploadedRequest {
  final List<String> imageFileIds;
  final Map<String, dynamic> params;
  final String? algorithm;
  final String inputType;

  ReconstructionStartUploadedRequest({
    required this.imageFileIds,
    required this.params,
    this.algorithm,
    this.inputType = 'image',
  });

  Map<String, dynamic> toJson() {
    return {
      'input_type': inputType,
      'input_file_ids': imageFileIds,
    };
  }
}

class ReconstructionMeshStartRequest {
  final List<String> inputFileIds;
  final Map<String, dynamic> params;
  final String algorithm;

  const ReconstructionMeshStartRequest({
    required this.inputFileIds,
    required this.params,
    this.algorithm = 'dash_gaussian_mesh',
  });

  Map<String, dynamic> toJson() {
    return {
      'algorithm': algorithm,
      'input_file_ids': inputFileIds,
      'params': params,
    };
  }
}

class Hunyuan3DStartRequest {
  final List<String> inputFileIds;
  final Map<String, dynamic> params;
  final String inputType;

  Hunyuan3DStartRequest({
    required this.inputFileIds,
    this.params = const {},
    this.inputType = 'image',
  });

  Map<String, dynamic> toJson() {
    return {
      'params': params,
      'input_type': inputType,
      'input_file_ids': inputFileIds,
    };
  }
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
          (json['input_file_count'] as num?)?.toInt() ??
          0,
      queueName: json['queue_name'] as String?,
      celeryTaskId: json['celery_task_id'] as String?,
    );
  }
}

class ReconstructionStatusResponse {
  final String taskId;
  final String title;
  final String status;
  final String? algorithm;
  final Map<String, dynamic> params;
  final List<String> inputFileIds;
  final String inputKind;
  final String visibility;
  final bool hasVisibility;
  final String? gaussianAlgorithm;
  final Map<String, dynamic> gaussianParams;
  final String? meshAlgorithm;
  final Map<String, dynamic> meshParams;
  final String? currentStage;
  final double? progress;
  final int? imageCount;
  final String? errorCode;
  final String? error;
  final String? resultFileId;
  final String? plyId;
  final List<ReconstructionResultFile> resultFiles;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ReconstructionStatusResponse({
    required this.taskId,
    this.title = '',
    required this.status,
    this.algorithm,
    this.params = const {},
    this.inputFileIds = const [],
    this.inputKind = '',
    this.visibility = 'private',
    this.hasVisibility = false,
    this.gaussianAlgorithm,
    this.gaussianParams = const {},
    this.meshAlgorithm,
    this.meshParams = const {},
    this.currentStage,
    this.progress,
    this.imageCount,
    this.errorCode,
    this.error,
    this.resultFileId,
    this.plyId,
    this.resultFiles = const [],
    this.createdAt,
    this.updatedAt,
  });

  factory ReconstructionStatusResponse.fromJson(Map<String, dynamic> json) {
    final resultFiles = (json['result_files'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => ReconstructionResultFile.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList();
    return ReconstructionStatusResponse(
      taskId: (json['task_id'] ?? '').toString(),
      title: json['title'] as String? ?? '',
      status: json['status'] as String? ?? '',
      algorithm: json['algorithm'] as String?,
      params: Map<String, dynamic>.from(json['params'] as Map? ?? const {}),
      inputFileIds: _readStringList(
        json['input_file_ids'] ??
            json['image_ids'] ??
            json['file_ids'] ??
            json['input_ids'],
      ),
      inputKind: (json['input_kind'] ?? json['input_type'] ?? '').toString(),
      visibility: (json['visibility'] ?? 'private').toString(),
      hasVisibility: json.containsKey('visibility'),
      gaussianAlgorithm: json['gaussian_algorithm'] as String?,
      gaussianParams: Map<String, dynamic>.from(
        json['gaussian_params'] as Map? ?? const {},
      ),
      meshAlgorithm: json['mesh_algorithm'] as String?,
      meshParams: Map<String, dynamic>.from(
        json['mesh_params'] as Map? ?? const {},
      ),
      currentStage: json['current_stage'] as String?,
      progress: (json['progress'] as num?)?.toDouble(),
      imageCount: (json['image_count'] as num?)?.toInt(),
      errorCode: (json['error_code'] ?? json['code'])?.toString(),
      error:
          (json['error'] ??
                  json['error_message'] ??
                  json['message'] ??
                  json['detail'])
              ?.toString(),
      resultFileId: (json['result_file_id'] ??
              json['ply_id'] ??
              _selectResultFileId(resultFiles))
          ?.toString(),
      plyId: json['ply_id']?.toString(),
      resultFiles: resultFiles,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
    );
  }

  static String? _selectResultFileId(List<ReconstructionResultFile> files) {
    if (files.isEmpty) return null;
    for (final file in files) {
      final category = file.category.toLowerCase();
      final type = file.fileType.toLowerCase();
      final filename = file.filename.toLowerCase();
      if (category.contains('model') ||
          type == 'model' ||
          filename.endsWith('.ply') ||
          filename.endsWith('.splat') ||
          filename.endsWith('.glb') ||
          filename.endsWith('.obj')) {
        return file.fileId;
      }
    }
    return files.first.fileId;
  }

  static List<String> _readStringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty && item != 'null')
        .toList();
  }
}

class ReconstructionResultFile {
  final String fileId;
  final String category;
  final String fileType;
  final String mimeType;
  final String filename;

  const ReconstructionResultFile({
    required this.fileId,
    required this.category,
    required this.fileType,
    required this.mimeType,
    required this.filename,
  });

  factory ReconstructionResultFile.fromJson(Map<String, dynamic> json) {
    return ReconstructionResultFile(
      fileId: (json['file_id'] ?? '').toString(),
      category: json['category'] as String? ?? '',
      fileType: json['file_type'] as String? ?? '',
      mimeType: json['mime_type'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
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

class ReconstructionDeleteResponse {
  final String taskId;
  final bool deleted;
  final String status;

  ReconstructionDeleteResponse({
    required this.taskId,
    required this.deleted,
    required this.status,
  });

  factory ReconstructionDeleteResponse.fromJson(Map<String, dynamic> json) {
    return ReconstructionDeleteResponse(
      taskId: (json['task_id'] ?? '').toString(),
      deleted: json['deleted'] as bool? ?? false,
      status: json['status'] as String? ?? '',
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
