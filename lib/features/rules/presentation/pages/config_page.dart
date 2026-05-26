import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/core/widgets/scaled_switch.dart';
import 'package:llm_proxy/features/rules/domain/entities/rule.dart';
import 'package:llm_proxy/features/rules/presentation/providers/rules_providers.dart';
import 'package:llm_proxy/features/rules/presentation/widgets/rule_edit_dialog.dart';
import 'package:llm_proxy/features/rules/presentation/widgets/model_provider_manager_dialog.dart';
import 'package:llm_proxy/features/rules/presentation/widgets/system_prompt_manager_dialog.dart';

/// 默认分组名（groupName 为空时归入此组）
const _kDefaultGroup = '默认';

class ConfigPage extends ConsumerStatefulWidget {
  const ConfigPage({super.key});

  @override
  ConsumerState<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends ConsumerState<ConfigPage>
    with TickerProviderStateMixin {
  TabController? _tabController;

  /// 当前各分组名列表（有序，默认组在最前）
  List<String> _groups = [];

  /// 根据规则列表构建分组并同步 TabController
  void _syncTabs(List<Rule> rules) {
    final groupSet = <String>{};
    for (final r in rules) {
      groupSet.add(r.groupName.isEmpty ? _kDefaultGroup : r.groupName);
    }

    // 保证"默认"在最前，其余按字母排序
    final sorted = groupSet.toList()
      ..sort((a, b) {
        if (a == _kDefaultGroup) return -1;
        if (b == _kDefaultGroup) return 1;
        return a.compareTo(b);
      });

    // 仅在分组列表变化时重建 TabController
    if (_listEquals(sorted, _groups)) return;

    final oldIndex = _tabController?.index ?? 0;
    _tabController?.dispose();

    _groups = sorted;
    _tabController = TabController(
      length: _groups.length,
      vsync: this,
      initialIndex: oldIndex.clamp(0, _groups.length - 1),
    );
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rulesAsync = ref.watch(rulesProvider);

    return rulesAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(child: Text('加载失败: $e')),
      ),
      data: (rules) {
        if (rules.isEmpty) {
          return Scaffold(
            appBar: AppBar(
              actions: [
                _buildProviderAction(),
                _buildSystemPromptAction(),
              ],
            ),
            body: const Center(child: Text('暂无代理规则，请点击右下角添加')),
            floatingActionButton: _buildFab(),
          );
        }

        _syncTabs(rules);

        return Scaffold(
          appBar: AppBar(
            // 用 TabBar 替换原来的 title
            title: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: _groups.map((g) => Tab(text: g)).toList(),
            ),
            actions: [
              _buildProviderAction(),
              _buildSystemPromptAction(),
            ],
          ),
          body: TabBarView(
            controller: _tabController,
            children: _groups.map((group) {
              // 筛选当前分组的规则
              final groupRules = rules.where((r) {
                final g = r.groupName.isEmpty ? _kDefaultGroup : r.groupName;
                return g == group;
              }).toList();

              return ListView.builder(
                itemCount: groupRules.length,
                itemBuilder: (context, index) {
                  final rule = groupRules[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: ListTile(
                      title: Text(rule.name),
                      subtitle: Text(_buildRuleSubtitle(rule)),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                size: 20, color: Colors.red),
                            tooltip: '删除规则',
                            onPressed: () => _showDeleteDialog(rule),
                          ),
                          ScaledSwitch(
                            value: rule.active,
                            onChanged: (val) => ref
                                .read(rulesProvider.notifier)
                                .toggle(rule.id, val),
                          ),
                        ],
                      ),
                      onTap: () => _showRuleDialog(rule: rule),
                      onLongPress: () => _showDeleteDialog(rule),
                    ),
                  );
                },
              );
            }).toList(),
          ),
          floatingActionButton: _buildFab(),
        );
      },
    );
  }

  String _buildRuleSubtitle(Rule rule) {
    if (rule.providerModelName.isNotEmpty) {
      return '${rule.customModelId} -> ${rule.providerModelName}';
    }
    if (rule.providerModelId != null) {
      return '${rule.customModelId} -> ProviderModel #${rule.providerModelId}';
    }
    return '${rule.customModelId} -> ${rule.targetModelId} (未关联 Provider)';
  }

  Widget _buildProviderAction() {
    return IconButton(
      icon: const Icon(Icons.cloud_outlined),
      tooltip: '管理 Model Provider',
      onPressed: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ModelProviderManagerPage(),
          ),
        );
        if (!context.mounted) return;
        ref.invalidate(modelProvidersProvider);
        ref.invalidate(allProviderModelsProvider);
      },
    );
  }

  Widget _buildSystemPromptAction() {
    return IconButton(
      icon: const Icon(Icons.article_outlined),
      tooltip: '管理 System Prompt',
      onPressed: () async {
        await showDialog(
          context: context,
          builder: (_) => const SystemPromptManagerDialog(),
        );
        if (!context.mounted) return;
        ref.invalidate(systemPromptsProvider);
      },
    );
  }

  Widget _buildFab() {
    return FloatingActionButton(
      onPressed: () => _showRuleDialog(),
      child: const Icon(Icons.add),
    );
  }

  void _showRuleDialog({Rule? rule}) {
    showDialog(
      context: context,
      builder: (context) => RuleEditDialog(rule: rule),
    );
  }

  void _showDeleteDialog(Rule rule) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除规则'),
        content: const Text('确定要删除这条规则吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
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
