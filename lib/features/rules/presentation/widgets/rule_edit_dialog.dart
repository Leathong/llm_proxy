import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/core/widgets/scaled_switch.dart';
import 'package:llm_proxy/features/rules/domain/entities/rule.dart';
import 'package:llm_proxy/features/rules/presentation/providers/rules_providers.dart';
import 'package:llm_proxy/features/rules/presentation/widgets/system_prompt_manager_dialog.dart';

class RuleEditDialog extends ConsumerStatefulWidget {
  final Rule? rule;

  const RuleEditDialog({super.key, this.rule});

  @override
  ConsumerState<RuleEditDialog> createState() => _RuleEditDialogState();
}

class _RuleEditDialogState extends ConsumerState<RuleEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late String _groupName;
  late String _customModelId;
  late String _targetModelId;
  late bool _active;
  late String _thinkingMode;
  late String _reasoningEffort;
  late bool _convertThinkingToContent;
  int? _systemPromptId;
  int? _providerModelId;

  @override
  void initState() {
    super.initState();
    _name = widget.rule?.name ?? '';
    _groupName = widget.rule?.groupName ?? '';
    _customModelId = widget.rule?.customModelId ?? '';
    _targetModelId = widget.rule?.targetModelId ?? '';
    _active = widget.rule?.active ?? true;
    _thinkingMode = widget.rule?.thinkingMode ?? '';
    _reasoningEffort = widget.rule?.reasoningEffort ?? '';
    _convertThinkingToContent = widget.rule?.convertThinkingToContent ?? false;
    _systemPromptId = widget.rule?.systemPromptId;
    _providerModelId = widget.rule?.providerModelId;
  }

  Rule _buildRule({int? overrideId}) {
    return Rule(
      id: overrideId ?? widget.rule?.id ?? 0,
      name: _name,
      groupName: _groupName,
      customModelId: _customModelId,
      targetModelId: _targetModelId,
      providerModelId: _providerModelId,
      active: _active,
      thinkingMode: _thinkingMode,
      reasoningEffort: _reasoningEffort,
      convertThinkingToContent: _convertThinkingToContent,
      systemPromptId: _systemPromptId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.rule == null ? '添加规则' : '编辑规则'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  initialValue: _name,
                  decoration: const InputDecoration(labelText: '规则名称'),
                  validator: (val) =>
                      val == null || val.isEmpty ? '请输入规则名称' : null,
                  onSaved: (val) => _name = val!,
                ),
                TextFormField(
                  initialValue: _groupName,
                  decoration: const InputDecoration(
                    labelText: '分组名称',
                    hintText: '留空表示默认分组',
                  ),
                  onSaved: (val) => _groupName = val ?? '',
                ),
                TextFormField(
                  initialValue: _customModelId,
                  decoration: const InputDecoration(
                      labelText: '自定义模型 ID (客户端请求时使用)'),
                  validator: (val) =>
                      val == null || val.isEmpty ? '请输入自定义模型 ID' : null,
                  onSaved: (val) => _customModelId = val!,
                ),
                const SizedBox(height: 12),
                _buildProviderModelSelector(),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _thinkingMode,
                  decoration:
                      const InputDecoration(labelText: '思考模式 (thinking)'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('不注入')),
                    DropdownMenuItem(
                        value: 'enabled', child: Text('enabled (开启)')),
                    DropdownMenuItem(
                        value: 'disabled', child: Text('disabled (关闭)')),
                  ],
                  onChanged: (val) =>
                      setState(() => _thinkingMode = val ?? ''),
                  onSaved: (val) => _thinkingMode = val ?? '',
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _reasoningEffort,
                  decoration: const InputDecoration(
                      labelText: '思考强度 (reasoning_effort)'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('不注入')),
                    DropdownMenuItem(value: 'high', child: Text('high')),
                    DropdownMenuItem(value: 'max', child: Text('max')),
                  ],
                  onChanged: (val) =>
                      setState(() => _reasoningEffort = val ?? ''),
                  onSaved: (val) => _reasoningEffort = val ?? '',
                ),
                const SizedBox(height: 8),
                SwitchTile(
                  title: const Text('将模型思考转写为正常返回'),
                  subtitle: const Text('开启后 thinking/reasoning 将作为 content 返回'),
                  value: _convertThinkingToContent,
                  onChanged: (val) =>
                      setState(() => _convertThinkingToContent = val),
                ),
                const SizedBox(height: 8),
                _buildSystemPromptSelector(),
                SwitchTile(
                  title: const Text('启用规则'),
                  value: _active,
                  onChanged: (val) => setState(() => _active = val),
                )
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        if (widget.rule != null)
          TextButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                _formKey.currentState!.save();
                final rule = _buildRule(overrideId: 0);
                ref.read(rulesProvider.notifier).add(rule);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已另存为新规则')),
                );
              }
            },
            child: const Text('另存为'),
          ),
        TextButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              _formKey.currentState!.save();
              final rule = _buildRule();
              if (widget.rule == null) {
                ref.read(rulesProvider.notifier).add(rule);
              } else {
                ref.read(rulesProvider.notifier).updateRule(rule);
              }
              Navigator.pop(context);
            }
          },
          child: const Text('保存'),
        ),
      ],
    );
  }

  Widget _buildProviderModelSelector() {
    final providerModelsAsync = ref.watch(allProviderModelsProvider);
    final providersAsync = ref.watch(modelProvidersProvider);

    return providerModelsAsync.when(
      loading: () => const SizedBox(
        height: 48,
        child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (e, _) => Text('加载模型列表失败: $e',
          style: const TextStyle(color: Colors.red, fontSize: 12)),
      data: (providerModels) {
        final enabledModels =
            providerModels.where((m) => m.enabled).toList();

        final providers = providersAsync.asData?.value ?? [];
        final providerNameMap = <int, String>{};
        final providerFormatMap = <int, String>{};
        for (final p in providers) {
          providerNameMap[p.id] = p.name;
          providerFormatMap[p.id] = p.format;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<int?>(
              initialValue: _providerModelId,
              decoration: const InputDecoration(
                labelText: '关联模型',
                hintText: '请选择 Provider 模型',
              ),
              validator: (val) =>
                  val == null ? '请选择关联模型' : null,
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('请选择...'),
                ),
                ...enabledModels.map((m) {
                  final providerName =
                      providerNameMap[m.providerId] ?? 'Provider #${m.providerId}';
                  final format =
                      providerFormatMap[m.providerId] ?? '';
                  return DropdownMenuItem<int?>(
                    value: m.id,
                    child: Text('$providerName / ${m.modelId}  [$format]',
                        overflow: TextOverflow.ellipsis),
                  );
                }),
              ],
              onChanged: (val) => setState(() => _providerModelId = val),
              onSaved: (val) => _providerModelId = val,
            ),
            if (_providerModelId != null) ...[
              const SizedBox(height: 4),
              Text(
                '目标模型 ID 和转发地址由 Provider 配置决定',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildSystemPromptSelector() {
    final promptsAsync = ref.watch(systemPromptsProvider);
    final prompts = promptsAsync.asData?.value ?? [];

    // 防御性处理：如果 _systemPromptId 指向的 System Prompt 已被删除，重置为 null
    if (_systemPromptId != null &&
        !prompts.any((p) => p.id == _systemPromptId)) {
      _systemPromptId = null;
    }

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<int?>(
            initialValue: _systemPromptId,
            decoration: const InputDecoration(
              labelText: 'System Prompt',
              hintText: '不使用',
            ),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('不使用'),
              ),
              ...prompts.map((p) => DropdownMenuItem<int?>(
                    value: p.id,
                    child: Text(p.name, overflow: TextOverflow.ellipsis),
                  )),
            ],
            onChanged: (val) => setState(() => _systemPromptId = val),
            onSaved: (val) => _systemPromptId = val,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.settings, size: 20),
          tooltip: '管理 System Prompt',
          onPressed: () async {
            await showDialog(
              context: context,
              builder: (_) => const SystemPromptManagerDialog(),
            );
            if (!context.mounted) return;
            ref.invalidate(systemPromptsProvider);
          },
        ),
      ],
    );
  }
}
