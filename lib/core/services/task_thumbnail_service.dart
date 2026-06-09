import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../network/download_models.dart';
import '../network/download_service.dart';
import '../network/reconstruction_models.dart';
import '../network/reconstruction_service.dart';
import '../state/task_state.dart';
import 'session_prefetch_service.dart';

class TaskThumbnailService {
  TaskThumbnailService._();

  static final TaskThumbnailService instance = TaskThumbnailService._();

  final DownloadService _downloadService = DownloadService();
  final ReconstructionService _reconstructionService = ReconstructionService();

  Future<File?> resolveForRemoteTask(
    ReconstructionTaskResponse task, {
    String outputDirectoryName = SessionPrefetchService.taskThumbnailDirectory,
  }) async {
    return resolveFromFileIds(
      taskId: task.taskId,
      previewFileId: task.previewImageId,
      previewFileIds: task.previewIds,
      inputFileIds: task.inputFileIds,
      outputDirectoryName: outputDirectoryName,
    );
  }

  Future<File?> resolveFromFileIds({
    required String taskId,
    String? previewFileId,
    Object? previewFileIds,
    Object? inputFileIds,
    String outputDirectoryName = SessionPrefetchService.taskThumbnailDirectory,
  }) async {
    final candidateIds = <String>[
      ..._previewIds(previewFileId, previewFileIds),
      ..._inputIds(inputFileIds),
    ];
    if (candidateIds.isEmpty && taskId.trim().isNotEmpty) {
      final detail = await _reconstructionService.getTaskDetail(taskId);
      if (detail != null) {
        final detailCandidateIds = <String>[
          ..._previewIds(detail.previewImageId, detail.previewIds),
          ..._inputIds(detail.inputFileIds),
        ];
        return _resolveCandidates(
          detailCandidateIds,
          taskId: taskId,
          outputDirectoryName: outputDirectoryName,
        );
      }
    }
    return _resolveCandidates(
      candidateIds,
      taskId: taskId,
      outputDirectoryName: outputDirectoryName,
    );
  }

  Future<File?> resolveForPublicTask(
    PublicReconstructionTask task, {
    String outputDirectoryName = 'discover_previews',
  }) async {
    var candidateIds = <String>[
      ..._previewIds(task.previewFileId, task.previewFileIds),
      ..._inputIds(task.inputFileIds),
    ];

    if (candidateIds.isEmpty && task.taskId.trim().isNotEmpty) {
      final detail = await _reconstructionService.getTaskDetail(task.taskId);
      if (detail != null) {
        candidateIds = <String>[
          ..._previewIds(detail.previewImageId, detail.previewIds),
          ..._inputIds(detail.inputFileIds),
        ];
      }
    }

    return _resolveCandidates(
      candidateIds,
      taskId: task.taskId,
      outputDirectoryName: outputDirectoryName,
    );
  }

  Future<File?> resolveForLocalTask(
    ProcessingTask? task, {
    String outputDirectoryName = SessionPrefetchService.taskThumbnailDirectory,
  }) async {
    if (task == null) return null;
    final localPath = localThumbnailPath(task);
    if (localPath != null) {
      final file = File(localPath);
      if (await file.exists()) return file;
    }

    final candidateIds = <String>[
      ..._previewIds(
        task.params['preview_image_id']?.toString(),
        task.params['preview_ids'],
      ),
      ..._inputIds(task.params['input_file_ids']),
      ...task.files.map((file) => file.fileId),
    ];
    return _resolveCandidates(
      candidateIds,
      taskId: task.taskId,
      outputDirectoryName: outputDirectoryName,
    );
  }

  String? localThumbnailPath(ProcessingTask task) {
    for (final file in task.files) {
      final path = file.localPath;
      if (path == null || path.isEmpty) continue;
      if (_isImagePath(path) && File(path).existsSync()) return path;
    }
    final thumbnails = task.params['video_thumbnail_paths'];
    if (thumbnails is List) {
      for (final item in thumbnails) {
        if (item is! String || item.isEmpty) continue;
        if (File(item).existsSync()) return item;
      }
    }
    return null;
  }

  Future<File?> _resolveCandidates(
    List<String> candidateIds, {
    required String taskId,
    required String outputDirectoryName,
  }) async {
    final seen = <String>{};
    for (final rawId in candidateIds) {
      final fileId = _cleanFileId(rawId);
      if (fileId == null || !seen.add(fileId)) continue;
      final cached = await _cachedResolvedFile(
        fileId,
        outputDirectoryName: outputDirectoryName,
      );
      if (cached != null) return cached;

      try {
        final resolved = await _downloadAndResolveFile(
          fileId,
          outputDirectoryName: outputDirectoryName,
        );
        if (resolved != null) return resolved;
      } catch (e) {
        debugPrint(
          '[Thumbnail] candidate failed taskId=$taskId fileId=$fileId error=$e',
        );
      }
    }
    return null;
  }

  Future<File?> _cachedResolvedFile(
    String fileId, {
    required String outputDirectoryName,
  }) async {
    final directory = await _cacheDirectory(outputDirectoryName);
    final videoThumb = File(p.join(directory.path, '${fileId}_thumb.jpg'));
    if (await videoThumb.exists()) return videoThumb;

    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name == fileId || name.startsWith('$fileId.')) {
        if (_isImagePath(entity.path)) return entity;
        if (_isVideoPath(entity.path)) {
          return _videoThumbnailFromFile(
            fileId: fileId,
            videoFile: entity,
            directory: directory,
          );
        }
      }
    }
    return null;
  }

  Future<File?> _downloadAndResolveFile(
    String fileId, {
    required String outputDirectoryName,
  }) async {
    final directory = await _cacheDirectory(outputDirectoryName);
    final info = await _downloadService.getFileInfo(fileId);
    final extension = _extensionForInfo(info);
    final saveFileName = extension.isEmpty ? fileId : '$fileId$extension';
    final result = await _downloadService.downloadFile(
      fileId,
      saveDirectory: directory.path,
      saveFileName: saveFileName,
      fetchInfo: false,
    );
    final file = result.file;
    if (_isImageInfo(info) || _isImagePath(file.path)) {
      debugPrint('[Thumbnail] resolved image fileId=$fileId path=${file.path}');
      return file;
    }
    if (_isVideoInfo(info) || _isVideoPath(file.path)) {
      return _videoThumbnailFromFile(
        fileId: fileId,
        videoFile: file,
        directory: directory,
      );
    }
    debugPrint(
      '[Thumbnail] unsupported thumbnail source fileId=$fileId '
      'filename=${info.filename} mime=${info.mimeType}',
    );
    return null;
  }

  Future<File?> _videoThumbnailFromFile({
    required String fileId,
    required File videoFile,
    required Directory directory,
  }) async {
    final target = File(p.join(directory.path, '${fileId}_thumb.jpg'));
    if (await target.exists()) return target;
    final thumbPath = await VideoThumbnail.thumbnailFile(
      video: videoFile.path,
      thumbnailPath: directory.path,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 720,
      quality: 82,
    );
    if (thumbPath == null || thumbPath.isEmpty) return null;
    final generated = File(thumbPath);
    if (!await generated.exists()) return null;
    await generated.copy(target.path);
    debugPrint(
      '[Thumbnail] resolved video frame fileId=$fileId path=${target.path}',
    );
    return target;
  }

  Future<Directory> _cacheDirectory(String outputDirectoryName) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, outputDirectoryName));
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  List<String> _previewIds(String? direct, Object? list) {
    return [
      if (_cleanFileId(direct) != null) _cleanFileId(direct)!,
      ..._inputIds(list),
    ];
  }

  List<String> _inputIds(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty && item != 'null')
        .toList();
  }

  String? _cleanFileId(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  String _extensionForInfo(DownloadFileInfo info) {
    final extension = p.extension(info.filename).toLowerCase();
    if (extension.isNotEmpty) return extension;
    final originalExtension = p.extension(info.originalName).toLowerCase();
    if (originalExtension.isNotEmpty) return originalExtension;
    if (info.mimeType.startsWith('image/jpeg')) return '.jpg';
    if (info.mimeType.startsWith('image/png')) return '.png';
    if (info.mimeType.startsWith('image/webp')) return '.webp';
    if (info.mimeType.startsWith('video/mp4')) return '.mp4';
    if (info.mimeType.startsWith('video/quicktime')) return '.mov';
    return '';
  }

  bool _isImageInfo(DownloadFileInfo info) {
    return info.mimeType.startsWith('image/') ||
        _isImagePath(info.filename) ||
        _isImagePath(info.originalName);
  }

  bool _isVideoInfo(DownloadFileInfo info) {
    return info.mimeType.startsWith('video/') ||
        _isVideoPath(info.filename) ||
        _isVideoPath(info.originalName);
  }

  bool _isImagePath(String path) {
    final extension = p.extension(path).toLowerCase().replaceFirst('.', '');
    return const {'jpg', 'jpeg', 'png', 'webp'}.contains(extension);
  }

  bool _isVideoPath(String path) {
    final extension = p.extension(path).toLowerCase().replaceFirst('.', '');
    return const {'mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm'}.contains(extension);
  }
}
