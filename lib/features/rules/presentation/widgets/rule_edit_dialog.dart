import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/features/rules/domain/entities/rule.dart';
import 'package:llm_proxy/features/rules/presentation/providers/rules_providers.dart';

class RuleEditDialog extends ConsumerStatefulWidget {
  final Rule? rule;

  const RuleEditDialog({super.key, this.rule});

  @override
  ConsumerState<RuleEditDialog> createState() => _RuleEditDialogState();
}

class _RuleEditDialogState extends ConsumerState<RuleEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late String _endpoint;
  late String _apiKey;
  late String _customModelId;
  late String _targetModelId;
  late bool _active;
  late String _thinkingMode;
  late String _reasoningEffort;

  @override
  void initState() {
    super.initState();
    _name = widget.rule?.name ?? '';
    _endpoint = widget.rule?.endpoint ?? '';
    _apiKey = widget.rule?.apiKey ?? '';
    _customModelId = widget.rule?.customModelId ?? '';
    _targetModelId = widget.rule?.targetModelId ?? '';
    _active = widget.rule?.active ?? true;
    _thinkingMode = widget.rule?.thinkingMode ?? '';
    _reasoningEffort = widget.rule?.reasoningEffort ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.rule == null ? '添加规则' : '编辑规则'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: _name,
                decoration: const InputDecoration(labelText: '规则名称'),
                validator: (val) => val == null || val.isEmpty ? '请输入规则名称' : null,
                onSaved: (val) => _name = val!,
              ),
              TextFormField(
                initialValue: _endpoint,
                decoration: const InputDecoration(labelText: '目标 Endpoint (如 https://api.openai.com/v1)'),
                validator: (val) => val == null || val.isEmpty ? '请输入目标 Endpoint' : null,
                onSaved: (val) => _endpoint = val!,
              ),
              TextFormField(
                initialValue: _apiKey,
                decoration: const InputDecoration(labelText: 'API Key'),
                onSaved: (val) => _apiKey = val ?? '',
              ),
              TextFormField(
                initialValue: _customModelId,
                decoration: const InputDecoration(labelText: '自定义模型 ID (客户端请求时使用)'),
                validator: (val) => val == null || val.isEmpty ? '请输入自定义模型 ID' : null,
                onSaved: (val) => _customModelId = val!,
              ),
              TextFormField(
                initialValue: _targetModelId,
                decoration: const InputDecoration(labelText: '目标模型 ID (真实请求时使用)'),
                validator: (val) => val == null || val.isEmpty ? '请输入目标模型 ID' : null,
                onSaved: (val) => _targetModelId = val!,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _thinkingMode,
                decoration: const InputDecoration(labelText: '思考模式 (thinking)'),
                items: const [
                  DropdownMenuItem(value: '', child: Text('不注入')),
                  DropdownMenuItem(value: 'enabled', child: Text('enabled (开启)')),
                  DropdownMenuItem(value: 'disabled', child: Text('disabled (关闭)')),
                ],
                onChanged: (val) => setState(() => _thinkingMode = val ?? ''),
                onSaved: (val) => _thinkingMode = val ?? '',
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _reasoningEffort,
                decoration: const InputDecoration(labelText: '思考强度 (reasoning_effort)'),
                items: const [
                  DropdownMenuItem(value: '', child: Text('不注入')),
                  DropdownMenuItem(value: 'high', child: Text('high')),
                  DropdownMenuItem(value: 'max', child: Text('max')),
                ],
                onChanged: (val) => setState(() => _reasoningEffort = val ?? ''),
                onSaved: (val) => _reasoningEffort = val ?? '',
              ),
              SwitchListTile(
                title: const Text('启用规则'),
                value: _active,
                onChanged: (val) => setState(() => _active = val),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        if (widget.rule != null)
          TextButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                _formKey.currentState!.save();
                final savedRule = Rule(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: _name,
                  endpoint: _endpoint,
                  apiKey: _apiKey,
                  customModelId: _customModelId,
                  targetModelId: _targetModelId,
                  active: _active,
                  thinkingMode: _thinkingMode,
                  reasoningEffort: _reasoningEffort,
                );
                ref.read(rulesProvider.notifier).add(savedRule);
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
              if (widget.rule == null) {
                final newRule = Rule(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: _name,
                  endpoint: _endpoint,
                  apiKey: _apiKey,
                  customModelId: _customModelId,
                  targetModelId: _targetModelId,
                  active: _active,
                  thinkingMode: _thinkingMode,
                  reasoningEffort: _reasoningEffort,
                );
                ref.read(rulesProvider.notifier).add(newRule);
              } else {
                final updatedRule = widget.rule!.copyWith(
                  name: _name,
                  endpoint: _endpoint,
                  apiKey: _apiKey,
                  customModelId: _customModelId,
                  targetModelId: _targetModelId,
                  active: _active,
                  thinkingMode: _thinkingMode,
                  reasoningEffort: _reasoningEffort,
                );
                ref.read(rulesProvider.notifier).update(updatedRule);
              }
              Navigator.pop(context);
            }
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
