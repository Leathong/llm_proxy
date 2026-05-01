import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:llm_proxy/app/app.dart';
import 'package:llm_proxy/core/database/app_database.dart';
import 'package:llm_proxy/features/rules/data/repositories/drift_rule_repository.dart';
import 'package:llm_proxy/features/rules/presentation/providers/rules_providers.dart';
import 'package:llm_proxy/features/settings/presentation/providers/settings_providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 SharedPreferences
  final prefs = await SharedPreferences.getInstance();

  // 初始化 Drift 数据库
  final database = AppDatabase();

  // 从 SharedPreferences 迁移旧数据到 Drift（仅首次执行）
  final migrationRepo = DriftRuleRepository(database, prefs);
  await migrationRepo.migrateFromSharedPreferences();

  // 初始化窗口管理器
  await windowManager.ensureInitialized();
  final windowOptions = const WindowOptions(
    size: Size(900, 600),
    minimumSize: Size(700, 500),
    center: true,
    title: 'LLM Proxy',
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // 全局错误捕获
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('【Flutter全局错误】: ${details.exception}\n${details.stack}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('【Platform全局异步错误】: $error\n$stack');
    return true;
  };

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(database),
      ],
      child: const _TrayAwareApp(),
    ),
  );
}

class _TrayAwareApp extends StatefulWidget {
  const _TrayAwareApp();

  @override
  State<_TrayAwareApp> createState() => _TrayAwareAppState();
}

class _TrayAwareAppState extends State<_TrayAwareApp>
    with WindowListener, TrayListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
    trayManager.addListener(this);
    _initSystemTray();
  }

  Future<void> _initSystemTray() async {
    await trayManager.setIcon('assets/tray_icon.png');
    final menu = Menu(
      items: [
        MenuItem(key: 'show_window', label: '显示窗口'),
        MenuItem.separator(),
        MenuItem(key: 'exit_app', label: '退出'),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    await windowManager.hide();
  }

  Future<void> _showWindow() async {
    if (!await windowManager.isVisible()) {
      await windowManager.show();
    }
    await windowManager.focus();
  }

  @override
  void onTrayIconMouseDown() async {
    await _showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show_window':
        await _showWindow();
      case 'exit_app':
        await trayManager.destroy();
        await windowManager.setPreventClose(false);
        await windowManager.close();
        exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return const LLMProxyApp();
  }
}
