import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/network/auth_service.dart';
import '../../core/network/reconstruction_service.dart';
import '../../core/network/upload_service.dart';
import '../../core/router/route_config.dart';
import '../../core/state/language_state.dart';
import '../../core/state/task_state.dart';
import '../../core/state/user_state.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  static final ImagePicker _picker = ImagePicker();
  static final UploadService _uploadService = UploadService();
  static final AuthService _authService = AuthService();
  static final ReconstructionService _downloadService = ReconstructionService();
  static final Set<String> _avatarDownloadKeys = <String>{};

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageState>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          context.tr('profile.title'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _buildUserInfoCard(context),
              const SizedBox(height: 24),
              _buildMenuItem(
                context,
                Icons.history,
                context.tr('profile.history'),
              ),
              _buildMenuItem(
                context,
                Icons.settings_outlined,
                context.tr('profile.settings'),
                onTap: () => _showLanguageSettings(context),
              ),
              _buildMenuItem(
                context,
                Icons.info_outline,
                context.tr('profile.about'),
              ),
              const SizedBox(height: 48),
              _buildLogoutButton(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserInfoCard(BuildContext context) {
    final userState = context.watch<UserState>();
    final user = userState.user;
    final displayName = user?.displayName ?? context.tr('profile.guest');
    final email = user?.email ?? '';
    unawaited(_ensureServerAvatar(userState));

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 0.8,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF).withValues(alpha: 0.05),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.1),
                  Colors.transparent,
                ],
              ),
            ),
            child: Row(
              children: [
                _AvatarButton(userState: userState),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: () => _pickAvatar(context),
                        icon: const Icon(Icons.photo_camera_outlined, size: 18),
                        label: Text(context.tr('profile.changeAvatar')),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF00C6FF),
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _pickAvatar(BuildContext context) async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );
      if (image == null) return;

      await UserState.instance.updateAvatarFromFile(image.path);
      final uploaded = await _uploadService.uploadFile(image.path);
      final avatar = await _authService.updateAvatar(uploaded.fileId);
      final originalPath = avatar.avatarFileId == null
          ? null
          : await _downloadAvatarFile(
              avatar.avatarFileId!,
              directoryName: 'avatar_originals',
            );
      final thumbPath = avatar.avatarThumbnailFileId == null
          ? null
          : await _downloadAvatarFile(
              avatar.avatarThumbnailFileId!,
              directoryName: 'avatar_thumbs',
            );
      await UserState.instance.updateAvatarFromServer(
        avatarFileId: avatar.avatarFileId,
        avatarThumbnailFileId: avatar.avatarThumbnailFileId,
        originalPath: originalPath,
        thumbPath: thumbPath,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('profile.avatarUploaded'))),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('profile.avatarFailed', args: {'message': e}),
          ),
        ),
      );
    }
  }

  Widget _buildMenuItem(
    BuildContext context,
    IconData icon,
    String title, {
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          leading: Icon(icon, color: Colors.white.withValues(alpha: 0.7)),
          title: Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          trailing: Icon(
            Icons.chevron_right,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          onTap: onTap ?? () => debugPrint('tap profile menu: $title'),
        ),
      ),
    );
  }

  void _showLanguageSettings(BuildContext context) {
    final language = context.read<LanguageState>();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0B1026),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('common.language'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _LanguageTile(
                  label: context.tr('common.chinese'),
                  selected: language.languageCode == 'zh',
                  onTap: () async {
                    await language.setLanguage('zh');
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
                _LanguageTile(
                  label: context.tr('common.english'),
                  selected: language.languageCode == 'en',
                  onTap: () async {
                    await language.setLanguage('en');
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return OutlinedButton(
      onPressed: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF0B1026),
            title: Text(context.tr('profile.logout')),
            content: Text(context.tr('profile.logoutConfirm')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(context.tr('common.cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  context.tr('profile.logout'),
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        if (!context.mounted) return;
        await context.read<TaskState>().clearTasks();
        await UserState.instance.logout();
        if (context.mounted) context.go(loginPath);
      },
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        context.tr('profile.logout'),
        style: const TextStyle(color: Colors.redAccent, fontSize: 16),
      ),
    );
  }

  static Future<void> _ensureServerAvatar(UserState userState) async {
    final user = userState.user;
    if (user == null) return;
    final thumbId = user.avatarThumbnailFileId;
    final originalId = user.avatarFileId;
    if ((thumbId == null || thumbId.isEmpty) &&
        (originalId == null || originalId.isEmpty)) {
      return;
    }

    final thumbPath = userState.avatarThumbPath;
    final originalPath = userState.avatarOriginalPath;
    final hasThumb = thumbPath != null &&
        File(thumbPath).existsSync() &&
        (thumbId == null || thumbPath.contains(thumbId));
    final hasOriginal = originalPath != null &&
        File(originalPath).existsSync() &&
        (originalId == null || originalPath.contains(originalId));
    if (hasThumb && hasOriginal) return;

    final key = '${user.id}:${thumbId ?? ''}:${originalId ?? ''}';
    if (!_avatarDownloadKeys.add(key)) return;
    try {
      final downloadedThumb = hasThumb
          ? thumbPath
          : thumbId == null
              ? null
              : await _downloadAvatarFile(
                  thumbId,
                  directoryName: 'avatar_thumbs',
                );
      final downloadedOriginal = hasOriginal
          ? originalPath
          : originalId == null
              ? null
              : await _downloadAvatarFile(
                  originalId,
                  directoryName: 'avatar_originals',
                );
      await userState.updateAvatarLocalPaths(
        originalPath: downloadedOriginal,
        thumbPath: downloadedThumb,
      );
    } catch (e) {
      debugPrint('[Profile] restore avatar failed: $e');
    } finally {
      _avatarDownloadKeys.remove(key);
    }
  }

  static Future<String?> _downloadAvatarFile(
    String fileId, {
    required String directoryName,
  }) async {
    final file = await _downloadService.downloadFile(
      fileId: fileId,
      outputDirectoryName: directoryName,
      saveFileName: fileId,
    );
    return file?.path;
  }
}

class _LanguageTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(color: Colors.white)),
      trailing: selected
          ? const Icon(Icons.check_rounded, color: Color(0xFF00C6FF))
          : null,
      onTap: onTap,
    );
  }
}

class _AvatarButton extends StatelessWidget {
  final UserState userState;

  const _AvatarButton({required this.userState});

  @override
  Widget build(BuildContext context) {
    final thumbPath = userState.avatarThumbPath;
    final thumbFile = thumbPath == null ? null : File(thumbPath);
    final hasThumb = thumbFile != null && thumbFile.existsSync();
    final thumbVersion = hasThumb
        ? thumbFile.statSync().modified.millisecondsSinceEpoch
        : 0;

    return GestureDetector(
      onTap: () async {
        var originalPath = userState.avatarOriginalPath;
        final originalFileId = userState.user?.avatarFileId;
        if ((originalPath == null || !File(originalPath).existsSync()) &&
            originalFileId != null &&
            originalFileId.isNotEmpty) {
          originalPath = await ProfilePage._downloadAvatarFile(
            originalFileId,
            directoryName: 'avatar_originals',
          );
          if (originalPath != null) {
            await userState.updateAvatarLocalPaths(originalPath: originalPath);
          }
        }
        if (!context.mounted) return;
        if (originalPath == null) {
          ProfilePage._pickAvatar(context);
          return;
        }
        _showOriginalAvatar(context, originalPath);
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: const Color(0xFF0072FF).withValues(alpha: 0.8),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0072FF).withValues(alpha: 0.3),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipOval(
              child: hasThumb
                  ? Image.file(
                      thumbFile,
                      key: ValueKey('$thumbPath:$thumbVersion'),
                      fit: BoxFit.cover,
                    )
                  : const Icon(Icons.person, size: 42, color: Colors.white),
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Material(
              color: const Color(0xFF00C6FF),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => ProfilePage._pickAvatar(context),
                child: const SizedBox(
                  width: 28,
                  height: 28,
                  child: Icon(
                    Icons.edit_outlined,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showOriginalAvatar(BuildContext context, String originalPath) {
    final file = File(originalPath);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('profile.avatarMissing'))),
      );
      return;
    }

    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.6,
                  maxScale: 5,
                  child: Center(
                    child: Image.file(file, fit: BoxFit.contain),
                  ),
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: SafeArea(
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
