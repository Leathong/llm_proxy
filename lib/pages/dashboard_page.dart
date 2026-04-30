import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/config_provider.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 监听 ConfigProvider 状态变化
    final configProvider = context.watch<ConfigProvider>();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('仪表盘'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              configProvider.isProxyRunning ? Icons.cloud_done : Icons.cloud_off,
              size: 80,
              color: configProvider.isProxyRunning ? Colors.green : Colors.grey,
            ),
            const SizedBox(height: 20),
            Text(
              configProvider.isProxyRunning ? '代理服务已运行' : '代理服务未运行',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            if (!configProvider.isInitialized)
              const CircularProgressIndicator()
            else ...[
              Text('当前代理端口: ${configProvider.proxyPort}', style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: () {
                  configProvider.toggleProxyServer();
                },
                icon: Icon(configProvider.isProxyRunning ? Icons.stop : Icons.play_arrow),
                label: Text(configProvider.isProxyRunning ? '停止服务' : '启动服务'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
