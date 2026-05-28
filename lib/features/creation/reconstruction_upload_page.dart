import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../core/network/reconstruction_service.dart';
import '../../core/network/upload_service.dart';
import '../../core/state/task_state.dart';
import '../../core/widgets/background/sci_fi_background.dart';
import '../../core/widgets/buttons/gradient_button.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class ReconstructionUploadPage extends StatefulWidget {
  final List<XFile>? images;
  final String? taskName;
  final Map<String, dynamic>? params;

  const ReconstructionUploadPage({
    super.key,
    this.images,
    this.taskName,
    this.params,
  });

  @override
  State<ReconstructionUploadPage> createState() =>
      _ReconstructionUploadPageState();
}

class _ReconstructionUploadPageState extends State<ReconstructionUploadPage> {
  final ReconstructionService _reconstructionService = ReconstructionService();
  final UploadService _uploadService = UploadService();
  final ImagePicker _picker = ImagePicker();

  List<XFile> _selectedImages = [];
  String _currentStatus =
      'ready'; // ready, compressing, uploading, processing, completed, failed
  String? _taskId;
  double _progress = 0.0;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    if (widget.images != null && widget.images!.isNotEmpty) {
      _selectedImages = List.from(widget.images!);
      // 延迟一帧执行，确保组件已挂载
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startProcess();
      });
    }
  }

  Future<void> _pickImages() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() {
        _selectedImages = images;
      });
    }
  }

  Future<String?> _compressImages() async {
    setState(() {
      _currentStatus = 'compressing';
      _progress = 0.0;
    });

    try {
      final encoder = ZipFileEncoder();
      final directory = await getTemporaryDirectory();
      final zipPath = p.join(
        directory.path,
        'upload_${DateTime.now().millisecondsSinceEpoch}.zip',
      );

      encoder.create(zipPath);
      for (var image in _selectedImages) {
        encoder.addFile(File(image.path));
      }
      encoder.close();

      return zipPath;
    } catch (e) {
      debugPrint('压缩失败: $e');
      return null;
    }
  }

  Future<void> _startProcess() async {
    if (_selectedImages.isEmpty) return;

    final taskState = Provider.of<TaskState>(context, listen: false);
    final String localTaskId = DateTime.now().millisecondsSinceEpoch.toString();

    // 创建初始任务对象 (草稿 -> 开始压缩)
    final initialTask = ProcessingTask(
      taskId: localTaskId,
      title: widget.taskName ?? '未命名任务',
      params: widget.params ?? {},
      files: _selectedImages
          .map(
            (f) => StorageFile(
              fileId: f.name,
              localPath: f.path,
              status: FileSyncStatus.localOnly,
              md5: '', // 初始占位
              size: 0,
            ),
          )
          .toList(),
      status: TaskStatus.draft,
      createdAt: DateTime.now(),
    );
    taskState.upsertTask(initialTask);

    // 1. 压缩图片
    final zipPath = await _compressImages();
    if (zipPath == null) {
      taskState.updateTaskStatus(localTaskId, TaskStatus.failed);
      setState(() => _currentStatus = 'failed');
      return;
    }

    // 2. 分片上传
    setState(() {
      _currentStatus = 'uploading';
      _progress = 0.0;
    });
    taskState.updateTaskStatus(localTaskId, TaskStatus.uploadingFiles);

    try {
      final mergeRes = await _uploadService.uploadFile(
        zipPath,
        onProgress: (p) => setState(() => _progress = p),
      );

      // 3. 启动重建任务
      setState(() {
        _currentStatus = 'processing';
        _progress = 0.1;
      });
      taskState.updateTaskStatus(localTaskId, TaskStatus.pending);

      final serverTaskId = await _reconstructionService.startReconstruction(
        storageKey: mergeRes.storageKey,
        extraParams: {
          'task_name': widget.taskName ?? '未命名任务',
          'type': widget.params?['type'] ?? 'object',
          'resolution': widget.params?['resolution'] ?? 0.5,
          'algorithm': widget.params?['algorithm'] ?? 'AnySplat',
          "cuda_device": "1",
          "python_path": "/data1/lzh/anaconda3/envs/anysplat/bin/python",
          "anysplat_path": "/data1/lzh/lzy/AnySplat",
        },
      );

      if (serverTaskId == null) {
        taskState.updateTaskStatus(localTaskId, TaskStatus.failed);
        setState(() => _currentStatus = 'failed');
        return;
      }

      // 将本地临时 ID 映射为服务端真正的任务 ID (或者保持关联)
      // 这里为了简单，我们更新状态并记录服务端 ID
      taskState.upsertTask(
        initialTask.copyWith(
          status: TaskStatus.processing,
          updatedAt: DateTime.now(),
        ),
      );

      setState(() {
        _taskId = serverTaskId;
      });

      // 4. 轮询状态
      _startPolling(serverTaskId, localTaskId);

      // 清理临时 zip
      final zipFile = File(zipPath);
      if (await zipFile.exists()) await zipFile.delete();
    } catch (e) {
      debugPrint('处理流程失败: $e');
      taskState.updateTaskStatus(localTaskId, TaskStatus.failed);
      setState(() => _currentStatus = 'failed');
    }
  }

  void _startPolling(String serverTaskId, String localTaskId) {
    final taskState = Provider.of<TaskState>(context, listen: false);

    _statusTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      final statusData = await _reconstructionService.checkStatus(serverTaskId);
      if (statusData == null) return;

      final status = statusData['status'];
      debugPrint('任务状态: $status');

      setState(() {
        if (status == 'completed') {
          timer.cancel();
          _currentStatus = 'completed';
          _progress = 1.0;
          taskState.updateTaskStatus(localTaskId, TaskStatus.completed);
          _downloadAndPreview(serverTaskId);
        } else if (status == 'failed') {
          timer.cancel();
          _currentStatus = 'failed';
          taskState.updateTaskStatus(localTaskId, TaskStatus.failed);
        } else {
          // 模拟进度增长 (0.1 ~ 0.9)
          if (_progress < 0.9) _progress += 0.05;
          taskState.updateTaskStatus(localTaskId, TaskStatus.processing);
        }
      });
    });
  }

  Future<void> _downloadAndPreview(String taskId) async {
    // 这里可以添加下载并跳转预览逻辑
    debugPrint('任务完成，ID: $taskId');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('重建完成！模型已准备就绪。')));
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('启动 3DGS 重建', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
      body: SciFiBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 80),
                  if (_currentStatus == 'ready') ...[
                    const Icon(
                      Icons.cloud_upload_outlined,
                      size: 80,
                      color: Color(0xFF00C6FF),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _selectedImages.isEmpty
                          ? '请选择需要重建的图片'
                          : '已选择 ${_selectedImages.length} 张图片',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 40),
                    ElevatedButton(
                      onPressed: _pickImages,
                      child: const Text('从相册选择图片'),
                    ),
                    const SizedBox(height: 20),
                    if (_selectedImages.isNotEmpty)
                      GradientButton(
                        label: '开始上传并重建',
                        onPressed: _startProcess,
                        height: 56,
                      ),
                  ] else ...[
                    _buildStatusUI(context),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusUI(BuildContext context) {
    String message = '';
    IconData icon = Icons.sync;
    Color color = const Color(0xFF00C6FF);

    switch (_currentStatus) {
      case 'compressing':
        message = '正在打包素材...';
        icon = Icons.folder_zip_outlined;
        break;
      case 'uploading':
        message = '正在分片上传...';
        icon = Icons.cloud_upload;
        break;
      case 'processing':
        message = '算法正在重建 3D 点云...';
        icon = Icons.memory;
        break;
      case 'completed':
        message = '重建成功！';
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case 'failed':
        message = '处理失败，请重试';
        icon = Icons.error;
        color = Colors.red;
        break;
    }

    return Column(
      children: [
        Icon(icon, size: 80, color: color),
        const SizedBox(height: 32),
        Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 40),
        LinearProgressIndicator(
          value: _progress,
          backgroundColor: Colors.white10,
          color: color,
          minHeight: 8,
        ),
        const SizedBox(height: 20),
        Text(
          '${(_progress * 100).toInt()}%',
          style: TextStyle(color: color, fontSize: 16),
        ),
        if (_currentStatus == 'completed' && _taskId != null) ...[
          const SizedBox(height: 12),
          Text(
            '任务 ID: $_taskId',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
        if (_currentStatus == 'failed')
          TextButton(
            onPressed: () => setState(() => _currentStatus = 'ready'),
            child: const Text('返回重试', style: TextStyle(color: Colors.white70)),
          ),
      ],
    );
  }
}
