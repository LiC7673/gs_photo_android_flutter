import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/config/app_config.dart';
import '../../core/config/api_config.dart';
import '../../core/state/language_state.dart';
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
        widget.modelUrl ?? '${ApiPaths.baseUrl}${AppConfig.previewPath}';

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
    context.watch<LanguageState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('viewer.web.title')),
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
