import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/features/rules/domain/entities/endpoint_config.dart';
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
  late String _customModelId;
  late String _targetModelId;
  late bool _active;
  late String _thinkingMode;
  late String _reasoningEffort;

  // 多 endpoint 列表
  late List<_EndpointEntry> _endpoints;

  @override
  void initState() {
    super.initState();
    _name = widget.rule?.name ?? '';
    _customModelId = widget.rule?.customModelId ?? '';
    _targetModelId = widget.rule?.targetModelId ?? '';
    _active = widget.rule?.active ?? true;
    _thinkingMode = widget.rule?.thinkingMode ?? '';
    _reasoningEffort = widget.rule?.reasoningEffort ?? '';

    if (widget.rule != null && widget.rule!.endpoints.isNotEmpty) {
      _endpoints = widget.rule!.endpoints
          .map((e) => _EndpointEntry(
                id: e.id,
                urlController: TextEditingController(text: e.url),
                apiKeyController: TextEditingController(text: e.apiKey),
                active: e.active,
              ))
          .toList();
    } else {
      // 默认添加一个空 endpoint
      _endpoints = [
        _EndpointEntry(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          urlController: TextEditingController(),
          apiKeyController: TextEditingController(),
          active: true,
        ),
      ];
    }
  }

  @override
  void dispose() {
    for (final ep in _endpoints) {
      ep.urlController.dispose();
      ep.apiKeyController.dispose();
    }
    super.dispose();
  }

  void _addEndpoint() {
    setState(() {
      _endpoints.add(_EndpointEntry(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        urlController: TextEditingController(),
        apiKeyController: TextEditingController(),
        active: true,
      ));
    });
  }

  void _removeEndpoint(int index) {
    if (_endpoints.length <= 1) return;
    setState(() {
      _endpoints[index].urlController.dispose();
      _endpoints[index].apiKeyController.dispose();
      _endpoints.removeAt(index);
    });
  }

  List<EndpointConfig> _buildEndpoints() {
    return _endpoints
        .map((e) => EndpointConfig(
              id: e.id,
              url: e.urlController.text.trim(),
              apiKey: e.apiKeyController.text.trim(),
              active: e.active,
            ))
        .toList();
  }

  Rule _buildRule({String? overrideId}) {
    return Rule(
      id: overrideId ?? widget.rule?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _name,
      endpoints: _buildEndpoints(),
      customModelId: _customModelId,
      targetModelId: _targetModelId,
      active: _active,
      thinkingMode: _thinkingMode,
      reasoningEffort: _reasoningEffort,
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
                  validator: (val) => val == null || val.isEmpty ? '请输入规则名称' : null,
                  onSaved: (val) => _name = val!,
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
                const SizedBox(height: 16),
                // Endpoint 列表区域
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Endpoints (${_endpoints.length})',
                        style: Theme.of(context).textTheme.titleSmall),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                      tooltip: '添加 Endpoint',
                      onPressed: _addEndpoint,
                    ),
                  ],
                ),
                ..._buildEndpointWidgets(),
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
                Transform.scale(
                  scale: 0.75,
                  child: SwitchListTile(
                    title: const Text('启用规则'),
                    value: _active,
                    onChanged: (val) => setState(() => _active = val),
                  ),
                )
              ],
            ),
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
                final savedRule = _buildRule(
                  overrideId: DateTime.now().millisecondsSinceEpoch.toString(),
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
                ref.read(rulesProvider.notifier).add(_buildRule());
              } else {
                ref.read(rulesProvider.notifier).update(_buildRule());
              }
              Navigator.pop(context);
            }
          },
          child: const Text('保存'),
        ),
      ],
    );
  }

  List<Widget> _buildEndpointWidgets() {
    return List.generate(_endpoints.length, (index) {
      final ep = _endpoints[index];
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            children: [
              Row(
                children: [
                  Text('# ${index + 1}',
                      style: Theme.of(context).textTheme.bodySmall),
                  const Spacer(),
                  // 启用/禁用开关
                  Transform.scale(
                    scale: 0.7,
                    child: Switch(
                      value: ep.active,
                      onChanged: (val) => setState(() => ep.active = val),
                    ),
                  ),
                  // 删除按钮（至少保留一个）
                  if (_endpoints.length > 1)
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      tooltip: '删除此 Endpoint',
                      onPressed: () => _removeEndpoint(index),
                    ),
                ],
              ),
              TextFormField(
                controller: ep.urlController,
                decoration: const InputDecoration(
                  labelText: 'Endpoint URL',
                  hintText: 'https://api.openai.com/v1',
                  isDense: true,
                ),
                validator: (val) =>
                    val == null || val.trim().isEmpty ? '请输入 Endpoint URL' : null,
              ),
              TextFormField(
                controller: ep.apiKeyController,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// endpoint 编辑条目的临时状态
class _EndpointEntry {
  final String id;
  final TextEditingController urlController;
  final TextEditingController apiKeyController;
  bool active;

  _EndpointEntry({
    required this.id,
    required this.urlController,
    required this.apiKeyController,
    required this.active,
  });
}
