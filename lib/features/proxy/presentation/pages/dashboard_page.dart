import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/features/proxy/presentation/providers/proxy_providers.dart';
import 'package:llm_proxy/features/settings/presentation/providers/settings_providers.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proxyState = ref.watch(proxyProvider);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('仪表盘')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              proxyState.isRunning ? Icons.cloud_done : Icons.cloud_off,
              size: 80,
              color: proxyState.isRunning ? Colors.green : Colors.grey,
            ),
            const SizedBox(height: 20),
            Text(
              proxyState.isRunning ? '代理服务已运行' : '代理服务未运行',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Text('当前代理端口: ${settings.proxyPort}', style: const TextStyle(fontSize: 16)),
            if (proxyState.error != null) ...[
              const SizedBox(height: 12),
              Text(proxyState.error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: proxyState.isLoading
                  ? null
                  : () => ref.read(proxyProvider.notifier).toggle(),
              icon: proxyState.isLoading
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(proxyState.isRunning ? Icons.stop : Icons.play_arrow),
              label: Text(proxyState.isRunning ? '停止服务' : '启动服务'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
