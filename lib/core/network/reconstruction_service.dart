import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../config/app_config.dart';
import 'dio_adapter.dart';

class ReconstructionService {
  final DioAdapter _adapter = DioAdapter();

  /// 1. 启动重建 (使用已上传的文件 ID 或 Storage Key)
  Future<String?> startReconstruction({
    required String storageKey,
    Map<String, dynamic>? extraParams,
  }) async {
    try {
      final response = await _adapter.post(
        AppConfig.reconstructionStaPath,
        data: {
          "storage_key": storageKey,
          "params": jsonEncode(
            extraParams ??
                {
                  "cuda_device": "1",
                  "python_path":
                      "/data1/lzh/anaconda3/envs/anysplat/bin/python",
                  "anysplat_path": "/data1/lzh/lzy/AnySplat",
                },
          ),
        },
      );

      return response.data["task_id"];
    } catch (e) {
      debugPrint('启动重建失败: $e');
      return null;
    }
  }

  /// 2. 查询状态
  Future<Map<String, dynamic>?> checkStatus(String taskId) async {
    try {
      final response = await _adapter.get(
        "${AppConfig.reconstructionStatusPath}/$taskId",
      );
      return response.data;
    } catch (e) {
      debugPrint('查询状态失败: $e');
      return null;
    }
  }

  /// 3. 下载模型结果
  Future<File?> downloadResult(String taskId) async {
    try {
      final response = await _adapter.get(
        "${AppConfig.reconstructionDownloadPath}/$taskId",
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.statusCode == 200) {
        final directory = await getApplicationDocumentsDirectory();
        final filePath = p.join(directory.path, 'reconstructed_$taskId.ply');
        final file = File(filePath);
        await file.writeAsBytes(response.data);
        return file;
      }
      return null;
    } catch (e) {
      debugPrint('下载模型失败: $e');
      return null;
    }
  }
}
