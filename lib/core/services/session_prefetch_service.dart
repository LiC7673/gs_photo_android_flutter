import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../network/auth_service.dart';
import '../network/reconstruction_models.dart';
import '../network/reconstruction_service.dart';
import '../state/user_state.dart';

class SessionPrefetchService {
  SessionPrefetchService._();

  static final SessionPrefetchService instance = SessionPrefetchService._();

  final AuthService _authService = AuthService();
  final ReconstructionService _reconstructionService = ReconstructionService();
  bool _running = false;

  static const String avatarThumbDirectory = 'avatar_thumbs';
  static const String avatarOriginalDirectory = 'avatar_originals';
  static const String taskThumbnailDirectory = 'task_card_thumbnails';

  Future<void> start({bool refreshUser = true}) async {
    if (_running) return;
    _running = true;
    try {
      final userState = UserState.instance;
      if (!userState.isLoggedIn) return;

      if (refreshUser) {
        try {
          final user = await _authService.fetchCurrentUser();
          await userState.updateUser(user);
        } catch (e) {
          debugPrint('[Prefetch] refresh user failed: $e');
        }
      }

      await _prefetchAvatar(userState);
      await _prefetchTaskThumbnails();
    } catch (e) {
      debugPrint('[Prefetch] session prefetch failed: $e');
    } finally {
      _running = false;
    }
  }

  Future<void> _prefetchAvatar(UserState userState) async {
    final user = userState.user;
    if (user == null) return;

    final thumbId = _cleanFileId(user.avatarThumbnailFileId);
    final originalId = _cleanFileId(user.avatarFileId);

    final thumbPath = thumbId == null
        ? null
        : await getCachedFilePath(
            thumbId,
            outputDirectoryName: avatarThumbDirectory,
          );
    final originalPath = originalId == null
        ? null
        : await getCachedFilePath(
            originalId,
            outputDirectoryName: avatarOriginalDirectory,
          );

    final hasThumb = thumbPath != null && await File(thumbPath).exists();
    final hasOriginal =
        originalPath != null && await File(originalPath).exists();

    final downloadedThumb = hasThumb
        ? thumbPath
        : thumbId == null
            ? null
            : (await _reconstructionService.downloadFile(
                fileId: thumbId,
                outputDirectoryName: avatarThumbDirectory,
                saveFileName: thumbId,
              ))
                ?.path;
    final downloadedOriginal = hasOriginal
        ? originalPath
        : originalId == null
            ? null
            : (await _reconstructionService.downloadFile(
                fileId: originalId,
                outputDirectoryName: avatarOriginalDirectory,
                saveFileName: originalId,
              ))
                ?.path;

    await userState.updateAvatarFromServer(
      avatarFileId: originalId,
      avatarThumbnailFileId: thumbId,
      originalPath: downloadedOriginal,
      thumbPath: downloadedThumb,
    );
  }

  Future<void> _prefetchTaskThumbnails() async {
    final tasks = await _reconstructionService.listTasks();
    final orderedTasks = List<ReconstructionTaskResponse>.from(tasks)
      ..sort((a, b) => _taskTime(b).compareTo(_taskTime(a)));

    final seenFileIds = <String>{};
    for (final task in orderedTasks) {
      final fileId = _thumbnailFileId(task);
      if (fileId == null || !seenFileIds.add(fileId)) continue;
      final cachedPath = await getCachedFilePath(
        fileId,
        outputDirectoryName: taskThumbnailDirectory,
      );
      if (await File(cachedPath).exists()) continue;
      try {
        await _reconstructionService.downloadFile(
          fileId: fileId,
          outputDirectoryName: taskThumbnailDirectory,
          saveFileName: fileId,
        );
      } catch (e) {
        debugPrint('[Prefetch] task thumbnail failed fileId=$fileId error=$e');
      }
    }
  }

  static Future<File?> cachedFile(
    String fileId, {
    required String outputDirectoryName,
  }) async {
    final path = await getCachedFilePath(
      fileId,
      outputDirectoryName: outputDirectoryName,
    );
    final file = File(path);
    if (!await file.exists()) return null;
    return file;
  }

  static Future<String> getCachedFilePath(
    String fileId, {
    required String outputDirectoryName,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    return p.join(directory.path, outputDirectoryName, p.basename(fileId));
  }

  static String? _thumbnailFileId(ReconstructionTaskResponse task) {
    final direct = _cleanFileId(task.previewImageId);
    if (direct != null) return direct;
    for (final previewId in task.previewIds) {
      final clean = _cleanFileId(previewId);
      if (clean != null) return clean;
    }
    return null;
  }

  static String? _cleanFileId(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  static DateTime _taskTime(ReconstructionTaskResponse task) {
    return task.updatedAt ??
        task.createdAt ??
        task.startedAt ??
        task.completedAt ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }
}
