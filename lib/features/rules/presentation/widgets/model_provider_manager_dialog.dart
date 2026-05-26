import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/core/widgets/scaled_switch.dart';
import 'package:llm_proxy/features/rules/domain/entities/model_provider.dart';
import 'package:llm_proxy/features/rules/domain/entities/provider_model.dart';
import 'package:llm_proxy/features/rules/domain/services/model_list_service.dart';
import 'package:llm_proxy/features/rules/presentation/providers/rules_providers.dart';

class ModelProviderManagerDialog extends ConsumerStatefulWidget {
  const ModelProviderManagerDialog({super.key});

  @override
  ConsumerState<ModelProviderManagerDialog> createState() =>
      _ModelProviderManagerDialogState();
}

class _ModelProviderManagerDialogState
    extends ConsumerState<ModelProviderManagerDialog> {
  final ModelListService _modelListService = ModelListService();

  @override
  void dispose() {
    _modelListService.dispose();
    super.dispose();
  }

  Future<void> _showEditDialog({ModelProvider? provider}) async {
    final result = await showDialog<ModelProvider>(
      context: context,
      builder: (ctx) => _ProviderEditDialog(provider: provider),
    );
    if (result != null) {
      if (provider == null) {
        await ref.read(modelProvidersProvider.notifier).add(result);
      } else {
        await ref.read(modelProvidersProvider.notifier).updateProvider(result);
      }
    }
  }

  Future<void> _deleteProvider(ModelProvider provider) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除 Provider'),
        content: Text('确定要删除 "${provider.name}" 吗？\n关联的模型也会被删除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(modelProvidersProvider.notifier).delete(provider.id);
    }
  }

  Future<void> _fetchModels(ModelProvider provider) async {
    try {
      final remoteModels = await _modelListService.fetchModels(provider);
      if (!mounted) return;

      final repo = ref.read(ruleRepositoryProvider);
      final existingModels = await repo.getProviderModels(provider.id);
      final existingIds = existingModels.map((m) => m.modelId).toSet();

      final newModels = remoteModels.where((m) => !existingIds.contains(m.id)).toList();

      if (!mounted) return;

      final selected = await showDialog<List<RemoteModel>>(
        context: context,
        builder: (ctx) => _ModelPickerDialog(
          providerName: provider.name,
          remoteModels: newModels,
          existingCount: existingModels.length,
        ),
      );

      if (selected != null && selected.isNotEmpty) {
        for (final model in selected) {
          await repo.addProviderModel(ProviderModel(
            id: 0,
            providerId: provider.id,
            modelId: model.id,
            displayName: model.displayName,
          ));
        }
        if (mounted) {
          ref.invalidate(allProviderModelsProvider);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已添加 ${selected.length} 个模型')),
          );
        }
      }
    } catch (e) {
      debugPrint('获取模型列表失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取模型列表失败: $e')),
        );
      }
    }
  }

  Future<void> _manageModels(ModelProvider provider) async {
    ref.invalidate(providerModelsProvider(provider.id));
    await showDialog(
      context: context,
      builder: (ctx) => _ModelManageDialog(provider: provider),
    );
    if (!mounted) return;
    ref.invalidate(allProviderModelsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final providersAsync = ref.watch(modelProvidersProvider);

    return AlertDialog(
      title: const Text('管理 Model Provider'),
      content: SizedBox(
        width: 550,
        height: 400,
        child: providersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('加载失败: $e')),
          data: (providers) {
            if (providers.isEmpty) {
              return const Center(child: Text('暂无 Provider，请点击下方按钮添加'));
            }
            return ListView.builder(
              itemCount: providers.length,
              itemBuilder: (context, index) {
                final provider = providers[index];
                final formatLabel = provider.format.toUpperCase();
                final formatColor = provider.format == 'anthropic'
                    ? Colors.orange
                    : Colors.green;

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    title: Text(provider.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(provider.baseUrl,
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: formatColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            formatLabel,
                            style: TextStyle(
                                fontSize: 10, color: formatColor),
                          ),
                        ),
                      ],
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.list_alt, size: 20),
                          tooltip: '管理模型',
                          onPressed: () => _manageModels(provider),
                        ),
                        IconButton(
                          icon: const Icon(Icons.download, size: 20),
                          tooltip: '获取模型列表',
                          onPressed: () => _fetchModels(provider),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          onPressed: () => _showEditDialog(provider: provider),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 20,
                              color: Colors.red),
                          onPressed: () => _deleteProvider(provider),
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
            child: const Text('关闭')),
        ElevatedButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text('添加 Provider'),
          onPressed: () => _showEditDialog(),
        ),
      ],
    );
  }
}

// ──────────────────────────── 模型管理对话框 ────────────────────────────

class _ModelManageDialog extends ConsumerStatefulWidget {
  final ModelProvider provider;

  const _ModelManageDialog({required this.provider});

  @override
  ConsumerState<_ModelManageDialog> createState() => _ModelManageDialogState();
}

class _ModelManageDialogState extends ConsumerState<_ModelManageDialog> {
  @override
  Widget build(BuildContext context) {
    final modelsAsync = ref.watch(providerModelsProvider(widget.provider.id));

    return AlertDialog(
      title: Text('${widget.provider.name} - 模型管理'),
      content: SizedBox(
        width: 500,
        height: 400,
        child: modelsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('加载失败: $e')),
          data: (models) {
            if (models.isEmpty) {
              return const Center(child: Text('暂无模型，请先获取模型列表'));
            }
            return ListView.builder(
              itemCount: models.length,
              itemBuilder: (context, index) {
                final model = models[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  child: ListTile(
                    title: Text(model.modelId,
                        style: const TextStyle(fontSize: 14)),
                    subtitle: model.displayName != null
                        ? Text(model.displayName!,
                            style: const TextStyle(fontSize: 12))
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ScaledSwitch(
                          value: model.enabled,
                          onChanged: (val) async {
                            final repo = ref.read(ruleRepositoryProvider);
                            await repo.toggleProviderModel(model.id, val);
                            ref.invalidate(providerModelsProvider(widget.provider.id));
                            ref.invalidate(allProviderModelsProvider);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18,
                              color: Colors.red),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('删除模型'),
                                content: Text('确定要删除 "${model.modelId}" 吗？'),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('取消')),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('删除',
                                        style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              final repo = ref.read(ruleRepositoryProvider);
                              await repo.deleteProviderModel(model.id);
                              ref.invalidate(providerModelsProvider(widget.provider.id));
                              ref.invalidate(allProviderModelsProvider);
                            }
                          },
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
            child: const Text('关闭')),
      ],
    );
  }
}

// ──────────────────────────── Provider 编辑对话框 ────────────────────────────

class _ProviderEditDialog extends StatefulWidget {
  final ModelProvider? provider;

  const _ProviderEditDialog({this.provider});

  @override
  State<_ProviderEditDialog> createState() => _ProviderEditDialogState();
}

class _ProviderEditDialogState extends State<_ProviderEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late String _baseUrl;
  late String _apiKey;
  late String _format;

  @override
  void initState() {
    super.initState();
    _name = widget.provider?.name ?? '';
    _baseUrl = widget.provider?.baseUrl ?? '';
    _apiKey = widget.provider?.apiKey ?? '';
    _format = widget.provider?.format ?? 'openai';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.provider == null ? '添加 Provider' : '编辑 Provider'),
      content: SizedBox(
        width: 450,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: _name,
                decoration: const InputDecoration(labelText: '名称'),
                validator: (v) =>
                    v == null || v.isEmpty ? '请输入名称' : null,
                onSaved: (v) => _name = v!,
              ),
              TextFormField(
                initialValue: _baseUrl,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  hintText: 'https://api.openai.com',
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? '请输入 Base URL' : null,
                onSaved: (v) => _baseUrl = v!,
              ),
              TextFormField(
                initialValue: _apiKey,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  hintText: '可选',
                ),
                onSaved: (v) => _apiKey = v ?? '',
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _format,
                decoration: const InputDecoration(labelText: '兼容格式'),
                items: const [
                  DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
                  DropdownMenuItem(
                      value: 'anthropic', child: Text('Anthropic')),
                ],
                onChanged: (v) => setState(() => _format = v ?? 'openai'),
                onSaved: (v) => _format = v ?? 'openai',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              _formKey.currentState!.save();
              Navigator.pop(
                context,
                ModelProvider(
                  id: widget.provider?.id ?? 0,
                  name: _name,
                  baseUrl: _baseUrl,
                  apiKey: _apiKey,
                  format: _format,
                ),
              );
            }
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

// ──────────────────────────── 模型选择对话框 ────────────────────────────

class _ModelPickerDialog extends StatefulWidget {
  final String providerName;
  final List<RemoteModel> remoteModels;
  final int existingCount;

  const _ModelPickerDialog({
    required this.providerName,
    required this.remoteModels,
    required this.existingCount,
  });

  @override
  State<_ModelPickerDialog> createState() => _ModelPickerDialogState();
}

class _ModelPickerDialogState extends State<_ModelPickerDialog> {
  final Set<String> _selectedIds = {};
  String _filterText = '';

  List<RemoteModel> get _filteredModels {
    if (_filterText.isEmpty) return widget.remoteModels;
    final lower = _filterText.toLowerCase();
    return widget.remoteModels
        .where((m) => m.id.toLowerCase().contains(lower))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredModels;

    return AlertDialog(
      title: Text('${widget.providerName} - 模型列表'),
      content: SizedBox(
        width: 450,
        height: 450,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('已添加: ${widget.existingCount} 个模型，'
                '新发现: ${widget.remoteModels.length} 个模型',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                hintText: '输入关键字过滤模型...',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (val) => setState(() => _filterText = val),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        _filterText.isEmpty ? '没有新模型' : '没有匹配的模型',
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final model = filtered[index];
                        final selected = _selectedIds.contains(model.id);
                        return CheckboxListTile(
                          value: selected,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selectedIds.add(model.id);
                              } else {
                                _selectedIds.remove(model.id);
                              }
                            });
                          },
                          title: Text(model.id,
                              style: const TextStyle(fontSize: 13)),
                          dense: true,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        ElevatedButton(
          onPressed: _selectedIds.isEmpty
              ? null
              : () {
                  final selected = widget.remoteModels
                      .where((m) => _selectedIds.contains(m.id))
                      .toList();
                  Navigator.pop(context, selected);
                },
          child: Text('添加 (${_selectedIds.length})'),
        ),
      ],
    );
  }
}
