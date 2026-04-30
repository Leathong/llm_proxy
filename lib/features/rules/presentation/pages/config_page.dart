import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/features/rules/domain/entities/rule.dart';
import 'package:llm_proxy/features/rules/presentation/providers/rules_providers.dart';
import 'package:llm_proxy/features/rules/presentation/widgets/rule_edit_dialog.dart';

class ConfigPage extends ConsumerWidget {
  const ConfigPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(rulesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('规则配置')),
      body: rules.isEmpty
          ? const Center(
              child: Text('暂无代理规则，请点击右下角添加'),
            )
          : ListView.builder(
              itemCount: rules.length,
              itemBuilder: (context, index) {
                final rule = rules[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    title: Text(rule.name),
                    subtitle: Text('${rule.customModelId} -> ${rule.targetModelId}\n${rule.endpoint}'),
                    isThreeLine: true,
                    trailing: Transform.scale(
                      scale: 0.75,
                      child: Switch(
                        value: rule.active,
                        onChanged: (val) => ref.read(rulesProvider.notifier).toggle(rule.id, val),
                      ),
                    ),
                    onTap: () => _showRuleDialog(context, ref, rule: rule),
                    onLongPress: () => _showDeleteDialog(context, ref, rule),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showRuleDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showRuleDialog(BuildContext context, WidgetRef ref, {Rule? rule}) {
    showDialog(
      context: context,
      builder: (context) => RuleEditDialog(rule: rule),
    );
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref, Rule rule) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除规则'),
        content: const Text('确定要删除这条规则吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              ref.read(rulesProvider.notifier).delete(rule.id);
              Navigator.pop(ctx);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
