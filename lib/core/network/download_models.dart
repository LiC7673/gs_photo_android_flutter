import 'dart:io';

class DownloadFileInfo {
  final String fileId;
  final int userId;
  final String? taskId;
  final String filename;
  final String originalName;
  final String category;
  final String mimeType;
  final int fileSize;
  final String fileHash;
  final String storageKey;
  final bool isArchived;
  final int downloadCount;
  final DateTime? createdAt;

  DownloadFileInfo({
    required this.fileId,
    required this.userId,
    this.taskId,
    required this.filename,
    required this.originalName,
    required this.category,
    required this.mimeType,
    required this.fileSize,
    required this.fileHash,
    required this.storageKey,
    required this.isArchived,
    required this.downloadCount,
    this.createdAt,
  });

  factory DownloadFileInfo.fromJson(Map<String, dynamic> json) {
    return DownloadFileInfo(
      fileId: (json['id'] ?? json['file_id'] ?? '').toString(),
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      taskId: json['task_id']?.toString(),
      filename: json['filename'] as String? ?? '',
      originalName: json['original_name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      mimeType: json['mime_type'] as String? ?? '',
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      fileHash: json['file_hash'] as String? ?? '',
      storageKey: json['storage_key'] as String? ?? '',
      isArchived: json['is_archived'] as bool? ?? false,
      downloadCount: (json['download_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }
}

class DownloadUrlResponse {
  final String fileId;
  final String url;
  final int expiresIn;

  DownloadUrlResponse({
    required this.fileId,
    required this.url,
    required this.expiresIn,
  });

  factory DownloadUrlResponse.fromJson(Map<String, dynamic> json) {
    return DownloadUrlResponse(
      fileId: (json['file_id'] ?? '').toString(),
      url: json['url'] as String? ?? '',
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 3600,
    );
  }
}

class DownloadFileResult {
  final String fileId;
  final String url;
  final String localPath;
  final int receivedBytes;
  final int totalBytes;
  final DownloadFileInfo? info;

  DownloadFileResult({
    required this.fileId,
    required this.url,
    required this.localPath,
    required this.receivedBytes,
    required this.totalBytes,
    this.info,
  });

  File get file => File(localPath);
}

class DownloadHookEvent {
  final String name;
  final String? fileId;
  final Map<String, dynamic> payload;

  DownloadHookEvent({
    required this.name,
    this.fileId,
    this.payload = const {},
  });
}

typedef DownloadHook = void Function(DownloadHookEvent event);
