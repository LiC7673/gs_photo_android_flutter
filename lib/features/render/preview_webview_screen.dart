import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/config/app_config.dart';

class PreviewWebViewScreen extends StatefulWidget {
  final String? modelUrl;

  const PreviewWebViewScreen({super.key, this.modelUrl});

  @override
  State<PreviewWebViewScreen> createState() => _PreviewWebViewScreenState();
}

class _PreviewWebViewScreenState extends State<PreviewWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    final String modelPath =
        widget.modelUrl ?? '${AppConfig.baseUrl}${AppConfig.previewPath}';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
            // 页面加载完成后注入模型地址并触发初始化
            _controller.runJavaScript("window.initViewer('$modelPath', true);");
          },
        ),
      )
      ..loadFlutterAsset('assets/web/index.html');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('3DGS Web 预览'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
