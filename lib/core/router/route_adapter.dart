import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'route_config.dart';
import '../../main.dart';
import '../../features/main_page/main_page.dart';
import '../../features/task_page/task_page.dart';
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
      routes: [
        // 顶级路由 (如登录)
        ..._convertToGoRoutes(appRouteTree),

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
                  routes: _convertToGoRoutes(featureRoutes), // 挂载功能路由在首页分支下
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
