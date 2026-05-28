class UploadInitRequest {
  final String filename;
  final int fileSize;
  final int chunkSize;
  final String mimeType;
  final String fileHash;

  UploadInitRequest({
    required this.filename,
    required this.fileSize,
    required this.chunkSize,
    required this.mimeType,
    required this.fileHash,
  });

  Map<String, dynamic> toJson() => {
    'filename': filename,
    'file_size': fileSize,
    'chunk_size': chunkSize,
    'mime_type': mimeType,
    'file_hash': fileHash,
  };
}

class UploadInitResponse {
  final String uploadId;
  final int chunkSize;
  final int totalChunks;
  final DateTime expiresAt;

  UploadInitResponse({
    required this.uploadId,
    required this.chunkSize,
    required this.totalChunks,
    required this.expiresAt,
  });

  factory UploadInitResponse.fromJson(Map<String, dynamic> json) =>
      UploadInitResponse(
        uploadId: json['upload_id'],
        chunkSize: json['chunk_size'],
        totalChunks: json['total_chunks'],
        expiresAt: DateTime.parse(json['expires_at']),
      );
  Map<String, dynamic> toJson() => {
    'upload_id': uploadId,
    'chunk_size': chunkSize,
    'total_chunks': totalChunks,
    // 注意：DateTime 类型必须转成字符串（推荐 ISO8601 格式），否则 jsonEncode 依然会报错
    'expires_at': expiresAt.toIso8601String(),
  };
}

class ChunkResponse {
  final bool received;
  final int chunkIndex;
  final String etag;

  ChunkResponse({
    required this.received,
    required this.chunkIndex,
    required this.etag,
  });

  factory ChunkResponse.fromJson(Map<String, dynamic> json) => ChunkResponse(
    received: json['received'],
    chunkIndex: json['chunk_index'],
    etag: json['etag'],
  );
}

class UploadProgressResponse {
  final String uploadId;
  final String filename;
  final int fileSize;
  final int totalChunks;
  final int receivedChunks;
  final String status;
  final List<int> chunkStatuses;

  UploadProgressResponse({
    required this.uploadId,
    required this.filename,
    required this.fileSize,
    required this.totalChunks,
    required this.receivedChunks,
    required this.status,
    required this.chunkStatuses,
  });

  factory UploadProgressResponse.fromJson(Map<String, dynamic> json) =>
      UploadProgressResponse(
        uploadId: json['upload_id'],
        filename: json['filename'],
        fileSize: json['file_size'],
        totalChunks: json['total_chunks'],
        receivedChunks: json['received_chunks'],
        status: json['status'],
        chunkStatuses: List<int>.from(json['chunk_statuses']),
      );
}

class MergeRequestPart {
  final int chunkIndex;
  final String etag;

  MergeRequestPart({required this.chunkIndex, required this.etag});

  Map<String, dynamic> toJson() => {'chunk_index': chunkIndex, 'etag': etag};
}

class MergeRequest {
  final String? expectedHash;
  final int expectedSize;
  final List<MergeRequestPart> parts;

  MergeRequest({
    this.expectedHash,
    required this.expectedSize,
    required this.parts,
  });

  Map<String, dynamic> toJson() => {
    if (expectedHash != null) 'expected_hash': expectedHash,
    'expected_size': expectedSize,
    'parts': parts.map((e) => e.toJson()).toList(),
  };
}

class MergeResponse {
  final String fileId;
  final String fileHash;
  final String storageKey;
  final bool verified;

  MergeResponse({
    required this.fileId,
    required this.fileHash,
    required this.storageKey,
    required this.verified,
  });

  factory MergeResponse.fromJson(Map<String, dynamic> json) => MergeResponse(
    fileId: json['file_id'],
    fileHash: json['file_hash'],
    storageKey: json['storage_key'],
    verified: json['verified'],
  );
}
