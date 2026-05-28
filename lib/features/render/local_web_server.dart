import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

class LocalWebServer {
  HttpServer? _server;

  Future<Uri> start() async {
    if (_server != null) {
      return Uri.parse('http://127.0.0.1:${_server!.port}/');
    }

    final webDir = await _prepareWebFiles();

    final handler = createStaticHandler(
      webDir.path,
      defaultDocument: 'index.html',
      serveFilesOutsidePath: false,
    );

    _server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);

    return Uri.parse('http://127.0.0.1:${_server!.port}/');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<Directory> _prepareWebFiles() async {
    final supportDir = await getApplicationSupportDirectory();
    final webDir = Directory(p.join(supportDir.path, 'spark_web'));

    if (await webDir.exists()) {
      await webDir.delete(recursive: true);
    }

    await webDir.create(recursive: true);

    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);

    final assetPaths = manifest
        .listAssets()
        .where((assetPath) => assetPath.startsWith('assets/web_demo/'))
        .where((assetPath) => !assetPath.endsWith('/'))
        .toList();

    if (assetPaths.isEmpty) {
      throw StateError(
        '没有找到 assets/web_demo/ 下的资源。请检查 pubspec.yaml 的 assets 配置。',
      );
    }

    for (final assetPath in assetPaths) {
      final byteData = await rootBundle.load(assetPath);

      final relativePath = assetPath.replaceFirst('assets/web_demo/', '');
      final outputFile = File(p.join(webDir.path, relativePath));

      await outputFile.parent.create(recursive: true);

      await outputFile.writeAsBytes(
        byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
        flush: true,
      );
    }

    final indexFile = File(p.join(webDir.path, 'index.html'));
    if (!await indexFile.exists()) {
      throw StateError(
        '没有复制到 index.html。请确认 assets/spark_web/index.html 存在，并已在 pubspec.yaml 注册。',
      );
    }

    return webDir;
  }
}
