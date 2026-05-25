import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/features/rules/domain/entities/endpoint_config.dart';
import 'package:llm_proxy/features/rules/presentation/providers/rules_providers.dart';

class EndpointManagerDialog extends ConsumerStatefulWidget {
  const EndpointManagerDialog({super.key});

  @override
  ConsumerState<EndpointManagerDialog> createState() =>
      _EndpointManagerDialogState();
}

class _EndpointManagerDialogState
    extends ConsumerState<EndpointManagerDialog> {
  @override
  Widget build(BuildContext context) {
    final endpointsAsync = ref.watch(allEndpointsProvider);

    return AlertDialog(
      title: const Text('管理 Endpoint'),
      content: SizedBox(
        width: 500,
        height: 400,
        child: endpointsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('加载失败: $err')),
          data: (endpoints) {
            if (endpoints.isEmpty) {
              return const Center(child: Text('暂无 Endpoint'));
            }
            return ListView.builder(
              itemCount: endpoints.length,
              itemBuilder: (context, index) {
                final ep = endpoints[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.shade50,
                      child: Text('#${ep.id}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.blue.shade700)),
                    ),
                    title: Text(ep.url, style: const TextStyle(fontSize: 14)),
                    subtitle: Text(
                      ep.apiKey.isEmpty
                          ? '无 API Key'
                          : 'Key: ${ep.apiKey.substring(0, ep.apiKey.length > 8 ? 8 : ep.apiKey.length)}...',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          tooltip: '编辑',
                          onPressed: () =>
                              _showEditDialog(context, endpoint: ep),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18,
                              color: Colors.red),
                          tooltip: '删除',
                          onPressed: () => _deleteEndpoint(ep),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        TextButton(
          onPressed: () => _showEditDialog(context),
          child: const Text('新增'),
        ),
      ],
    );
  }

  void _showEditDialog(BuildContext context, {EndpointConfig? endpoint}) {
    final isEdit = endpoint != null;
    final urlController = TextEditingController(text: endpoint?.url ?? '');
    final apiKeyController =
        TextEditingController(text: endpoint?.apiKey ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? '编辑 Endpoint' : '新增 Endpoint'),
        content: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'Endpoint URL',
                  hintText: 'https://api.openai.com/v1',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: apiKeyController,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('保存')),
        ],
      ),
    ).then((saved) async {
      if (saved == true) {
        final url = urlController.text.trim();
        final apiKey = apiKeyController.text.trim();
        if (url.isEmpty) return;

        final repo = ref.read(ruleRepositoryProvider);
        if (isEdit) {
          await repo.updateEndpoint(EndpointConfig(
            id: endpoint.id,
            url: url,
            apiKey: apiKey,
          ));
        } else {
          await repo.addEndpoint(EndpointConfig(
            id: 0,
            url: url,
            apiKey: apiKey,
          ));
        }
        ref.invalidate(allEndpointsProvider);
      }
    });
  }

  Future<void> _deleteEndpoint(EndpointConfig endpoint) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除 Endpoint'),
        content: Text(
            '确定要删除 Endpoint "${endpoint.url}" 吗？\n\n注意：如果该 Endpoint 被规则引用，删除后相关规则的该 Endpoint 也会被移除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(ruleRepositoryProvider).deleteEndpoint(endpoint.id);
      ref.invalidate(allEndpointsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Endpoint 已删除')),
      );
    }
  }
}
