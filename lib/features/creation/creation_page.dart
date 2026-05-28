import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/widgets/background/sci_fi_background.dart';
import '../../core/widgets/buttons/gradient_button.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/route_config.dart';

class CreationPage extends StatefulWidget {
  const CreationPage({super.key});

  @override
  State<CreationPage> createState() => _CreationPageState();
}

class _CreationPageState extends State<CreationPage> {
  // 1. 任务名称
  final TextEditingController _taskNameController = TextEditingController(
    text: '我的 3D 重建项目',
  );

  // 2. 重建类型
  String _reconstructionType = 'object'; // 'object' or 'scene'

  // 3. 重建参数
  double _resolutionScale = 0.5; // 0.1 - 1.0
  String _selectedAlgorithm = 'AnySplat';
  final List<String> _algorithms = [
    'AnySplat',
    '3DGS-Vanilla',
    'Mip-Splatting',
  ];

  // 4. 图片素材
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _selectedImages = [];

  @override
  void dispose() {
    _taskNameController.dispose();
    super.dispose();
  }

  Future<void> _pickFromGallery() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() {
        _selectedImages.addAll(images);
      });
    }
  }

  Future<void> _takeFromCamera() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() {
        _selectedImages.add(image);
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool canStart = _selectedImages.length > 5;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text(
          '创建 3D 任务',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. 任务名称
                _buildSectionTitle('任务名称'),
                _buildGlassCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: TextField(
                    controller: _taskNameController,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: '输入任务名称...',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                      border: InputBorder.none,
                      icon: const Icon(
                        Icons.edit_note,
                        color: Color(0xFF00C6FF),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // 2. 重建类型
                _buildSectionTitle('重建类型'),
                Row(
                  children: [
                    Expanded(
                      child: _buildTypeCard(
                        context,
                        '物体类',
                        Icons.inventory_2_outlined,
                        _reconstructionType == 'object',
                        () => setState(() => _reconstructionType = 'object'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTypeCard(
                        context,
                        '场景类',
                        Icons.landscape_outlined,
                        _reconstructionType == 'scene',
                        () => setState(() => _reconstructionType = 'scene'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // 3. 重建参数
                _buildSectionTitle('重建参数'),
                _buildGlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _buildParamRow(
                        '压缩分辨率 (${_resolutionScale.toStringAsFixed(1)})',
                        _buildResolutionSlider(context),
                      ),
                      const Divider(color: Colors.white10, height: 32),
                      _buildParamRow('算法选择', _buildAlgorithmSelector(context)),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // 4. 上传文件 (图片)
                _buildSectionTitle('素材管理 (${_selectedImages.length} 张)'),
                _buildGlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _buildActionButton(
                            context,
                            '本地相册',
                            Icons.photo_library_outlined,
                            _pickFromGallery,
                          ),
                          const SizedBox(width: 12),
                          _buildActionButton(
                            context,
                            '现场拍摄',
                            Icons.camera_alt_outlined,
                            _takeFromCamera,
                          ),
                        ],
                      ),
                      if (_selectedImages.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 96,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _selectedImages.length,
                            itemBuilder: (context, index) {
                              return _buildImageThumbnail(context, index);
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                GradientButton(
                  label: canStart ? '开始 3DGS 重建' : '请至少选择 6 张图片',
                  onPressed: canStart
                      ? () {
                          context.push(
                            '$homeTabPath/$creationConfigPath/$uploadProgressPath',
                            extra: {
                              'images': _selectedImages,
                              'taskName': _taskNameController.text,
                              'type': _reconstructionType,
                              'resolution': _resolutionScale,
                              'algorithm': _selectedAlgorithm,
                            },
                          );
                        }
                      : null,
                  height: 56,
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildGlassCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.symmetric(
      horizontal: 20,
      vertical: 16,
    ),
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: padding,
            color: const Color(0xFFFFFFFF).withValues(alpha: 0.05),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildTypeCard(
    BuildContext context,
    String label,
    IconData icon,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF00C6FF)
                : Colors.white.withValues(alpha: 0.1),
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? const Color(0xFF00C6FF).withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.05),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFF00C6FF) : Colors.white70,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParamRow(String label, Widget action) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 16)),
        action,
      ],
    );
  }

  Widget _buildResolutionSlider(BuildContext context) {
    return SizedBox(
      width: 140,
      child: SliderTheme(
        data: SliderThemeData(
          trackHeight: 2,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          activeTrackColor: const Color(0xFF00C6FF),
          thumbColor: const Color(0xFF00C6FF),
          inactiveTrackColor: Colors.white10,
        ),
        child: Slider(
          value: _resolutionScale,
          min: 0.1,
          max: 1.0,
          onChanged: (v) => setState(() => _resolutionScale = v),
        ),
      ),
    );
  }

  Widget _buildAlgorithmSelector(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButton<String>(
        value: _selectedAlgorithm,
        dropdownColor: const Color(0xFF1C0305),
        underline: const SizedBox(),
        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70),
        items: _algorithms.map((String value) {
          return DropdownMenuItem<String>(
            value: value,
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          );
        }).toList(),
        onChanged: (newValue) {
          if (newValue != null) setState(() => _selectedAlgorithm = newValue);
        },
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: const Color(0xFF00C6FF), size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageThumbnail(BuildContext context, int index) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        image: DecorationImage(
          image: FileImage(File(_selectedImages[index].path)),
          fit: BoxFit.cover,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: () => _removeImage(index),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
