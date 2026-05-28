import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../state/user_state.dart';
import 'route_config.dart';
import '../../main.dart';
import '../../features/camera/camera_guide_screen.dart';
import '../../features/creation/creation_page.dart';
import '../../features/main_page/main_page.dart';
import '../../features/render/local_viewer_page.dart';
import '../../features/render/preview_webview_screen.dart';
import '../../features/task_page/task_page.dart';
import '../../features/task_page/task_detail_page.dart';
import '../../features/recommendation_page/recommendation_page.dart';
import '../../features/profile/profile_page.dart';

class RouteAdapter {
  static const Color _routeBackgroundColor = Color(0xFF03081C);

  static Widget _withRouteBackground(Widget child) {
    return ColoredBox(color: _routeBackgroundColor, child: child);
  }

  /// 递归将自定义的 AppRouteNode 转换为 GoRoute
  static List<GoRoute> _convertToGoRoutes(List<AppRouteNode> nodes) {
    return nodes.map((node) {
      return GoRoute(
        path: node.path,
        builder: (context, state) =>
            _withRouteBackground(node.builder(context, state)),
        routes: _convertToGoRoutes(node.children),
      );
    }).toList();
  }

  /// 生成最终给 MaterialApp 使用的 GoRouter 实例
  static GoRouter createRouter() {
    return GoRouter(
      initialLocation: loginPath,
      debugLogDiagnostics: true,
      refreshListenable: UserState.instance,
      redirect: (context, state) {
        final isLoggedIn = UserState.instance.isLoggedIn;
        final isLoggingIn = state.uri.path == loginPath;

        if (!isLoggedIn && !isLoggingIn) {
          return loginPath;
        }

        if (isLoggedIn && isLoggingIn) {
          return homeTabPath;
        }

        return null;
      },
      routes: [
        // 顶级路由 (如登录)
        ..._convertToGoRoutes(appRouteTree),

        // 二级页面：放在 Shell 外，像独立 Activity，不显示底部导航
        GoRoute(
          path: '$homeTabPath/$cameraGuidePath',
          builder: (context, state) =>
              _withRouteBackground(const CameraGuideScreen()),
        ),
        GoRoute(
          path: '$homeTabPath/$creationConfigPath',
          builder: (context, state) =>
              _withRouteBackground(const CreationPage()),
        ),
        GoRoute(
          path: '$homeTabPath/$previewPath',
          builder: (context, state) {
            final modelUrl = state.uri.queryParameters['modelUrl'];
            return _withRouteBackground(
              PreviewWebViewScreen(modelUrl: modelUrl),
            );
          },
        ),
        GoRoute(
          path: '$homeTabPath/$localViewerPath',
          builder: (context, state) {
            final extra = state.extra;
            return _withRouteBackground(
              SparkLocalViewerPage(modelPath: extra is String ? extra : null),
            );
          },
        ),
        GoRoute(
          path: '$taskTabPath/$taskDetailPath/:taskId',
          builder: (context, state) => _withRouteBackground(
            TaskDetailPage(
              taskId: state.pathParameters['taskId'] ?? '',
              initialImages: (state.extra as Map?)?['images'] as List<XFile>?,
            ),
          ),
        ),

        // 主导航 Shell 路由
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            return MainNavigationWrapper(navigationShell: navigationShell);
          },
          branches: [
            // 首页分支
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: homeTabPath,
                  builder: (context, state) =>
                      _withRouteBackground(const MainScreen()),
                ),
              ],
            ),
            // 任务分支
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: taskTabPath,
                  builder: (context, state) =>
                      _withRouteBackground(const TaskPage()),
                ),
              ],
            ),
            // 发现分支
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: recommendationTabPath,
                  builder: (context, state) =>
                      _withRouteBackground(const RecommendationPage()),
                ),
              ],
            ),
            // 消息分支 (目前占位)
            // StatefulShellBranch(
            //   routes: [
            //     GoRoute(
            //       path: messageTabPath,
            //       builder: (context, state) => const Center(
            //         child: Text('消息界面', style: TextStyle(color: Colors.white, fontSize: 24)),
            //       ),
            //     ),
            //   ],
            // ),
            // 我的分支
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: profileTabPath,
                  builder: (context, state) =>
                      _withRouteBackground(const ProfilePage()),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
