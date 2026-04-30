import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

import 'providers/config_provider.dart';
import 'providers/log_provider.dart';
import 'pages/dashboard_page.dart';
import 'pages/config_page.dart';
import 'pages/log_page.dart';
import 'pages/settings_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化窗口管理器
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(900, 600),
    minimumSize: Size(700, 500),
    center: true,
    title: 'LLM Proxy',
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // 全局捕获 Flutter 框架抛出的错误并打印到控制台
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('【Flutter全局错误】: ${details.exception}\n${details.stack}');
  };

  // 全局捕获异步未处理的错误并打印到控制台
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('【Platform全局异步错误】: $error\n$stack');
    return true;
  };

  final logProvider = LogProvider();
  runApp(
    // 注册全局状态管理
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: logProvider),
        ChangeNotifierProvider(create: (_) => ConfigProvider(logProvider: logProvider)),
      ],
      child: const LLMProxyApp(),
    ),
  );
}

class LLMProxyApp extends StatelessWidget {
  const LLMProxyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LLM Proxy',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true, // 启用 Material 3 设计风格
      ),
      home: const SelectionArea(child: MainNavigationScreen()),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// 主导航页，包含侧边栏和主内容区域，同时管理窗口关闭拦截和系统托盘
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen>
    with WindowListener, TrayListener {
  // 当前选中的页面索引
  int _selectedIndex = 0;

  // 所有页面的列表
  final List<Widget> _pages = const [
    DashboardPage(),
    ConfigPage(),
    LogPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    // 监听窗口事件（用于拦截关闭操作）
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
    // 监听托盘事件
    trayManager.addListener(this);
    _initSystemTray();
  }

  /// 初始化系统托盘图标和右键菜单
  Future<void> _initSystemTray() async {
    await trayManager.setIcon('assets/tray_icon.png');
    Menu menu = Menu(
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

  // 拦截窗口关闭：隐藏窗口而非退出应用
  @override
  void onWindowClose() async {
    // 使用 orderOut 风格的隐藏不会触发 isVisible 问题，
    // 但配合 setPreventClose(true) 能确保窗口可恢复
    await windowManager.hide();
  }

  /// 显示并聚焦窗口的辅助方法，由托盘点击和菜单项共用
  Future<void> _showWindow() async {
    // 先检查窗口是否可见，若不可见则显示
    if (!await windowManager.isVisible()) {
      await windowManager.show();
    }
    // 确保窗口置前并聚焦
    await windowManager.focus();
  }

  // 点击托盘图标：显示窗口并聚焦
  @override
  void onTrayIconMouseDown() async {
    await _showWindow();
  }

  // 右键点击托盘图标：弹出菜单
  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  // 处理托盘菜单项点击
  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show_window':
        await _showWindow();
        break;
      case 'exit_app':
        // 彻底退出：销毁托盘并关闭应用
        await trayManager.destroy();
        await windowManager.setPreventClose(false);
        await windowManager.close();
        exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('仪表盘'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.rule_folder_outlined),
                selectedIcon: Icon(Icons.rule_folder),
                label: Text('配置管理'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.list_alt_outlined),
                selectedIcon: Icon(Icons.list_alt),
                label: Text('日志查看'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('设置与证书'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: _pages[_selectedIndex],
          ),
        ],
      ),
    );
  }
}
