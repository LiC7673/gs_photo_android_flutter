import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/login/login_screen.dart';
import '../../features/camera/camera_guide_screen.dart';
import '../../features/creation/creation_page.dart';
import '../../features/render/preview_webview_screen.dart';
import '../../features/render/local_viewer_page.dart';

/// 1. 定义路由节点模型
class AppRouteNode {
  final String path; // 相对路径
  final Widget Function(BuildContext, GoRouterState) builder; // 页面构建器
  final List<AppRouteNode> children; // 子路由

  AppRouteNode({
    required this.path,
    required this.builder,
    this.children = const [],
  });
}

/// 2. 常量定义
const String rootPath = '/';
const String loginPath = '/login';
const String mainPath = '/main';

// Tab 路径
const String homeTabPath = '/home';
const String taskTabPath = '/task';
const String recommendationTabPath = '/recommendation';
const String messageTabPath = '/message';
const String profileTabPath = '/profile';

// 功能页面路径 (相对于其父路径)
const String cameraGuidePath = 'camera_guide';
const String creationConfigPath = 'creation_config';
const String uploadProgressPath = 'upload_progress';
const String previewPath = 'preview';

const String localViewerPath = 'local_viewer';
const String taskDetailPath = 'detail';

/// 3. 核心路由配置树 (非 Shell 部分)
final List<AppRouteNode> appRouteTree = [
  // 登录页 (独立)
  AppRouteNode(
    path: '/login',
    builder: (context, state) => const LoginScreen(),
  ),
];

/// 4. 功能子路由 (通常挂载在 Main 之下，或者根据需要平级)
final List<AppRouteNode> featureRoutes = [
  // 相机引导
  AppRouteNode(
    path: cameraGuidePath,
    builder: (context, state) => const CameraGuideScreen(),
  ),
  // 物体创建配置
  AppRouteNode(
    path: creationConfigPath,
    builder: (context, state) => const CreationPage(),
  ),
  // 模型预览 (支持传参)
  AppRouteNode(
    path: previewPath,
    builder: (context, state) {
      final modelUrl = state.uri.queryParameters['modelUrl'];
      return PreviewWebViewScreen(modelUrl: modelUrl);
    },
  ),
  // 本地查看器
  AppRouteNode(
    path: localViewerPath,
    builder: (context, state) {
      final extra = state.extra;
      return SparkLocalViewerPage(modelPath: extra is String ? extra : null);
    },
  ),
];
