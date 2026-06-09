class FileResponse {
  final int id;
  final String filename;
  final String fileHash;
  final int fileSize;
  final String mimeType;
  final String category;
  final DateTime createdAt;
  final String storageKey;

  FileResponse({
    required this.id,
    required this.filename,
    required this.fileHash,
    required this.fileSize,
    required this.mimeType,
    required this.category,
    required this.createdAt,
    required this.storageKey,
  });

  factory FileResponse.fromJson(Map<String, dynamic> json) => FileResponse(
    id: json['id'],
    filename: json['filename'],
    fileHash: json['file_hash'],
    fileSize: json['file_size'],
    mimeType: json['mime_type'],
    category: json['category'],
    createdAt: DateTime.parse(json['created_at']),
    storageKey: json['storage_key'],
  );
}

class FileListResponse {
  final List<FileResponse> items;
  final int total;

  FileListResponse({required this.items, required this.total});

  factory FileListResponse.fromJson(Map<String, dynamic> json) => FileListResponse(
    items: (json['items'] as List).map((i) => FileResponse.fromJson(i)).toList(),
    total: json['total'],
  );
}

class FileUrlResponse {
  final String url;
  final DateTime expiresAt;

  FileUrlResponse({required this.url, required this.expiresAt});

  factory FileUrlResponse.fromJson(Map<String, dynamic> json) => FileUrlResponse(
    url: json['url'],
    expiresAt: DateTime.parse(json['expires_at']),
  );
}
