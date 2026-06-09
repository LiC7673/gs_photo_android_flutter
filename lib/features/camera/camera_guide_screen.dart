import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/state/language_state.dart';

enum CameraGuideMode { photo, video }

class CameraGuideArgs {
  final String? taskName;
  final Map<String, dynamic> params;
  final List<XFile> initialImages;
  final CameraGuideMode mode;

  const CameraGuideArgs({
    this.taskName,
    this.params = const {},
    this.initialImages = const [],
    this.mode = CameraGuideMode.photo,
  });

  CameraGuideArgs copyWith({CameraGuideMode? mode}) {
    return CameraGuideArgs(
      taskName: taskName,
      params: params,
      initialImages: initialImages,
      mode: mode ?? this.mode,
    );
  }
}

class CameraGuideResult {
  final List<XFile> images;
  final List<String> videoPaths;
  final List<String> videoThumbnailPaths;
  final String? reportPath;

  const CameraGuideResult({
    this.images = const [],
    this.videoPaths = const [],
    this.videoThumbnailPaths = const [],
    this.reportPath,
  });
}

class CameraGuideScreen extends StatefulWidget {
  final CameraGuideArgs? args;

  const CameraGuideScreen({super.key, this.args});

  @override
  State<CameraGuideScreen> createState() => _CameraGuideScreenState();
}

class VideoCameraGuideScreen extends StatelessWidget {
  final CameraGuideArgs? args;

  const VideoCameraGuideScreen({super.key, this.args});

  @override
  Widget build(BuildContext context) {
    return CameraGuideScreen(
      args: (args ?? const CameraGuideArgs()).copyWith(
        mode: CameraGuideMode.video,
      ),
    );
  }
}

class _CameraGuideScreenState extends State<CameraGuideScreen> {
  final List<XFile> _selectedImages = [];
  final List<String> _savedVideoPaths = [];
  final List<String> _savedVideoThumbnailPaths = [];
  final List<_QualitySegment> _motionWarnings = [];
  final List<_QualitySegment> _coverageWarnings = [];
  final List<CameraDescription> _backCameras = [];

  CameraController? _controller;
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;
  Timer? _recordingTimer;
  Timer? _zoomWheelHideTimer;

  bool _isInitialized = false;
  bool _isRecording = false;
  bool _recordingBusy = false;
  bool _isAnalyzingFrame = false;
  bool _permissionDenied = false;
  bool _showZoomWheel = false;

  DateTime? _recordingStartedAt;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _recordingDuration = Duration.zero;
  String? _pendingVideoThumbnailPath;

  double? _lastBrightness;
  double? _lastFrameSignature;
  double _blurScore = 1;
  double _brightness = 0;
  double _frameChange = 0;
  double _motionSpeed = 0;
  double _minZoom = 1;
  double _maxZoom = 1;
  double _currentZoom = 1;
  DeviceOrientation? _lockedCaptureOrientation;

  int _sampleCount = 0;
  int _blurFrameCount = 0;
  int _exposureJumpCount = 0;
  int _coverageIssueCount = 0;
  int _rapidTurnCount = 0;
  int _cameraIndex = 0;

  _CaptureReport? _lastReport;

  bool get _isVideoMode => widget.args?.mode == CameraGuideMode.video;

  static const Duration _minimumRecordingDuration = Duration(seconds: 2);

  _MetricStatus get _blurStatus {
    if (_sampleCount == 0) return _MetricStatus.good;
    if (_blurScore < 0.35) return _MetricStatus.bad;
    if (_blurScore < 0.55) return _MetricStatus.warn;
    return _MetricStatus.good;
  }

  _MetricStatus get _motionStatus {
    if (_motionSpeed > 2.2) return _MetricStatus.bad;
    if (_motionSpeed > 1.3) return _MetricStatus.warn;
    return _MetricStatus.good;
  }

  _MetricStatus get _exposureStatus {
    if (_lastBrightness == null) return _MetricStatus.good;
    if (_brightness < 35 || _brightness > 220) return _MetricStatus.warn;
    return _MetricStatus.good;
  }

  _MetricStatus get _coverageStatus {
    if (_frameChange > 42) return _MetricStatus.bad;
    if (_frameChange > 28) return _MetricStatus.warn;
    return _MetricStatus.good;
  }

  @override
  void initState() {
    super.initState();
    unawaited(WakelockPlus.enable());
    unawaited(_importInitialImages());
    unawaited(_initializeCamera());
  }

  Future<void> _importInitialImages() async {
    for (final image in widget.args?.initialImages ?? const <XFile>[]) {
      final savedPath = await _saveImageFile(image);
      if (!mounted) return;
      _selectedImages.add(XFile(savedPath, name: path.basename(savedPath)));
    }
    if (mounted && _selectedImages.isNotEmpty) setState(() {});
  }

  Future<void> _initializeCamera() async {
    final permission = await Permission.camera.request();
    if (!permission.isGranted) {
      if (mounted) setState(() => _permissionDenied = true);
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      _backCameras
        ..clear()
        ..addAll(
          cameras.where(
            (item) => item.lensDirection == CameraLensDirection.back,
          ),
        );
      if (_backCameras.isEmpty) _backCameras.addAll(cameras);
      _cameraIndex = _cameraIndex.clamp(0, _backCameras.length - 1).toInt();
      final camera = _backCameras[_cameraIndex];
      debugPrint(
        '[CameraGuide] using camera index=$_cameraIndex '
        'name=${camera.name} lens=${camera.lensDirection} '
        'orientation=${camera.sensorOrientation} '
        'candidates=${_backCameras.length}',
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      final initialOrientation = _deviceOrientationForMedia(context);
      _lockedCaptureOrientation = initialOrientation;
      await _applyCaptureOrientation(controller, initialOrientation);
      _controller = controller;
      _listenToMotion();
      if (mounted) setState(() => _isInitialized = true);
      unawaited(_startCameraBackgroundSetup(controller));
    } catch (e) {
      debugPrint('[CameraGuide] init failed: $e');
      if (mounted) setState(() => _permissionDenied = true);
    }
  }

  Future<void> _switchBackCamera() async {
    if (_backCameras.length < 2 || _recordingBusy || _isRecording) return;
    final oldController = _controller;
    _controller = null;
    setState(() {
      _isInitialized = false;
      _minZoom = 1;
      _maxZoom = 1;
      _currentZoom = 1;
      _showZoomWheel = false;
      _lockedCaptureOrientation = null;
      _cameraIndex = (_cameraIndex + 1) % _backCameras.length;
    });
    try {
      await oldController?.dispose();
    } catch (e) {
      debugPrint('[CameraGuide] dispose before switch failed: $e');
    }
    await _initializeCamera();
  }

  Future<void> _startCameraBackgroundSetup(CameraController controller) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted || _controller != controller) return;
    await _initializeZoom(controller);
  }

  Future<void> _initializeZoom(CameraController controller) async {
    try {
      final minZoom = await controller.getMinZoomLevel();
      final maxZoom = await controller.getMaxZoomLevel();
      final initialZoom = 1.0.clamp(minZoom, maxZoom).toDouble();
      await controller.setZoomLevel(initialZoom);
      if (!mounted || _controller != controller) return;
      setState(() {
        _minZoom = minZoom;
        _maxZoom = maxZoom;
        _currentZoom = initialZoom;
      });
    } catch (e) {
      debugPrint('[CameraGuide] zoom init failed: $e');
      if (mounted) {
        setState(() {
          _minZoom = 1;
          _maxZoom = 1;
          _currentZoom = 1;
        });
      }
    }
  }

  DeviceOrientation _deviceOrientationForMedia(BuildContext context) {
    final orientation = MediaQuery.maybeOf(context)?.orientation;
    return orientation == Orientation.landscape
        ? DeviceOrientation.landscapeLeft
        : DeviceOrientation.portraitUp;
  }

  Future<void> _applyCaptureOrientation(
    CameraController controller,
    DeviceOrientation deviceOrientation,
  ) async {
    try {
      await controller.lockCaptureOrientation(deviceOrientation);
      debugPrint('[CameraGuide] capture orientation locked=$deviceOrientation');
    } catch (e) {
      debugPrint('[CameraGuide] lock capture orientation failed: $e');
    }
  }

  Future<void> _setZoomLevel(double zoom, {bool revealWheel = false}) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final nextZoom = zoom.clamp(_minZoom, _maxZoom).toDouble();
    try {
      await controller.setZoomLevel(nextZoom);
      if (!mounted) return;
      setState(() {
        _currentZoom = nextZoom;
        if (revealWheel) _showZoomWheel = true;
      });
    } catch (e) {
      debugPrint('[CameraGuide] set zoom failed: $e');
    }
  }

  void _revealZoomWheel() {
    _zoomWheelHideTimer?.cancel();
    if (!_showZoomWheel && mounted) {
      setState(() => _showZoomWheel = true);
    }
  }

  void _scheduleZoomWheelHide() {
    _zoomWheelHideTimer?.cancel();
    _zoomWheelHideTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _showZoomWheel = false);
    });
  }

  void _handleZoomDrag(double delta) {
    if (_maxZoom <= _minZoom) return;
    _revealZoomWheel();
    final nextZoom = _currentZoom + delta * 0.018;
    unawaited(_setZoomLevel(nextZoom, revealWheel: true));
  }

  void _listenToMotion() {
    _gyroSubscription?.cancel();
    _gyroSubscription = gyroscopeEvents.listen((event) {
      final speed = math.sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      if (!mounted) return;
      setState(() => _motionSpeed = speed);
      if (_isRecording && speed > 1.6) {
        _rapidTurnCount++;
        _addSegment(_motionWarnings);
      }
    });
  }

  Future<void> _startQualityStream() async {
    // Disabled by default: on some vivo/Adreno devices, starting an
    // ImageReader stream together with CameraPreview leaves the preview black.
  }

  Future<void> _stopQualityStream() async {
    // See _startQualityStream.
  }

  void _handleCameraImage(CameraImage image) {
    final now = DateTime.now();
    if (_isAnalyzingFrame || now.difference(_lastFrameAt).inMilliseconds < 450) {
      return;
    }
    _isAnalyzingFrame = true;
    _lastFrameAt = now;

    final metrics = _analyzeLumaPlane(image);
    final previousBrightness = _lastBrightness;
    final previousSignature = _lastFrameSignature;

    _lastBrightness = metrics.brightness;
    _lastFrameSignature = metrics.signature;
    _blurScore = metrics.blurScore;
    _brightness = metrics.brightness;
    if (previousSignature != null) {
      _frameChange = (metrics.signature - previousSignature).abs();
    }

    if (_isRecording) {
      _sampleCount++;
      if (metrics.blurScore < 0.45) _blurFrameCount++;
      if (previousBrightness != null &&
          (metrics.brightness - previousBrightness).abs() > 35) {
        _exposureJumpCount++;
      }
      if (_frameChange > 30) {
        _coverageIssueCount++;
        _addSegment(_coverageWarnings);
      }
    }

    _isAnalyzingFrame = false;
    if (mounted) setState(() {});
  }

  _FrameMetrics _analyzeLumaPlane(CameraImage image) {
    final plane = image.planes.first;
    final bytes = plane.bytes;
    final width = image.width;
    final height = image.height;
    final rowStride = plane.bytesPerRow;
    const sampleStep = 8;

    var brightnessSum = 0.0;
    var edgeSum = 0.0;
    var signatureSum = 0.0;
    var count = 0;

    for (var y = sampleStep; y < height - sampleStep; y += sampleStep) {
      final row = y * rowStride;
      for (var x = sampleStep; x < width - sampleStep; x += sampleStep) {
        final index = row + x;
        if (index >= bytes.length) continue;
        final rightIndex = row + x + sampleStep;
        final downIndex = (y + sampleStep) * rowStride + x;
        if (rightIndex >= bytes.length || downIndex >= bytes.length) continue;
        final value = bytes[index];
        brightnessSum += value;
        edgeSum += (value - bytes[rightIndex]).abs();
        edgeSum += (value - bytes[downIndex]).abs();
        signatureSum += value * ((x + y) % 7 + 1);
        count++;
      }
    }

    if (count == 0) {
      return const _FrameMetrics(brightness: 0, blurScore: 1, signature: 0);
    }
    final edgeStrength = edgeSum / count;
    return _FrameMetrics(
      brightness: brightnessSum / count,
      blurScore: (edgeStrength / 42).clamp(0.0, 1.0).toDouble(),
      signature: signatureSum / count / 4,
    );
  }

  Future<void> _startRecording() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isRecording ||
        _recordingBusy) {
      return;
    }

    _resetSession();
    if (mounted) setState(() => _recordingBusy = true);
    try {
      if (_isVideoMode) {
        _pendingVideoThumbnailPath = await _captureVideoThumbnail(controller);
        await controller.startVideoRecording();
      } else {
        await controller.startVideoRecording();
      }
      unawaited(WakelockPlus.enable());
      _recordingStartedAt = DateTime.now();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _recordingStartedAt == null) return;
        setState(() {
          _recordingDuration = _currentRecordingDuration();
        });
      });
      if (mounted) {
        setState(() {
          _isRecording = true;
          _recordingBusy = false;
        });
      }
    } catch (e) {
      debugPrint('[CameraGuide] start recording failed: $e');
      if (!mounted) return;
      setState(() => _recordingBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'camera.error.startRecording',
              args: {'message': e},
            ),
          ),
        ),
      );
    }
  }

  Future<void> _stopRecording() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        !_isRecording ||
        _recordingBusy) {
      return;
    }

    if (mounted) setState(() => _recordingBusy = true);
    final remaining = _minimumRecordingDuration - _currentRecordingDuration();
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
    _recordingTimer?.cancel();
    XFile? video;
    Object? stopError;
    try {
      video = await controller.stopVideoRecording();
    } catch (e) {
      stopError = e;
      debugPrint('[CameraGuide] stop recording failed: $e');
    }

    if (stopError != null) {
      _recordingTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _recordingBusy = false;
        _recordingStartedAt = null;
        _recordingDuration = Duration.zero;
        _pendingVideoThumbnailPath = null;
      });
      await _recoverCameraAfterRecordingFailure();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'camera.error.stopRecording',
              args: {'message': stopError},
            ),
          ),
        ),
      );
      return;
    }

    final savedVideoPath = video == null ? null : await _saveVideo(video);
    final thumbnailPath = _pendingVideoThumbnailPath;
    if (savedVideoPath != null && thumbnailPath != null) {
      _savedVideoThumbnailPaths.add(thumbnailPath);
    }
    _pendingVideoThumbnailPath = null;
    final report = _buildReport(videoPath: savedVideoPath);
    final reportPath = await _saveReport(report);

    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _recordingBusy = false;
      _lastReport = report.copyWith(reportPath: reportPath);
    });
    _showReportSheet(_lastReport!);
  }

  Future<void> _recoverCameraAfterRecordingFailure() async {
    final oldController = _controller;
    _controller = null;
    if (mounted) setState(() => _isInitialized = false);
    try {
      await oldController?.dispose();
    } catch (e) {
      debugPrint('[CameraGuide] dispose failed after recording error: $e');
    }
    await _initializeCamera();
  }

  Duration _currentRecordingDuration() {
    final startedAt = _recordingStartedAt;
    if (startedAt == null) return _recordingDuration;
    return DateTime.now().difference(startedAt);
  }

  Future<String?> _captureVideoThumbnail(CameraController controller) async {
    if (!controller.value.isInitialized || controller.value.isTakingPicture) {
      return null;
    }
    try {
      final image = await controller.takePicture();
      return _saveImageFile(image);
    } catch (e) {
      debugPrint('[CameraGuide] video thumbnail capture failed: $e');
      return null;
    }
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture ||
        _isRecording) {
      return;
    }

    try {
      final photo = await controller.takePicture();
      final savedPath = await _saveImageFile(photo);
      if (!mounted) return;
      setState(() {
        _selectedImages.add(XFile(savedPath, name: path.basename(savedPath)));
      });
      unawaited(_playCaptureTapFeedback());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image saved: ${path.basename(savedPath)}')),
      );
    } catch (e) {
      debugPrint('[CameraGuide] take picture failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Capture failed: $e')),
      );
    }
  }

  Future<void> _playCaptureTapFeedback() async {
    try {
      await HapticFeedback.selectionClick();
      await SystemSound.play(SystemSoundType.click);
    } catch (e) {
      debugPrint('[CameraGuide] capture feedback failed: $e');
    }
  }

  Future<String> _saveVideo(XFile video) async {
    final captureDir = await _mediaDirectory('videos');
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final outputPath = path.join(captureDir.path, 'capture_$timestamp.mp4');
    await video.saveTo(outputPath);
    _savedVideoPaths.add(outputPath);
    return outputPath;
  }

  Future<String> _saveImageFile(XFile image) async {
    final captureDir = await _mediaDirectory('images');
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final extension = path.extension(image.path).isEmpty
        ? '.jpg'
        : path.extension(image.path);
    final outputPath = path.join(captureDir.path, 'image_$timestamp$extension');
    await File(image.path).copy(outputPath);
    return outputPath;
  }

  Future<String> _saveReport(_CaptureReport report) async {
    final reportDir = await _mediaDirectory('reports');
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final outputPath = path.join(reportDir.path, 'quality_$timestamp.json');
    await File(outputPath).writeAsString(jsonEncode(report.toJson()));
    return outputPath;
  }

  Future<Directory> _mediaDirectory(String child) async {
    final directory = await getApplicationDocumentsDirectory();
    final captureDir = Directory(path.join(directory.path, 'captures', child));
    if (!await captureDir.exists()) {
      await captureDir.create(recursive: true);
    }
    return captureDir;
  }

  void _finishCapture() {
    context.pop(
      CameraGuideResult(
        images: List<XFile>.from(_selectedImages),
        videoPaths: List<String>.from(_savedVideoPaths),
        videoThumbnailPaths: List<String>.from(_savedVideoThumbnailPaths),
        reportPath: _lastReport?.reportPath,
      ),
    );
  }

  Future<void> _handleBack() async {
    if (_isRecording && !_recordingBusy) {
      await _stopRecording();
      return;
    }
    if (!_recordingBusy && mounted) {
      context.pop();
    }
  }

  _CaptureReport _buildReport({String? videoPath}) {
    final blurRatio = _sampleCount == 0 ? 0.0 : _blurFrameCount / _sampleCount;
    final coverageRatio = _sampleCount == 0
        ? 0.0
        : _coverageIssueCount / _sampleCount;
    final score = (100 -
            blurRatio * 32 -
            coverageRatio * 22 -
            _rapidTurnCount * 2.5 -
            _exposureJumpCount * 7)
        .round()
        .clamp(0, 100)
        .toInt();
    final suggestions = <String>[];
    if (_motionWarnings.isNotEmpty) {
      suggestions.add(
        context.tr(
          'camera.report.suggestion.motion',
          args: {'time': _formatSegments(_motionWarnings)},
        ),
      );
    }
    if (_coverageWarnings.isNotEmpty) {
      suggestions.add(
        context.tr(
          'camera.report.suggestion.overlap',
          args: {'time': _formatSegments(_coverageWarnings)},
        ),
      );
    }
    if (_exposureJumpCount > 0) {
      suggestions.add(context.tr('camera.report.suggestion.exposure'));
    }
    suggestions.add(
      score >= 70
          ? context.tr('camera.report.suggestion.usable')
          : context.tr('camera.report.suggestion.retake'),
    );
    return _CaptureReport(
      score: score,
      blurRatio: blurRatio,
      rapidTurnCount: _rapidTurnCount,
      exposureJumpCount: _exposureJumpCount,
      coverageIssueCount: _coverageIssueCount,
      suggestions: suggestions,
      videoPath: videoPath,
      reportPath: null,
    );
  }

  String _formatSegments(List<_QualitySegment> segments) {
    final segment = segments.first;
    final start = segment.startSecond;
    final end = math.max(segment.endSecond, start + 1);
    return '$start-$end s';
  }

  void _addSegment(List<_QualitySegment> list) {
    final second = _recordingDuration.inSeconds;
    if (list.isNotEmpty && second - list.last.endSecond <= 1) {
      list[list.length - 1] = list.last.copyWith(endSecond: second);
      return;
    }
    list.add(_QualitySegment(startSecond: second, endSecond: second));
  }

  void _removeImage(int index) {
    setState(() => _selectedImages.removeAt(index));
  }

  void _resetSession() {
    _recordingStartedAt = null;
    _recordingDuration = Duration.zero;
    _sampleCount = 0;
    _blurFrameCount = 0;
    _exposureJumpCount = 0;
    _coverageIssueCount = 0;
    _rapidTurnCount = 0;
    _motionWarnings.clear();
    _coverageWarnings.clear();
    _lastReport = null;
    _pendingVideoThumbnailPath = null;
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _zoomWheelHideTimer?.cancel();
    _gyroSubscription?.cancel();
    _controller?.dispose();
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageState>();
    _syncCaptureOrientation();
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _buildPreview()),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.72),
                  ],
                ),
              ),
            ),
          ),
          _buildTopBar(context),
          _buildMetricPanel(),
          _buildCaptureControls(),
        ],
      ),
    );
  }

  void _syncCaptureOrientation() {
    final controller = _controller;
    if (!_isInitialized || controller == null || _isRecording) return;
    final nextOrientation = _deviceOrientationForMedia(context);
    if (_lockedCaptureOrientation == nextOrientation) return;
    _lockedCaptureOrientation = nextOrientation;
    unawaited(_applyCaptureOrientation(controller, nextOrientation));
  }

  Widget _buildPreview() {
    final controller = _controller;
    if (_permissionDenied) {
      return Center(
        child: Text(
          context.tr('camera.permissionRequired'),
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }
    if (!_isInitialized || controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00C6FF)),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final previewAspect = _displayPreviewAspectRatio(controller, context);
        final viewAspect = constraints.maxWidth / constraints.maxHeight;

        final previewWidth = viewAspect > previewAspect
            ? constraints.maxWidth
            : constraints.maxHeight * previewAspect;
        final previewHeight = viewAspect > previewAspect
            ? constraints.maxWidth / previewAspect
            : constraints.maxHeight;

        return ClipRect(
          child: OverflowBox(
            maxWidth: previewWidth,
            maxHeight: previewHeight,
            child: SizedBox(
              width: previewWidth,
              height: previewHeight,
              child: CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }

  double _displayPreviewAspectRatio(
    CameraController controller,
    BuildContext context,
  ) {
    final cameraAspect = controller.value.aspectRatio;
    if (cameraAspect <= 0) return 9 / 16;
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final normalizedLandscapeAspect =
        cameraAspect >= 1 ? cameraAspect : 1 / cameraAspect;
    return landscape
        ? normalizedLandscapeAspect
        : 1 / normalizedLandscapeAspect;
  }

  Widget _buildTopBar(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: Row(
        children: [
          _GlassIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onPressed: _handleBack,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('camera.title'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _isRecording
                      ? context.tr(
                          'camera.recording',
                          args: {'time': _formatDuration(_recordingDuration)},
                        )
                      : _isVideoMode
                          ? context.tr(
                              'camera.videosSaved',
                              args: {'count': _savedVideoPaths.length},
                            )
                          : context.tr(
                              'camera.imagesSaved',
                              args: {'count': _selectedImages.length},
                            ),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          if (_lastReport != null)
            _GlassIconButton(
              icon: Icons.assessment_outlined,
              onPressed: () => _showReportSheet(_lastReport!),
            ),
          if (_backCameras.length > 1) ...[
            const SizedBox(width: 10),
            _GlassIconButton(
              icon: Icons.cameraswitch_outlined,
              onPressed: _switchBackCamera,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricPanel() {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final tiles = [
      _MetricTile(
        label: context.tr('camera.metric.sharpness'),
        value: _metricStatusLabel(_blurStatus),
        status: _blurStatus,
      ),
      _MetricTile(
        label: context.tr('camera.metric.motion'),
        value: _metricStatusLabel(_motionStatus),
        status: _motionStatus,
      ),
      _MetricTile(
        label: context.tr('camera.metric.exposure'),
        value: _metricStatusLabel(_exposureStatus),
        status: _exposureStatus,
      ),
      _MetricTile(
        label: context.tr('camera.metric.overlap'),
        value: _metricStatusLabel(_coverageStatus),
        status: _coverageStatus,
      ),
    ];

    return Positioned(
      left: isLandscape ? 72 : 16,
      right: isLandscape ? 72 : 16,
      top: MediaQuery.of(context).padding.top + (isLandscape ? 56 : 72),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: EdgeInsets.all(isLandscape ? 10 : 14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.48),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: isLandscape
                ? Row(children: tiles.map((tile) => Expanded(child: tile)).toList())
                : Column(
                    children: [
                      Row(children: [Expanded(child: tiles[0]), Expanded(child: tiles[1])]),
                      const SizedBox(height: 10),
                      Row(children: [Expanded(child: tiles[2]), Expanded(child: tiles[3])]),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  String _metricStatusLabel(_MetricStatus status) {
    switch (status) {
      case _MetricStatus.good:
        return context.tr('camera.status.good');
      case _MetricStatus.warn:
        return context.tr('camera.status.check');
      case _MetricStatus.bad:
        return context.tr('camera.status.bad');
    }
  }

  Widget _buildCaptureControls() {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Positioned(
      left: isLandscape ? 72 : 16,
      right: isLandscape ? 72 : 16,
      bottom: math.max(16, bottomPadding + 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_isVideoMode && _selectedImages.isNotEmpty && !isLandscape) ...[
            SizedBox(
              height: 58,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _selectedImages.length,
                itemBuilder: (context, index) => _buildCapturedThumb(index),
              ),
            ),
            const SizedBox(height: 10),
          ],
          _buildZoomControl(),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                padding: const EdgeInsets.all(10),
                color: Colors.black.withValues(alpha: 0.45),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (!_isVideoMode) ...[
                      _CaptureActionButton(
                        icon: Icons.camera_alt_outlined,
                        label: context.tr('camera.action.photo'),
                        onPressed: _isInitialized && !_isRecording
                            ? _takePicture
                            : null,
                      ),
                      _CaptureActionButton(
                        icon: Icons.check_rounded,
                        label: context.tr(
                          'camera.action.done',
                          args: {'count': _selectedImages.length},
                        ),
                        color: const Color(0xFF2DFF9A),
                        onPressed: _selectedImages.isEmpty
                            ? null
                            : _finishCapture,
                      ),
                    ] else ...[
                      _CaptureActionButton(
                        icon: _isRecording
                            ? Icons.stop_rounded
                            : Icons.fiber_manual_record,
                        label: _isRecording
                            ? context.tr('camera.action.stop')
                            : context.tr('camera.action.record'),
                        color: _isRecording
                            ? const Color(0xFFFF4D6D)
                            : const Color(0xFF00C6FF),
                        onPressed: !_isInitialized || _recordingBusy
                            ? null
                            : (_isRecording ? _stopRecording : _startRecording),
                      ),
                      _CaptureActionButton(
                        icon: Icons.check_rounded,
                        label: context.tr(
                          'camera.action.done',
                          args: {'count': _savedVideoPaths.length},
                        ),
                        color: const Color(0xFF2DFF9A),
                        onPressed: _isRecording ||
                                _recordingBusy ||
                                _savedVideoPaths.isEmpty
                            ? null
                            : _finishCapture,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoomControl() {
    if (!_isInitialized || _maxZoom <= _minZoom) {
      return const SizedBox.shrink();
    }

    final zoomOptions = const [0.5, 1.0, 3.0];
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressStart: (_) => _revealZoomWheel(),
      onLongPressEnd: (_) => _scheduleZoomWheelHide(),
      onHorizontalDragStart: (_) => _revealZoomWheel(),
      onHorizontalDragUpdate: (details) {
        _handleZoomDrag(details.primaryDelta ?? 0);
      },
      onHorizontalDragEnd: (_) => _scheduleZoomWheelHide(),
      onHorizontalDragCancel: _scheduleZoomWheelHide,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: _showZoomWheel ? 248 : 176,
            padding: EdgeInsets.symmetric(
              horizontal: _showZoomWheel ? 12 : 6,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: _showZoomWheel
                ? _buildZoomWheel()
                : Row(
                    children: zoomOptions
                        .map(
                          (zoom) => Expanded(child: _buildZoomButton(zoom)),
                        )
                        .toList(),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildZoomButton(double zoom) {
    final supported = zoom >= _minZoom - 0.01 && zoom <= _maxZoom + 0.01;
    final selected = supported && (_currentZoom - zoom).abs() < 0.08;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Opacity(
        opacity: supported ? 1 : 0.42,
        child: GestureDetector(
          onTap: supported
              ? () {
                  unawaited(_setZoomLevel(zoom));
                  _scheduleZoomWheelHide();
                }
              : null,
          onLongPress: _revealZoomWheel,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: double.infinity,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF00C6FF).withValues(alpha: 0.9)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _formatZoomLabel(zoom),
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildZoomWheel() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 44,
          child: Text(
            _formatZoomLabel(_currentZoom),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF00C6FF),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              activeTrackColor: const Color(0xFF00C6FF),
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: const Color(0xFF00C6FF).withValues(alpha: 0.16),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: _currentZoom.clamp(_minZoom, _maxZoom).toDouble(),
              min: _minZoom,
              max: _maxZoom,
              divisions: math.max(1, ((_maxZoom - _minZoom) * 10).round()),
              onChangeStart: (_) => _revealZoomWheel(),
              onChanged: (value) {
                unawaited(_setZoomLevel(value, revealWheel: true));
              },
              onChangeEnd: (_) => _scheduleZoomWheelHide(),
            ),
          ),
        ),
      ],
    );
  }

  String _formatZoomLabel(double zoom) {
    if ((zoom - zoom.roundToDouble()).abs() < 0.05) {
      return '${zoom.round()}x';
    }
    return '${zoom.toStringAsFixed(1)}x';
  }

  Widget _buildCapturedThumb(int index) {
    final image = _selectedImages[index];
    return Container(
      width: 54,
      height: 54,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        image: DecorationImage(
          image: FileImage(File(image.path)),
          fit: BoxFit.cover,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Align(
        alignment: Alignment.topRight,
        child: GestureDetector(
          onTap: () => _removeImage(index),
          child: Container(
            margin: const EdgeInsets.all(3),
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close, color: Colors.white, size: 12),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _showReportSheet(_CaptureReport report) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0B1026),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.tr(
                          'camera.report.quality',
                          args: {'score': report.score},
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _ReportRow(
                  label: context.tr('camera.report.blurFrames'),
                  value: '${(report.blurRatio * 100).round()}%',
                ),
                _ReportRow(
                  label: context.tr('camera.report.fastTurns'),
                  value: '${report.rapidTurnCount}',
                ),
                _ReportRow(
                  label: context.tr('camera.report.exposureJumps'),
                  value: '${report.exposureJumpCount}',
                ),
                _ReportRow(
                  label: context.tr('camera.report.overlapIssues'),
                  value: '${report.coverageIssueCount}',
                ),
                const SizedBox(height: 14),
                Text(
                  context.tr('camera.report.suggestions'),
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 8),
                ...List.generate(
                  report.suggestions.length,
                  (index) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${index + 1}. ${report.suggestions[index]}',
                      style: const TextStyle(color: Colors.white, height: 1.35),
                    ),
                  ),
                ),
                if (report.reportPath != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    context.tr(
                      'camera.report.saved',
                      args: {'path': report.reportPath},
                    ),
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final _MetricStatus status;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: status.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '$label: $value',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _ReportRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReportRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: Colors.white54)),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CaptureActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color color;

  const _CaptureActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color = const Color(0xFF00C6FF),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, overflow: TextOverflow.ellipsis),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.14),
          disabledForegroundColor: Colors.white38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _GlassIconButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.white.withValues(alpha: 0.11),
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: 46,
              height: 46,
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

enum _MetricStatus {
  good(Color(0xFF2DFF9A)),
  warn(Color(0xFFFFD166)),
  bad(Color(0xFFFF4D6D));

  final Color color;

  const _MetricStatus(this.color);
}

class _FrameMetrics {
  final double brightness;
  final double blurScore;
  final double signature;

  const _FrameMetrics({
    required this.brightness,
    required this.blurScore,
    required this.signature,
  });
}

class _QualitySegment {
  final int startSecond;
  final int endSecond;

  const _QualitySegment({
    required this.startSecond,
    required this.endSecond,
  });

  _QualitySegment copyWith({int? endSecond}) {
    return _QualitySegment(
      startSecond: startSecond,
      endSecond: endSecond ?? this.endSecond,
    );
  }
}

class _CaptureReport {
  final int score;
  final double blurRatio;
  final int rapidTurnCount;
  final int exposureJumpCount;
  final int coverageIssueCount;
  final List<String> suggestions;
  final String? videoPath;
  final String? reportPath;

  const _CaptureReport({
    required this.score,
    required this.blurRatio,
    required this.rapidTurnCount,
    required this.exposureJumpCount,
    required this.coverageIssueCount,
    required this.suggestions,
    required this.videoPath,
    required this.reportPath,
  });

  _CaptureReport copyWith({String? reportPath}) {
    return _CaptureReport(
      score: score,
      blurRatio: blurRatio,
      rapidTurnCount: rapidTurnCount,
      exposureJumpCount: exposureJumpCount,
      coverageIssueCount: coverageIssueCount,
      suggestions: suggestions,
      videoPath: videoPath,
      reportPath: reportPath ?? this.reportPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'score': score,
      'blur_ratio': blurRatio,
      'rapid_turn_count': rapidTurnCount,
      'exposure_jump_count': exposureJumpCount,
      'coverage_issue_count': coverageIssueCount,
      'suggestions': suggestions,
      'video_path': videoPath,
      'report_path': reportPath,
      'created_at': DateTime.now().toIso8601String(),
    };
  }
}
