import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:go_router/go_router.dart';
import 'local_web_server.dart';

class SparkLocalViewerPage extends StatefulWidget {
  final String? modelPath;

  const SparkLocalViewerPage({super.key, this.modelPath});

  @override
  State<SparkLocalViewerPage> createState() => _SparkLocalViewerPageState();
}

class _SparkLocalViewerPageState extends State<SparkLocalViewerPage> {
  late final LocalWebServer _server;

  WebViewController? _controller;
  bool _loading = true;
  String? _error;
  bool _autoRotate = false;

  String? get _modelUrl {
    final modelPath = widget.modelPath;
    if (modelPath == null || modelPath.isEmpty) return null;
    return '/models/${Uri.encodeComponent(modelPath.split(Platform.pathSeparator).last)}';
  }

  @override
  void initState() {
    super.initState();
    _server = LocalWebServer(
      modelFile: widget.modelPath == null ? null : File(widget.modelPath!),
    );
    _initViewer();
  }

  Future<void> _initViewer() async {
    try {
      final localUrl = await _server.start();

      final controller = WebViewController();
      controller
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.black)
        ..addJavaScriptChannel(
          'FlutterBridge',
          onMessageReceived: (JavaScriptMessage message) {
            debugPrint('From Spark Web: ${message.message}');
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) {
              if (mounted) {
                setState(() {
                  _loading = true;
                  _error = null;
                });
              }
            },
            onPageFinished: (_) {
              if (mounted) {
                setState(() {
                  _loading = false;
                });
              }
              final modelUrl = _modelUrl;
              if (modelUrl != null) {
                controller.runJavaScript('''
                  (() => {
                    const modelUrl = "$modelUrl";
                    let tries = 0;
                    const load = () => {
                      if (window.loadSplat) {
                        window.loadSplat(modelUrl);
                        return;
                      }
                      if (tries++ < 20) {
                        window.setTimeout(load, 100);
                      }
                    };
                    load();
                  })();
                  ''');
              }
            },
            onWebResourceError: (WebResourceError error) {
              if (mounted) {
                setState(() {
                  _error = error.description;
                  _loading = false;
                });
              }
            },
          ),
        );
      await controller.loadRequest(localUrl);

      if (!mounted) return;

      setState(() {
        _controller = controller;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _resetCamera() async {
    await _controller?.runJavaScript(
      'window.resetCamera && window.resetCamera();',
    );
  }

  Future<void> _toggleAutoRotate() async {
    final next = !_autoRotate;

    await _controller?.runJavaScript(
      'window.setAutoRotate && window.setAutoRotate($next);',
    );

    if (mounted) {
      setState(() {
        _autoRotate = next;
      });
    }
  }

  Future<void> _setRotateOnlyMode() async {
    await _controller?.runJavaScript(
      'window.setControlMode && window.setControlMode("rotateOnly");',
    );
  }

  Future<void> _setFreeViewMode() async {
    await _controller?.runJavaScript(
      'window.setControlMode && window.setControlMode("view");',
    );
  }

  @override
  void dispose() {
    _server.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text('素材整理', style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            if (controller != null) WebViewWidget(controller: controller),

            if (_loading) const Center(child: CircularProgressIndicator()),

            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

            if (controller != null)
              Positioned(
                right: 16,
                bottom: 24,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'reset_camera',
                      onPressed: _resetCamera,
                      child: const Icon(Icons.center_focus_strong),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton.small(
                      heroTag: 'auto_rotate',
                      onPressed: _toggleAutoRotate,
                      child: Icon(_autoRotate ? Icons.pause : Icons.threesixty),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton.small(
                      heroTag: 'rotate_only',
                      onPressed: _setRotateOnlyMode,
                      child: const Icon(Icons.screen_rotation),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton.small(
                      heroTag: 'free_view',
                      onPressed: _setFreeViewMode,
                      child: const Icon(Icons.open_with),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
