import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/core/theme/app_colors.dart';
import 'package:llm_proxy/features/proxy/domain/entities/active_request_info.dart';
import 'package:llm_proxy/features/proxy/presentation/providers/active_requests_providers.dart';
import 'package:llm_proxy/features/proxy/presentation/providers/proxy_providers.dart';
import 'package:llm_proxy/features/settings/presentation/providers/settings_providers.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m ${d.inSeconds.remainder(60)}s';
    } else if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    } else {
      return '${d.inSeconds}s';
    }
  }

  Future<bool> _confirmDisconnect(BuildContext context, ActiveRequestInfo info) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认断开'),
        content: Text('确定要断开模型 "${info.model}" 的请求吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('断开'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final proxyState = ref.watch(proxyProvider);
    final settings = ref.watch(settingsProvider);
    final activeRequests = ref.watch(activeRequestsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('仪表盘')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildServerStatusCard(proxyState, settings),
          const SizedBox(height: 16),
          _buildActiveRequestsSection(activeRequests),
        ],
      ),
    );
  }

  Widget _buildServerStatusCard(ProxyState proxyState, dynamic settings) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              proxyState.isRunning ? Icons.cloud_done : Icons.cloud_off,
              size: 64,
              color: proxyState.isRunning ? AppColors.success : AppColors.grey,
            ),
            const SizedBox(height: 12),
            Text(
              proxyState.isRunning ? '代理服务已运行' : '代理服务未运行',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('当前代理端口: ${settings.proxyPort}',
                style: const TextStyle(fontSize: 14, color: AppColors.grey)),
            if (proxyState.error != null) ...[
              const SizedBox(height: 8),
              Text(proxyState.error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 13)),
            ],
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: proxyState.isLoading
                  ? null
                  : () => ref.read(proxyProvider.notifier).toggle(),
              icon: proxyState.isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(proxyState.isRunning ? Icons.stop : Icons.play_arrow),
              label: Text(proxyState.isRunning ? '停止服务' : '启动服务'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveRequestsSection(List<ActiveRequestInfo> requests) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.swap_vertical_circle, size: 20),
                const SizedBox(width: 8),
                Text(
                  '进行中的请求',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: requests.isNotEmpty ? AppColors.warning : AppColors.greyUltraLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${requests.length}',
                    style: TextStyle(
                      fontSize: 12,
                      color: requests.isNotEmpty ? AppColors.whiteSoft : AppColors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (requests.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 40, color: AppColors.grey),
                    SizedBox(height: 8),
                    Text('没有进行中的请求',
                        style: TextStyle(color: AppColors.grey)),
                  ],
                ),
              ),
            )
          else
            ...requests.map((info) => _buildRequestItem(info)),
        ],
      ),
    );
  }

  Widget _buildRequestItem(ActiveRequestInfo info) {
    final elapsed = info.elapsed;
    return ListTile(
      dense: true,
      leading: const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      ),
      title: Text(
        info.model,
        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${info.method} ${info.path}',
        style: const TextStyle(fontSize: 12),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatDuration(elapsed),
            style: const TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: AppColors.grey,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.close, size: 18, color: AppColors.error),
              tooltip: '断开请求',
              onPressed: () async {
                final confirmed = await _confirmDisconnect(context, info);
                if (confirmed && mounted) {
                  ref.read(activeRequestsProvider.notifier).disconnect(info.logId);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
