import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/core/widgets/scaled_switch.dart';
import 'package:llm_proxy/features/rules/domain/entities/provider_model.dart';
import 'package:llm_proxy/features/rules/domain/entities/rule.dart';
import 'package:llm_proxy/features/rules/presentation/providers/rules_providers.dart';
import 'package:llm_proxy/features/rules/presentation/widgets/provider_model_dropdown.dart';
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

  /// 根据规则列表和已保存的顺序构建分组并同步 TabController
  void _syncTabs(List<Rule> rules, List<String> savedOrder) {
    final groupSet = <String>{};
    for (final r in rules) {
      groupSet.add(r.groupName.isEmpty ? _kDefaultGroup : r.groupName);
    }

    // 按已保存的顺序排列分组，未在保存顺序中的新分组追加到末尾
    final ordered = <String>[];
    for (final g in savedOrder) {
      if (groupSet.contains(g)) {
        ordered.add(g);
        groupSet.remove(g);
      }
    }
    // 追加新分组（按字母排序）
    final newGroups = groupSet.toList()..sort();
    ordered.addAll(newGroups);

    // 如果分组有增减，持久化新的顺序
    final hasChanges = newGroups.isNotEmpty ||
        savedOrder.any((g) => !ordered.contains(g));
    if (hasChanges && ordered.isNotEmpty) {
      ref.read(groupOrderProvider.notifier).saveOrder(ordered);
    }

    // 仅在分组列表变化时重建 TabController
    if (_listEquals(ordered, _groups)) return;

    final oldIndex = _tabController?.index ?? 0;
    _tabController?.dispose();

    _groups = ordered;
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
    final savedOrder = ref.watch(groupOrderProvider);

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

        _syncTabs(rules, savedOrder);

        return Scaffold(
          appBar: AppBar(
            title: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: _groups.map((g) => Tab(text: g)).toList(),
            ),
            actions: [
              _buildReorderAction(),
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
                    child: InkWell(
                      onTap: () => _showRuleDialog(rule: rule),
                      onLongPress: () => _showDeleteDialog(rule),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 标题行：规则名称 + 操作按钮
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    rule.name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      // backgroundColor: Colors.red,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      size: 20, color: Colors.red),
                                  tooltip: '删除规则',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
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
                            // 模型切换下拉框（一级页面直接切换）
                            ProviderModelDropdown(
                              providerModelId: rule.providerModelId,
                              compact: true,
                              onChanged: (ProviderModel selected) {
                                // 构建 providerModelName
                                final providersAsync =
                                    ref.read(modelProvidersProvider);
                                final providers =
                                    providersAsync.asData?.value ?? [];
                                final pName = providers
                                    .where(
                                        (p) => p.id == selected.providerId)
                                    .firstOrNull
                                    ?.name ??
                                    'Provider #${selected.providerId}';
                                final providerModelName =
                                    '$pName / ${selected.modelId}';

                                ref.read(rulesProvider.notifier).updateRule(
                                      rule.copyWith(
                                        providerModelId: selected.id,
                                        providerModelName:
                                            providerModelName,
                                      ),
                                    );
                              },
                            ),
                          ],
                        ),
                      ),
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

  Widget _buildReorderAction() {
    return IconButton(
      icon: const Icon(Icons.reorder),
      tooltip: '编辑分组顺序',
      onPressed: _showReorderDialog,
    );
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

  void _showReorderDialog() {
    // 复制当前分组列表，避免直接修改
    final items = List<String>.from(_groups);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('编辑分组顺序'),
            content: SizedBox(
              width: 300,
              child: items.isEmpty
                  ? const Text('暂无分组')
                  : ReorderableListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        return ListTile(
                          key: ValueKey(items[index]),
                          title: Text(items[index]),
                          leading: const Icon(Icons.drag_handle),
                        );
                      },
                      onReorderItem: (oldIndex, newIndex) {
                        setDialogState(() {
                          final item = items.removeAt(oldIndex);
                          items.insert(newIndex, item);
                        });
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  ref.read(groupOrderProvider.notifier).saveOrder(items);
                  Navigator.pop(ctx);
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }
}
