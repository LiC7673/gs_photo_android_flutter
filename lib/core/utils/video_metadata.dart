import 'dart:io';

import 'package:flutter/services.dart';

class VideoMetadata {
  static const MethodChannel _channel = MethodChannel('gs/media_info');

  static Future<int?> frameCount(String path) async {
    if (path.trim().isEmpty || !File(path).existsSync()) return null;
    try {
      final value = await _channel.invokeMethod<int>(
        'getVideoFrameCount',
        {'path': path},
      );
      return value;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
