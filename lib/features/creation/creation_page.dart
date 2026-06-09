import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/network/reconstruction_models.dart';
import '../../core/network/reconstruction_service.dart';
import '../../core/router/route_config.dart';
import '../../core/state/language_state.dart';
import '../../core/state/task_state.dart';
import '../../core/utils/video_metadata.dart';
import '../../core/widgets/background/sci_fi_background.dart';
import '../../core/widgets/buttons/gradient_button.dart';
import '../camera/camera_guide_screen.dart';

class CreationPage extends StatefulWidget {
  const CreationPage({super.key});

  @override
  State<CreationPage> createState() => _CreationPageState();
}

class _CreationPageState extends State<CreationPage> {
  final TextEditingController _taskNameController = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  final ReconstructionService _reconstructionService = ReconstructionService();
  final List<XFile> _selectedImages = [];
  final List<String> _selectedVideoPaths = [];
  final List<String> _selectedVideoThumbnailPaths = [];
  String? _lastQualityReportPath;

  String _selectedAlgorithm = 'anysplat';
  bool _showAlgorithmParams = false;
  bool _loadingAlgorithms = true;
  bool _isPublicTask = false;
  final Map<String, TextEditingController> _paramControllers = {};
  final Map<String, bool> _boolParamValues = {};
  Set<String>? _availableAlgorithmNames;

  @override
  void initState() {
    super.initState();
    _syncParamControllers(_selectedAlgorithm);
    unawaited(_loadAlgorithms());
  }

  @override
  void dispose() {
    _taskNameController.dispose();
    for (final controller in _paramControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAlgorithms() async {
    final response = await _reconstructionService.listAlgorithms().timeout(
      const Duration(seconds: 3),
      onTimeout: () => null,
    );
    if (!mounted) return;

    final availableAlgorithms = response?.algorithms
        .where((algorithm) => algorithm.available && algorithm.name.isNotEmpty)
        .map((algorithm) => algorithm.name)
        .toSet();
    if (availableAlgorithms == null || availableAlgorithms.isEmpty) {
      setState(() => _loadingAlgorithms = false);
      return;
    }

    final defaultAlgorithm = response?.defaultAlgorithm;
    final knownAlgorithms = _algorithmOptions
        .where((option) => option.enabled)
        .map((option) => option.algorithm)
        .toSet();
    final selected =
        defaultAlgorithm != null &&
            knownAlgorithms.contains(defaultAlgorithm) &&
            availableAlgorithms.contains(defaultAlgorithm)
        ? defaultAlgorithm
        : _selectedAlgorithm;

    setState(() {
      _availableAlgorithmNames = availableAlgorithms;
      _selectedAlgorithm = selected;
      _loadingAlgorithms = false;
    });
    _syncParamControllers(selected);
  }

  Future<void> _pickFromGallery() async {
    final images = await _picker.pickMultiImage();
    if (images.isEmpty || !mounted) return;
    setState(() => _selectedImages.addAll(images));
  }

  void _removeImage(int index) {
    setState(() => _selectedImages.removeAt(index));
  }

  void _removeVideo(int index) {
    setState(() {
      if (index < _selectedVideoPaths.length) {
        _selectedVideoPaths.removeAt(index);
      }
      if (index < _selectedVideoThumbnailPaths.length) {
        _selectedVideoThumbnailPaths.removeAt(index);
      }
    });
  }

  CameraGuideArgs _buildGuideArgs() {
    final taskName = _taskNameController.text.trim().isEmpty
        ? context.tr('creation.defaultTaskName')
        : _taskNameController.text.trim();
    final params = _buildTaskParams(taskName);
    params['visibility'] = _isPublicTask ? 'public' : 'private';

    return CameraGuideArgs(
      taskName: taskName,
      params: params,
      initialImages: List<XFile>.from(_selectedImages),
    );
  }

  Future<void> _openPhotoGuide(BuildContext context) async {
    final result = await context.push<CameraGuideResult>(
      '$homeTabPath/$cameraGuidePath',
      extra: _buildGuideArgs().copyWith(mode: CameraGuideMode.photo),
    );
    if (!mounted || result == null) return;
    setState(() {
      _selectedImages
        ..clear()
        ..addAll(result.images);
    });
  }

  Future<void> _openVideoGuide(BuildContext context) async {
    final args = _buildGuideArgs();
    final result = await context.push<CameraGuideResult>(
      '$homeTabPath/$videoCameraGuidePath',
      extra: CameraGuideArgs(
        taskName: args.taskName,
        params: args.params,
        mode: CameraGuideMode.video,
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _selectedVideoPaths
        ..clear()
        ..addAll(result.videoPaths);
      _selectedVideoThumbnailPaths
        ..clear()
        ..addAll(result.videoThumbnailPaths);
      _lastQualityReportPath = result.reportPath;
    });
  }

  Future<void> _createTask(BuildContext context) async {
    final validationError = await _validateUploadInputs();
    if (validationError != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validationError)));
      return;
    }

    final taskId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final taskName = _taskNameController.text.trim().isEmpty
        ? context.tr('creation.defaultTaskName')
        : _taskNameController.text.trim();
    final params = _buildTaskParams(taskName);
    params['visibility'] = _isPublicTask ? 'public' : 'private';
    if (_selectedVideoPaths.isNotEmpty) {
      params['video_paths'] = List<String>.from(_selectedVideoPaths);
    }
    if (_selectedVideoThumbnailPaths.isNotEmpty) {
      params['video_thumbnail_paths'] = List<String>.from(
        _selectedVideoThumbnailPaths,
      );
    }
    if (_lastQualityReportPath != null) {
      params['quality_report_path'] = _lastQualityReportPath;
    }
    final imageFiles = _selectedImages.map((image) {
      final file = File(image.path);
      return StorageFile(
        fileId: image.name.isNotEmpty ? image.name : image.path,
        localPath: image.path,
        status: FileSyncStatus.localOnly,
        md5: '',
        size: file.existsSync() ? file.lengthSync() : 0,
      );
    }).toList();
    final videoFiles = _selectedVideoPaths.map((videoPath) {
      final file = File(videoPath);
      return StorageFile(
        fileId: videoPath.split(Platform.pathSeparator).last,
        localPath: videoPath,
        status: FileSyncStatus.localOnly,
        md5: '',
        size: file.existsSync() ? file.lengthSync() : 0,
      );
    }).toList();

    context.read<TaskState>().upsertTask(
      ProcessingTask(
        taskId: taskId,
        title: taskName,
        params: params,
        files: [...imageFiles, ...videoFiles],
        status: TaskStatus.draft,
        visibility: _isPublicTask ? 'public' : 'private',
        stage: 'Waiting to start',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    context.go(
      '$taskTabPath/$taskDetailPath/${Uri.encodeComponent(taskId)}',
      extra: {
        'images': List<XFile>.from(_selectedImages),
        'videos': List<String>.from(_selectedVideoPaths),
      },
    );
  }

  Future<String?> _validateUploadInputs() async {
    final imageCount = _selectedImages.length;
    final videoPaths = List<String>.from(_selectedVideoPaths);

    if (imageCount == 0 && videoPaths.isEmpty) {
      return context.tr('creation.validation.empty');
    }

    if (imageCount >= 6) return null;

    if (videoPaths.isEmpty) {
      return context.tr('creation.validation.needImages');
    }

    for (final videoPath in videoPaths) {
      if (!File(videoPath).existsSync()) {
        return context.tr(
          'creation.validation.videoMissing',
          args: {'file': videoPath.split(Platform.pathSeparator).last},
        );
      }
      final frameCount = await VideoMetadata.frameCount(videoPath);
      if (frameCount == null) {
        return context.tr('creation.validation.videoUnreadable');
      }
      if (frameCount <= 6) {
        return context.tr(
          'creation.validation.videoShort',
          args: {'count': frameCount},
        );
      }
    }

    return null;
  }

  Map<String, dynamic> _buildTaskParams(String taskName) {
    final params = _buildAlgorithmParams(_selectedAlgorithm);
    params['algorithm'] = _selectedAlgorithm;
    params['task_name'] = taskName;
    return params;
  }

  Map<String, dynamic> _buildAlgorithmParams(String algorithm) {
    final option = _algorithmOptionFor(algorithm);
    final params = <String, dynamic>{};
    for (final spec in option.params) {
      if (spec.type == _AlgorithmParamType.boolean) {
        params[spec.key] = _boolParamValues[spec.key] ?? spec.defaultValue;
        continue;
      }
      final text = _paramControllers[spec.key]?.text.trim() ?? '';
      params[spec.key] = spec.parse(text);
    }
    return params;
  }

  void _selectAlgorithm(String algorithm) {
    if (_selectedAlgorithm == algorithm) return;
    setState(() {
      _selectedAlgorithm = algorithm;
      _syncParamControllers(algorithm);
    });
  }

  void _syncParamControllers(String algorithm) {
    final option = _algorithmOptionFor(algorithm);
    for (final spec in option.params) {
      if (spec.type == _AlgorithmParamType.boolean) {
        _boolParamValues[spec.key] = spec.defaultValue == true;
        continue;
      }
      final controller = _paramControllers.putIfAbsent(
        spec.key,
        () => TextEditingController(),
      );
      controller.text = spec.defaultText;
    }
  }

  _AlgorithmOption _algorithmOptionFor(String algorithm) {
    return _algorithmOptions.firstWhere(
      (option) => option.algorithm == algorithm,
      orElse: () => _algorithmOptions.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageState>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          context.tr('creation.title'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => context.go(homeTabPath),
        ),
      ),
      body: SciFiBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle(context.tr('creation.taskName')),
                _buildGlassCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: TextField(
                    controller: _taskNameController,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: context.tr('creation.taskNameHint'),
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                      border: InputBorder.none,
                      icon: const Icon(
                        Icons.edit_note,
                        color: Color(0xFF00C6FF),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionTitle(context.tr('creation.reconstruction')),
                _buildAlgorithmPanel(),
                const SizedBox(height: 12),
                _buildVisibilityPanel(),
                const SizedBox(height: 24),
                _buildSectionTitle(
                  context.tr(
                    'creation.images',
                    args: {'count': _selectedImages.length},
                  ),
                ),
                _buildGlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: [
                          Row(
                            children: [
                              _buildActionButton(
                                context.tr('creation.gallery'),
                                Icons.photo_library_outlined,
                                _pickFromGallery,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _buildActionButton(
                                context.tr('creation.photoGuide'),
                                Icons.camera_alt_outlined,
                                () => _openPhotoGuide(context),
                              ),
                              const SizedBox(width: 12),
                              _buildActionButton(
                                context.tr('creation.videoGuide'),
                                Icons.videocam_outlined,
                                () => _openVideoGuide(context),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (_selectedVideoPaths.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          context.tr(
                            'creation.videoSaved',
                            args: {'count': _selectedVideoPaths.length},
                          ),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      if (_selectedImages.isNotEmpty ||
                          _selectedVideoPaths.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 96,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _selectedImages.length +
                                _selectedVideoPaths.length,
                            itemBuilder: (context, index) {
                              if (index < _selectedImages.length) {
                                return _buildImageThumbnail(index);
                              }
                              return _buildVideoThumbnail(
                                index - _selectedImages.length,
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                GradientButton(
                  label: context.tr('creation.start'),
                  onPressed: () => _createTask(context),
                  height: 56,
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildGlassCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.symmetric(
      horizontal: 20,
      vertical: 16,
    ),
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: padding,
            color: const Color(0xFFFFFFFF).withValues(alpha: 0.05),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildAlgorithmPanel() {
    final option = _algorithmOptionFor(_selectedAlgorithm);
    return _buildGlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildAlgorithmSelector(),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: () {
                  setState(() => _showAlgorithmParams = !_showAlgorithmParams);
                },
                icon: Icon(
                  _showAlgorithmParams
                      ? Icons.keyboard_arrow_up
                      : Icons.tune,
                  size: 18,
                ),
                label: Text(
                  _showAlgorithmParams
                      ? context.tr('creation.params.collapse')
                      : context.tr('creation.params.expand'),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF00C6FF),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _algorithmSummary(context, option),
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: _showAlgorithmParams
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(height: 8),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 18),
              child: option.params.isEmpty
                  ? Text(
                      context.tr('creation.params.empty'),
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                      ),
                    )
                  : Column(
                      children: [
                        for (var index = 0;
                            index < option.params.length;
                            index++) ...[
                          if (index > 0)
                            const Divider(color: Colors.white10, height: 22),
                          _buildAlgorithmParamField(option.params[index]),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlgorithmParamField(_AlgorithmParamSpec spec) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('param.${spec.key}.label'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr('param.${spec.key}.desc'),
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        spec.type == _AlgorithmParamType.boolean
            ? Switch(
                value:
                    _boolParamValues[spec.key] ??
                    (spec.defaultValue == true),
                activeColor: const Color(0xFF00C6FF),
                onChanged: (value) {
                  setState(() => _boolParamValues[spec.key] = value);
                },
              )
            : SizedBox(
                width: 108,
                child: TextField(
                  controller: _paramControllers[spec.key],
                  keyboardType: spec.keyboardType,
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF00C6FF)),
                    ),
                  ),
                ),
              ),
      ],
    );
  }

  Widget _buildVisibilityPanel() {
    return _buildGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(
            _isPublicTask ? Icons.public : Icons.lock_outline,
            color: const Color(0xFF00C6FF),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('creation.visibility.title'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  context.tr(
                    _isPublicTask
                        ? 'creation.visibility.publicHint'
                        : 'creation.visibility.privateHint',
                  ),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: _isPublicTask,
            activeColor: const Color(0xFF00C6FF),
            onChanged: (value) => setState(() => _isPublicTask = value),
          ),
        ],
      ),
    );
  }

  Widget _buildAlgorithmSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: _loadingAlgorithms
          ? const SizedBox(height: 48, child: Center(child: _JumpingDots()))
          : DropdownButton<String>(
              value: _selectedAlgorithm,
              isExpanded: true,
              dropdownColor: const Color(0xFF1C0305),
              underline: const SizedBox(),
              icon: const Icon(
                Icons.keyboard_arrow_down,
                color: Colors.white70,
              ),
              items: _algorithmOptions.map((option) {
                final serverUnavailable =
                    _availableAlgorithmNames != null &&
                        !_availableAlgorithmNames!.contains(option.algorithm);
                final enabled = option.enabled;
                final suffix = !enabled
                    ? context.tr('algorithm.unavailable')
                    : serverUnavailable
                    ? context.tr('algorithm.serverMissing')
                    : '';
                return DropdownMenuItem<String>(
                  value: option.algorithm,
                  enabled: enabled,
                  child: Text(
                    '${_algorithmTitle(context, option)}$suffix',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: enabled ? Colors.white : Colors.white38,
                      fontSize: 14,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (newValue) {
                if (newValue != null) {
                  _selectAlgorithm(newValue);
                }
              },
            ),
    );
  }

  Widget _buildActionButton(
    String label,
    IconData icon,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: const Color(0xFF00C6FF), size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageThumbnail(int index) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        image: DecorationImage(
          image: FileImage(File(_selectedImages[index].path)),
          fit: BoxFit.cover,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: () => _removeImage(index),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoThumbnail(int index) {
    final thumbnailPath = index < _selectedVideoThumbnailPaths.length
        ? _selectedVideoThumbnailPaths[index]
        : null;
    final hasThumbnail =
        thumbnailPath != null && File(thumbnailPath).existsSync();
    return Container(
      margin: const EdgeInsets.only(right: 12),
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.black.withValues(alpha: 0.28),
        image: hasThumbnail
            ? DecorationImage(
                image: FileImage(File(thumbnailPath!)),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.black.withValues(alpha: 0.18),
              ),
            ),
          ),
          const Center(
            child: Icon(
              Icons.videocam_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: () => _removeVideo(index),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _AlgorithmParamType { integer, decimal, text, boolean }

class _AlgorithmOption {
  final String algorithm;
  final String displayName;
  final String summary;
  final bool enabled;
  final List<_AlgorithmParamSpec> params;

  const _AlgorithmOption({
    required this.algorithm,
    required this.displayName,
    required this.summary,
    this.enabled = true,
    this.params = const [],
  });
}

class _AlgorithmParamSpec {
  final String key;
  final String label;
  final String description;
  final Object defaultValue;
  final _AlgorithmParamType type;

  const _AlgorithmParamSpec({
    required this.key,
    required this.label,
    required this.description,
    required this.defaultValue,
    required this.type,
  });

  String get defaultText => defaultValue.toString();

  TextInputType get keyboardType {
    switch (type) {
      case _AlgorithmParamType.integer:
        return TextInputType.number;
      case _AlgorithmParamType.decimal:
        return const TextInputType.numberWithOptions(decimal: true);
      case _AlgorithmParamType.text:
      case _AlgorithmParamType.boolean:
        return TextInputType.text;
    }
  }

  Object parse(String text) {
    if (text.isEmpty) return defaultValue;
    switch (type) {
      case _AlgorithmParamType.integer:
        return int.tryParse(text) ?? defaultValue;
      case _AlgorithmParamType.decimal:
        return double.tryParse(text) ?? defaultValue;
      case _AlgorithmParamType.text:
        return text;
      case _AlgorithmParamType.boolean:
        return defaultValue;
    }
  }
}

const List<_AlgorithmOption> _algorithmOptions = [
  _AlgorithmOption(
    algorithm: 'anysplat',
    displayName: 'AnySplat Reconstruction',
    summary: 'Fast 3DGS reconstruction from images or short videos.',
    params: [
      _AlgorithmParamSpec(
        key: 'frame_nums',
        label: 'Frame count',
        description: 'Controls how many key frames are sampled per pass.',
        defaultValue: 4,
        type: _AlgorithmParamType.integer,
      ),
      _AlgorithmParamSpec(
        key: 'crop_quantile',
        label: 'Crop confidence quantile',
        description: 'Filters edges and low-confidence regions.',
        defaultValue: 0.8,
        type: _AlgorithmParamType.decimal,
      ),
    ],
  ),
  _AlgorithmOption(
    algorithm: 'dash_gaussian',
    displayName: 'DashGaussian Reconstruction',
    summary: 'Higher quality Gaussian optimization for stable captures.',
    params: [
      _AlgorithmParamSpec(
        key: 'iterations',
        label: 'Training iterations',
        description: 'Controls optimization rounds for the Gaussian model.',
        defaultValue: 30000,
        type: _AlgorithmParamType.integer,
      ),
    ],
  ),
  _AlgorithmOption(
    algorithm: 'hunyuan3d',
    displayName: 'Hunyuan3D',
    summary: 'Uses the backend default configuration.',
  ),
  _AlgorithmOption(
    algorithm: 'vggt_omega',
    displayName: 'VGGT Omega',
    summary: 'Currently disabled until the backend enables this algorithm.',
    enabled: false,
  ),
];
String _algorithmTitle(BuildContext context, _AlgorithmOption option) {
  switch (option.algorithm) {
    case 'anysplat':
      return context.tr('algorithm.anysplat.title');
    case 'dash_gaussian':
      return context.tr('algorithm.dashGaussian.title');
    case 'hunyuan3d':
      return context.tr('algorithm.hunyuan3d.title');
    case 'vggt_omega':
      return context.tr('algorithm.vggtOmega.title');
    default:
      return option.displayName;
  }
}

String _algorithmSummary(BuildContext context, _AlgorithmOption option) {
  switch (option.algorithm) {
    case 'anysplat':
      return context.tr('algorithm.anysplat.summary');
    case 'dash_gaussian':
      return context.tr('algorithm.dashGaussian.summary');
    case 'hunyuan3d':
      return context.tr('algorithm.hunyuan3d.summary');
    case 'vggt_omega':
      return context.tr('algorithm.vggtOmega.summary');
    default:
      return option.summary;
  }
}

class _JumpingDots extends StatefulWidget {
  const _JumpingDots();

  @override
  State<_JumpingDots> createState() => _JumpingDotsState();
}

class _JumpingDotsState extends State<_JumpingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final phase = (_controller.value + index * 0.18) * math.pi * 2;
            final offset = -4 * math.sin(phase);
            return Transform.translate(
              offset: Offset(0, offset),
              child: Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: const BoxDecoration(
                  color: Color(0xFF00C6FF),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
