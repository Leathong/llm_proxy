import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:llm_proxy/features/proxy/presentation/pages/dashboard_page.dart';
import 'package:llm_proxy/features/rules/presentation/pages/config_page.dart';
import 'package:llm_proxy/features/logs/presentation/pages/log_page.dart';
import 'package:llm_proxy/features/settings/presentation/pages/settings_page.dart';

Page<void> _noTransitionPageBuilder<T>(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) => child,
  );
}

final GoRouter appRouter = GoRouter(
  initialLocation: '/dashboard',
  routes: [
    ShellRoute(
      builder: (context, state, child) => _NavigationShell(child: child),
      routes: [
        GoRoute(
          path: '/dashboard',
          name: 'dashboard',
          pageBuilder: (context, state) => _noTransitionPageBuilder(
            context, state, const DashboardPage(),
          ),
        ),
        GoRoute(
          path: '/rules',
          name: 'rules',
          pageBuilder: (context, state) => _noTransitionPageBuilder(
            context, state, const ConfigPage(),
          ),
        ),
        GoRoute(
          path: '/logs',
          name: 'logs',
          pageBuilder: (context, state) => _noTransitionPageBuilder(
            context, state, const LogPage(),
          ),
        ),
        GoRoute(
          path: '/settings',
          name: 'settings',
          pageBuilder: (context, state) => _noTransitionPageBuilder(
            context, state, const SettingsPage(),
          ),
        ),
      ],
    ),
  ],
);

class _NavigationShell extends StatelessWidget {
  final Widget child;
  const _NavigationShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;

    int selectedIndex;
    switch (location) {
      case '/dashboard':
        selectedIndex = 0;
      case '/rules':
        selectedIndex = 1;
      case '/logs':
        selectedIndex = 2;
      case '/settings':
        selectedIndex = 3;
      default:
        selectedIndex = 0;
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIndex,
            onDestinationSelected: (int index) {
              switch (index) {
                case 0: context.go('/dashboard');
                case 1: context.go('/rules');
                case 2: context.go('/logs');
                case 3: context.go('/settings');
              }
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
                label: Text('日志'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('设置与证书'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}
