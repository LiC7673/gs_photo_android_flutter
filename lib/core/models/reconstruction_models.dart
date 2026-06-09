class AlgorithmResponse {
  final String name;
  final String description;
  final Map<String, dynamic> defaultParams;

  AlgorithmResponse({
    required this.name,
    required this.description,
    required this.defaultParams,
  });

  factory AlgorithmResponse.fromJson(Map<String, dynamic> json) => AlgorithmResponse(
    name: json['name'],
    description: json['description'],
    defaultParams: json['default_params'] ?? {},
  );
}

class ReconstructionStartResponse {
  final String taskId;
  final String status;

  ReconstructionStartResponse({required this.taskId, required this.status});

  factory ReconstructionStartResponse.fromJson(Map<String, dynamic> json) => ReconstructionStartResponse(
    taskId: json['task_id'],
    status: json['status'],
  );
}

class ReconstructionStatusResponse {
  final String taskId;
  final String status;
  final double progress;
  final String? resultUrl;
  final DateTime? completedAt;

  ReconstructionStatusResponse({
    required this.taskId,
    required this.status,
    required this.progress,
    this.resultUrl,
    this.completedAt,
  });

  factory ReconstructionStatusResponse.fromJson(Map<String, dynamic> json) => ReconstructionStatusResponse(
    taskId: json['task_id'],
    status: json['status'],
    progress: (json['progress'] ?? 0.0).toDouble(),
    resultUrl: json['result_url'],
    completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at']) : null,
  );
}

class ReconstructionLogsResponse {
  final List<String> logs;
  final int totalLines;

  ReconstructionLogsResponse({required this.logs, required this.totalLines});

  factory ReconstructionLogsResponse.fromJson(Map<String, dynamic> json) => ReconstructionLogsResponse(
    logs: List<String>.from(json['logs']),
    totalLines: json['total_lines'],
  );
}
