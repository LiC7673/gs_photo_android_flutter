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
    debugPrint('[API] trigger startReconstruction storageKey=$storageKey');
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

      final taskId = response.data["task_id"];
      debugPrint('[API] result startReconstruction taskId=$taskId');
      return taskId;
    } catch (e) {
      debugPrint('[API] result startReconstruction failed error=$e');
      return null;
    }
  }

  /// 2. 查询状态
  Future<Map<String, dynamic>?> checkStatus(String taskId) async {
    debugPrint('[API] trigger checkReconstructionStatus taskId=$taskId');
    try {
      final response = await _adapter.get(
        "${AppConfig.reconstructionStatusPath}/$taskId",
      );
      debugPrint(
        '[API] result checkReconstructionStatus taskId=$taskId '
        'status=${response.data['status']}',
      );
      return response.data;
    } catch (e) {
      debugPrint('[API] result checkReconstructionStatus failed error=$e');
      return null;
    }
  }

  /// 3. 下载模型结果
  Future<File?> downloadResult(String taskId) async {
    debugPrint('[API] trigger downloadReconstructionResult taskId=$taskId');
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
        debugPrint(
          '[API] result downloadReconstructionResult taskId=$taskId '
          'path=$filePath',
        );
        return file;
      }
      debugPrint(
        '[API] result downloadReconstructionResult taskId=$taskId '
        'status=${response.statusCode}',
      );
      return null;
    } catch (e) {
      debugPrint('[API] result downloadReconstructionResult failed error=$e');
      return null;
    }
  }
}
