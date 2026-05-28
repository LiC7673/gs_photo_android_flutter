import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/widgets/bar/custom_nav_bar.dart';
import 'core/widgets/background/sci_fi_background.dart';
import 'core/router/route_adapter.dart';
import 'core/router/route_config.dart';
import 'core/state/task_state.dart';
import 'package:go_router/go_router.dart';

const Color _appBackgroundColor = Color(0xFF03081C);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: _appBackgroundColor,
      systemNavigationBarColor: _appBackgroundColor,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => TaskState())],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'GS App',
      routerConfig: RouteAdapter.createRouter(),
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _appBackgroundColor,
        canvasColor: _appBackgroundColor,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00C6FF),
          brightness: Brightness.dark,
          surface: _appBackgroundColor,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: _appBackgroundColor,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
        ),
      ),
      builder: (context, child) {
        return ColoredBox(
          color: _appBackgroundColor,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

class MainNavigationWrapper extends StatelessWidget {
  const MainNavigationWrapper({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentPath = GoRouterState.of(context).uri.path;
    final tabRootPaths = {
      homeTabPath,
      taskTabPath,
      recommendationTabPath,
      profileTabPath,
    };
    final isAtTabRoot = tabRootPaths.contains(currentPath);

    return PopScope(
      canPop: !isAtTabRoot,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        if (navigationShell.currentIndex != 0) {
          navigationShell.goBranch(0);
        }
      },
      child: SciFiBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(bottom: false, child: navigationShell),
          bottomNavigationBar: CustomNavBar(
            currentIndex: navigationShell.currentIndex,
            onTap: _onTap,
          ),
        ),
      ),
    );
  }
}
