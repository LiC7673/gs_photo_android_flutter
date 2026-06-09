import 'package:flutter/material.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/state/language_state.dart';
import 'package:path/path.dart' as p;

class MeshPreviewPage extends StatefulWidget {
  final String? modelPath;
  final String? modelUrl;

  const MeshPreviewPage({super.key, this.modelPath, this.modelUrl});

  static bool supportsPath(String? path) {
    if (path == null || path.trim().isEmpty) return false;
    final extension = p.extension(path).toLowerCase();
    return const {'.glb', '.gltf', '.obj', '.fbx'}.contains(extension);
  }

  @override
  State<MeshPreviewPage> createState() => _MeshPreviewPageState();
}

class _MeshPreviewPageState extends State<MeshPreviewPage> {
  final Flutter3DController _controller = Flutter3DController();

  bool _loading = true;
  bool _autoRotate = false;
  String? _error;
  String? _selectedAnimation;
  List<String> _animations = const [];

  String? get _source {
    final url = widget.modelUrl?.trim();
    if (url != null && url.isNotEmpty) return url;

    final path = widget.modelPath?.trim();
    if (path == null || path.isEmpty) return null;
    return Uri.file(path).toString();
  }

  bool get _isObj {
    final source = widget.modelPath ?? widget.modelUrl ?? '';
    return p.extension(source).toLowerCase() == '.obj';
  }

  String get _title {
    final source = widget.modelPath ?? widget.modelUrl;
    if (source == null || source.isEmpty) return 'Mesh Preview';
    return p.basename(source);
  }

  Future<void> _onModelLoaded(String modelAddress) async {
    if (!mounted) return;

    var animations = const <String>[];
    if (!_isObj) {
      try {
        animations = await _controller.getAvailableAnimations();
      } catch (_) {
        animations = const <String>[];
      }
    }

    setState(() {
      _loading = false;
      _error = null;
      _animations = animations;
      _selectedAnimation = animations.isEmpty ? null : animations.first;
    });
  }

  void _onModelLoadFailed(String error) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = 'Model failed to load: $error';
    });
  }

  Future<void> _toggleAutoRotate() async {
    if (_isObj) return;
    final next = !_autoRotate;
    if (next) {
      _controller.startRotation(rotationSpeed: 20);
    } else {
      _controller.pauseRotation();
    }
    setState(() => _autoRotate = next);
  }

  Future<void> _resetCamera() async {
    if (_isObj) return;
    _controller.resetCameraOrbit();
    _controller.resetCameraTarget();
  }

  Future<void> _playAnimation(String? animation) async {
    if (animation == null || animation.isEmpty || _isObj) return;
    _controller.playAnimation(animationName: animation);
    if (mounted) {
      setState(() => _selectedAnimation = animation);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageState>();
    final source = _source;
    final unsupported =
        source == null ||
        (!MeshPreviewPage.supportsPath(widget.modelPath) &&
            widget.modelUrl == null);

    return Scaffold(
      backgroundColor: const Color(0xFF05070F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Text(
          _title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: unsupported
            ? _UnsupportedMesh(path: widget.modelPath)
            : Stack(
                children: [
                  Positioned.fill(child: _buildViewer(source)),
                  if (_loading)
                    const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF00C6FF),
                      ),
                    ),
                  if (_error != null) _buildError(),
                  if (!_loading && _error == null) _buildToolbar(),
                ],
              ),
      ),
    );
  }

  Widget _buildViewer(String source) {
    if (_isObj) {
      return Flutter3DViewer.obj(
        src: source,
        scale: 1,
        cameraX: 0,
        cameraY: 0,
        cameraZ: 10,
        onLoad: _onModelLoaded,
        onError: _onModelLoadFailed,
      );
    }

    return Flutter3DViewer(
      controller: _controller,
      src: source,
      activeGestureInterceptor: true,
      enableTouch: true,
      progressBarColor: const Color(0xFF00C6FF),
      onLoad: _onModelLoaded,
      onError: _onModelLoadFailed,
    );
  }

  Widget _buildError() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1026).withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: context.tr('viewer.mesh.resetCamera'),
              onPressed: _isObj ? null : _resetCamera,
              icon: const Icon(Icons.center_focus_strong),
              color: Colors.white,
              disabledColor: Colors.white24,
            ),
            IconButton(
              tooltip: context.tr('viewer.mesh.autoRotate'),
              onPressed: _isObj ? null : _toggleAutoRotate,
              icon: Icon(_autoRotate ? Icons.pause : Icons.threesixty),
              color: const Color(0xFF00C6FF),
              disabledColor: Colors.white24,
            ),
            const SizedBox(width: 8),
            Expanded(child: _buildAnimationPicker()),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimationPicker() {
    if (_isObj || _animations.isEmpty) {
      return Text(
        context.tr('viewer.mesh.gestureHint'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white60, fontSize: 13),
      );
    }

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selectedAnimation,
        isExpanded: true,
        dropdownColor: const Color(0xFF101735),
        iconEnabledColor: Colors.white70,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        items: _animations
            .map(
              (animation) => DropdownMenuItem<String>(
                value: animation,
                child: Text(
                  animation,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: _playAnimation,
      ),
    );
  }
}

class _UnsupportedMesh extends StatelessWidget {
  final String? path;

  const _UnsupportedMesh({this.path});

  @override
  Widget build(BuildContext context) {
    final extension = p.extension(path ?? '').toLowerCase();
    final message = extension == '.ply'
        ? 'PLY is not supported by flutter_3d_controller. Use GLB, GLTF, OBJ, or FBX. PLY files still use the existing point-cloud viewer.'
        : 'Open a GLB, GLTF, OBJ, or FBX file to preview the mesh.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.view_in_ar_outlined,
              size: 64,
              color: Color(0xFF00C6FF),
            ),
            const SizedBox(height: 18),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
