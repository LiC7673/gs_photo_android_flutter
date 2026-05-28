import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/widgets/buttons/gradient_button.dart';
import '../../core/widgets/buttons/square_glass_button.dart';
import '../../core/widgets/buttons/glass_button.dart';
import '../../core/widgets/carousel/custom_carousel.dart';
import '../../core/widgets/task/task_card.dart';
import '../../core/network/upload_service.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/route_config.dart';
import 'dart:convert';
import 'dart:ui';

import '../../core/network/upload_models.dart';
import 'package:crypto/crypto.dart';
import 'dart:io';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final UploadService _uploadService = UploadService();
  final ImagePicker _picker = ImagePicker();
  String _testResult = '';
  bool _isTesting = false;

  Future<void> _runUploadTest() async {
    setState(() {
      _isTesting = true;
      _testResult = '正在选择图片...';
    });

    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) {
        setState(() {
          _isTesting = false;
          _testResult = '已取消图片选择';
        });
        return;
      }

      final file = File(image.path);
      final fileSize = await file.length();
      final bytes = await file.readAsBytes();

      const encoder = JsonEncoder.withIndent('  ');
      String log = '--- [1/3] 初始化上传 ---\n';
      setState(() => _testResult = log);

      // 1. 初始化
      final initRes = await _uploadService.initializeUpload(image.path);
      log += '初始化成功:\n${encoder.convert(initRes)}\n\n';
      setState(() => _testResult = log);

      final uploadId = initRes.uploadId;
      final chunkSize = initRes.chunkSize;
      final totalChunks = initRes.totalChunks;
      List<MergeRequestPart> parts = [];

      log += '--- [2/3] 分片上传 ($totalChunks) ---\n';
      setState(() => _testResult = log);

      // 2. 分片上传
      for (int i = 0; i < totalChunks; i++) {
        int start = i * chunkSize;
        int end = (i + 1) * chunkSize;
        if (end > fileSize) end = fileSize;
        final chunkData = bytes.sublist(start, end);

        final chunkRes = await _uploadService.uploadChunk(
          uploadId: uploadId,
          chunkIndex: i,
          chunkData: chunkData,
        );

        parts.add(MergeRequestPart(chunkIndex: i, etag: chunkRes.etag));
        log += '分片 $i 成功: etag=${chunkRes.etag}\n';
        setState(() => _testResult = log);
      }

      log += '\n--- [3/3] 合并分片 ---\n';
      setState(() => _testResult = log);

      // 3. 合并
      final fileHash = md5.convert(bytes).toString();
      final mergeRes = await _uploadService.mergeChunks(
        uploadId: uploadId,
        expectedSize: fileSize,
        expectedHash: fileHash,
        parts: parts,
      );

      log +=
          '合并成功:\n${encoder.convert({'file_id': mergeRes.fileId, 'file_hash': mergeRes.fileHash, 'storage_key': mergeRes.storageKey, 'verified': mergeRes.verified})}\n';

      setState(() {
        _isTesting = false;
        _testResult = log;
      });
    } catch (e) {
      setState(() {
        _isTesting = false;
        _testResult += '\n[ERROR] 操作失败:\n$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.transparent, // 背景已由外层容器处理
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CustomCarousel(
                images: const [
                  'https://images.unsplash.com/photo-1451187580459-43490279c0fa?q=80&w=2072&auto=format&fit=crop',
                  'https://images.unsplash.com/photo-1550745165-9bc0b252726f?q=80&w=2070&auto=format&fit=crop',
                  'https://images.unsplash.com/photo-1558591710-4b4a1ae0f04d?q=80&w=1887&auto=format&fit=crop',
                ],
                height: 180,
              ),
              const SizedBox(height: 24),
              GradientButton(
                label: '开始创建',
                onPressed: () {
                  context.push('$homeTabPath/$creationConfigPath');
                },
                height: 56,
              ),
              const TaskCard(
                title: '家庭生日相册',
                statusText: 'AI 重建中',
                progress: 0.78,
                timeRemaining: '2 分钟',
                imageUrl:
                    'https://images.unsplash.com/photo-1513364776144-60967b0f800f?q=80&w=2071&auto=format&fit=crop',
              ),

              // --- 测试上传服务部分 ---
              const SizedBox(height: 16),
              GlassButton(
                label: _isTesting ? '正在测试...' : '测试文件上传服务',
                icon: _isTesting ? Icons.sync : Icons.cloud_upload_outlined,
                onPressed: _isTesting ? () {} : _runUploadTest,
                height: 48,
                opacity: 0.1,
              ),
              if (_testResult.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildTestResultDisplay(),
              ],

              // -----------------------
              const SizedBox(height: 24),
              // 横向排列四个方形磨砂按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SquareGlassButton(
                    label: '拍摄引导',
                    icon: Icons.camera_alt_outlined,
                    onPressed: () {
                      context.push('$homeTabPath/$cameraGuidePath');
                    },
                    size: 76,
                  ),
                  SquareGlassButton(
                    label: '素材整理',
                    icon: Icons.auto_awesome_motion_outlined,
                    onPressed: () =>
                        context.push('$homeTabPath/$localViewerPath'),
                    size: 76,
                  ),
                  SquareGlassButton(
                    label: '云端同步',
                    icon: Icons.cloud_done_outlined,
                    onPressed: () => debugPrint('点击：云端同步'),
                    size: 76,
                  ),
                  SquareGlassButton(
                    label: '使用说明',
                    icon: Icons.help_outline_rounded,
                    onPressed: () => debugPrint('点击：使用说明'),
                    size: 76,
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTestResultDisplay() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '服务器响应测试结果:',
                style: TextStyle(
                  color: Color(0xFF00C6FF),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                _testResult,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
