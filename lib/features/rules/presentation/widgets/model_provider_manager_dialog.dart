import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/core/theme/app_colors.dart';
import 'package:llm_proxy/core/widgets/scaled_switch.dart';
import 'package:llm_proxy/features/rules/domain/entities/model_provider.dart';
import 'package:llm_proxy/features/rules/domain/entities/provider_model.dart';
import 'package:llm_proxy/features/rules/domain/services/model_list_service.dart';
import 'package:llm_proxy/features/rules/presentation/providers/rules_providers.dart';

/// Model Provider 管理页面（全屏，非弹窗）
class ModelProviderManagerPage extends ConsumerStatefulWidget {
  const ModelProviderManagerPage({super.key});

  @override
  ConsumerState<ModelProviderManagerPage> createState() =>
      _ModelProviderManagerPageState();
}

class _ModelProviderManagerPageState
    extends ConsumerState<ModelProviderManagerPage> {
  final ModelListService _modelListService = ModelListService();

  /// 当前展开的 provider id，null 表示全部折叠
  int? _expandedProviderId;

  /// 是否处于编辑模式（展开区域显示编辑表单而非模型列表）
  bool _isEditing = false;

  /// 编辑表单的 key，用于在切换编辑/查看模式时重建表单
  Key _editFormKey = UniqueKey();

  /// 正在获取模型列表的 provider id，null 表示空闲
  int? _fetchingProviderId;

  @override
  void dispose() {
    _modelListService.dispose();
    super.dispose();
  }

  void _toggleExpand(int providerId) {
    setState(() {
      if (_expandedProviderId == providerId) {
        _expandedProviderId = null;
        _isEditing = false;
      } else {
        _expandedProviderId = providerId;
        _isEditing = false;
      }
    });
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _editFormKey = UniqueKey();
    });
  }

  void _stopEditing() {
    setState(() {
      _isEditing = false;
    });
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
            child: const Text('删除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(modelProvidersProvider.notifier).delete(provider.id);
      setState(() {
        _expandedProviderId = null;
        _isEditing = false;
      });
    }
  }

  Future<void> _fetchModels(ModelProvider provider) async {
    setState(() => _fetchingProviderId = provider.id);
    try {
      final remoteModels = await _modelListService.fetchModels(provider);
      if (!mounted) return;

      final repo = ref.read(ruleRepositoryProvider);
      final existingModels = await repo.getProviderModels(provider.id);
      final existingIds = existingModels.map((m) => m.modelId).toSet();

      final newModels =
          remoteModels.where((m) => !existingIds.contains(m.id)).toList();

      // 接口请求完成，立即停止 loading（弹窗显示前）
      if (mounted) {
        setState(() => _fetchingProviderId = null);
      }

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
          ref.invalidate(providerModelsProvider(provider.id));
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
    } finally {
      if (mounted) {
        setState(() => _fetchingProviderId = null);
      }
    }
  }

  Future<void> _deleteModel(int modelId, int providerId) async {
    final repo = ref.read(ruleRepositoryProvider);
    await repo.deleteProviderModel(modelId);
    ref.invalidate(providerModelsProvider(providerId));
    ref.invalidate(allProviderModelsProvider);
  }

  Future<void> _toggleModel(int modelId, int providerId, bool enabled) async {
    final repo = ref.read(ruleRepositoryProvider);
    await repo.toggleProviderModel(modelId, enabled);
    ref.invalidate(providerModelsProvider(providerId));
    ref.invalidate(allProviderModelsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final providersAsync = ref.watch(modelProvidersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('管理 Model Provider'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加 Provider',
            onPressed: () {
              setState(() {
                _expandedProviderId = -1; // -1 表示新增模式
                _isEditing = true;
                _editFormKey = UniqueKey();
              });
            },
          ),
        ],
      ),
      body: providersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (providers) {
          if (providers.isEmpty && _expandedProviderId != -1) {
            return const Center(child: Text('暂无 Provider，请点击右上角 + 添加'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 新增 Provider 的展开区域
              if (_expandedProviderId == -1)
                _buildExpandedSection(
                  provider: null,
                  isExpanded: true,
                ),

              // 已有 Provider 列表
              for (final provider in providers)
                _buildExpandedSection(
                  provider: provider,
                  isExpanded: _expandedProviderId == provider.id,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildExpandedSection({
    required ModelProvider? provider,
    required bool isExpanded,
  }) {
    final isNew = provider == null;
    final providerId = provider?.id ?? -1;
    final formatLabel = provider?.format.toUpperCase() ?? '';
    final formatColor =
        provider?.format == 'anthropic' ? AppColors.formatAnthropic : AppColors.formatOpenAI;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // 头部：可点击展开/折叠
          InkWell(
            onTap: () => _toggleExpand(providerId),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.grey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isNew ? '新建 Provider' : provider.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        if (!isNew) ...[
                          const SizedBox(height: 2),
                          Text(
                            provider.baseUrl,
                            style: const TextStyle(fontSize: 12, color: AppColors.grey),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: formatColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              formatLabel,
                              style:
                                  TextStyle(fontSize: 10, color: formatColor),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!isNew) ...[
                    if (_fetchingProviderId == provider.id)
                      const SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.download, size: 20),
                        tooltip: '获取模型列表',
                        onPressed: () => _fetchModels(provider),
                      ),
                    IconButton(
                      icon: const Icon(Icons.delete, size: 20, color: AppColors.error),
                      tooltip: '删除 Provider',
                      onPressed: () => _deleteProvider(provider),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // 展开区域
          if (isExpanded) ...[
            const Divider(height: 1),

            // 编辑/查看模式切换按钮（仅已有 provider 显示）
            if (!isNew)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      _isEditing ? '编辑 Provider' : '模型列表',
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      icon: Icon(
                        _isEditing ? Icons.list : Icons.edit,
                        size: 16,
                      ),
                      label: Text(_isEditing ? '查看模型' : '编辑信息'),
                      onPressed: () {
                        if (_isEditing) {
                          _stopEditing();
                        } else {
                          _startEditing();
                        }
                      },
                    ),
                  ],
                ),
              ),

            // 编辑表单 或 模型列表
            if (isNew || _isEditing)
              _ProviderEditForm(
                key: _editFormKey,
                provider: provider,
                onSaved: (savedProvider) async {
                  if (isNew) {
                    final result = await ref
                        .read(modelProvidersProvider.notifier)
                        .add(savedProvider);
                    setState(() {
                      _expandedProviderId = result.id;
                      _isEditing = false;
                    });
                  } else {
                    await ref
                        .read(modelProvidersProvider.notifier)
                        .updateProvider(savedProvider);
                    _stopEditing();
                  }
                },
                onCancel: () {
                  if (isNew) {
                    setState(() => _expandedProviderId = null);
                  } else {
                    _stopEditing();
                  }
                },
              )
            else
              _ModelListSection(
                providerId: providerId,
                onDeleteModel: (modelId) => _deleteModel(modelId, providerId),
                onToggleModel: (modelId, enabled) =>
                    _toggleModel(modelId, providerId, enabled),
              ),
          ],
        ],
      ),
    );
  }
}

// ──────────────────────────── Provider 编辑表单 ────────────────────────────

class _ProviderEditForm extends StatefulWidget {
  final ModelProvider? provider;
  final void Function(ModelProvider) onSaved;
  final VoidCallback onCancel;

  const _ProviderEditForm({
    super.key,
    this.provider,
    required this.onSaved,
    required this.onCancel,
  });

  @override
  State<_ProviderEditForm> createState() => _ProviderEditFormState();
}

class _ProviderEditFormState extends State<_ProviderEditForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _apiKeyCtrl;
  late String _format;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.provider?.name ?? '');
    _baseUrlCtrl = TextEditingController(text: widget.provider?.baseUrl ?? '');
    _apiKeyCtrl = TextEditingController(text: widget.provider?.apiKey ?? '');
    _format = widget.provider?.format ?? 'openai';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '名称',
                border: OutlineInputBorder(),
              ),
              validator: (v) => v == null || v.isEmpty ? '请输入名称' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _baseUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'https://api.openai.com',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.isEmpty ? '请输入 Base URL' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _apiKeyCtrl,
              decoration: const InputDecoration(
                labelText: 'API Key',
                hintText: '可选',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _format,
              decoration: const InputDecoration(
                labelText: '兼容格式',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
                DropdownMenuItem(value: 'anthropic', child: Text('Anthropic')),
              ],
              onChanged: (v) => setState(() => _format = v ?? 'openai'),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: widget.onCancel,
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      widget.onSaved(ModelProvider(
                        id: widget.provider?.id ?? 0,
                        name: _nameCtrl.text,
                        baseUrl: _baseUrlCtrl.text,
                        apiKey: _apiKeyCtrl.text,
                        format: _format,
                      ));
                    }
                  },
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────── 模型列表区域 ────────────────────────────

class _ModelListSection extends ConsumerWidget {
  final int providerId;
  final void Function(int modelId) onDeleteModel;
  final void Function(int modelId, bool enabled) onToggleModel;

  const _ModelListSection({
    required this.providerId,
    required this.onDeleteModel,
    required this.onToggleModel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modelsAsync = ref.watch(providerModelsProvider(providerId));

    return Padding(
      padding: const EdgeInsets.all(16),
      child: modelsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (models) {
          if (models.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('暂无模型，请点击上方下载按钮获取模型列表',
                    style: TextStyle(color: AppColors.grey)),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('共 ${models.length} 个模型',
                  style: const TextStyle(fontSize: 12, color: AppColors.grey)),
              const SizedBox(height: 8),
              ...models.map((model) => Card(
                    margin: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      dense: true,
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
                            onChanged: (val) =>
                                onToggleModel(model.id, val),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete,
                                size: 18, color: AppColors.error),
                            onPressed: () => onDeleteModel(model.id),
                          ),
                        ],
                      ),
                    ),
                  )),
            ],
          );
        },
      ),
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
            Text(
                '已添加: ${widget.existingCount} 个模型，'
                '新发现: ${widget.remoteModels.length} 个模型',
                style: const TextStyle(fontSize: 12, color: AppColors.grey)),
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
