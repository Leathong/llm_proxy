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
                endpointId: e.id,
                urlController: TextEditingController(text: e.url),
                apiKeyController: TextEditingController(text: e.apiKey),
                active: e.active,
              ))
          .toList();
    } else {
      _endpoints = [
        _EndpointEntry(
          endpointId: 0,
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
        endpointId: 0,
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

  void _showHistoryEndpointPicker() async {
    final allEndpoints = await ref.read(allEndpointsProvider.future);
    if (!mounted) return;

    final currentIds = _endpoints.map((e) => e.endpointId).toSet();

    final available =
        allEndpoints.where((e) => !currentIds.contains(e.id)).toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可用的历史 Endpoint')),
      );
      return;
    }

    final selected = await showDialog<List<EndpointConfig>>(
      context: context,
      builder: (ctx) => _HistoryEndpointPickerDialog(endpoints: available),
    );

    if (selected != null && selected.isNotEmpty) {
      setState(() {
        for (final ep in selected) {
          _endpoints.add(_EndpointEntry(
            endpointId: ep.id,
            urlController: TextEditingController(text: ep.url),
            apiKeyController: TextEditingController(text: ep.apiKey),
            active: true,
          ));
        }
      });
    }
  }

  List<EndpointConfig> _buildEndpoints() {
    return _endpoints
        .map((e) => EndpointConfig(
              id: e.endpointId,
              url: e.urlController.text.trim(),
              apiKey: e.apiKeyController.text.trim(),
              active: e.active,
            ))
        .toList();
  }

  Rule _buildRule({int? overrideId}) {
    return Rule(
      id: overrideId ?? widget.rule?.id ?? 0,
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
                  validator: (val) =>
                      val == null || val.isEmpty ? '请输入规则名称' : null,
                  onSaved: (val) => _name = val!,
                ),
                TextFormField(
                  initialValue: _customModelId,
                  decoration: const InputDecoration(
                      labelText: '自定义模型 ID (客户端请求时使用)'),
                  validator: (val) =>
                      val == null || val.isEmpty ? '请输入自定义模型 ID' : null,
                  onSaved: (val) => _customModelId = val!,
                ),
                TextFormField(
                  initialValue: _targetModelId,
                  decoration: const InputDecoration(
                      labelText: '目标模型 ID (真实请求时使用)'),
                  validator: (val) =>
                      val == null || val.isEmpty ? '请输入目标模型 ID' : null,
                  onSaved: (val) => _targetModelId = val!,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Endpoints (${_endpoints.length})',
                        style: Theme.of(context).textTheme.titleSmall),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.history, size: 20),
                          tooltip: '从历史 Endpoint 选择',
                          onPressed: _showHistoryEndpointPicker,
                        ),
                        IconButton(
                          icon:
                              const Icon(Icons.add_circle_outline, size: 20),
                          tooltip: '新建 Endpoint',
                          onPressed: _addEndpoint,
                        ),
                      ],
                    ),
                  ],
                ),
                ..._buildEndpointWidgets(),
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
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        if (widget.rule != null)
          TextButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                _formKey.currentState!.save();
                final rule = _buildRule(overrideId: 0);
                final endpoints = _buildEndpoints();
                ref.read(rulesProvider.notifier).add(rule, endpoints);
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
              final endpoints = _buildEndpoints();
              if (widget.rule == null) {
                ref.read(rulesProvider.notifier).add(rule, endpoints);
              } else {
                ref.read(rulesProvider.notifier).updateRule(rule, endpoints);
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
                  if (ep.endpointId > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Chip(
                        label: Text('ID: ${ep.endpointId}',
                            style: const TextStyle(fontSize: 10)),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  const Spacer(),
                  Transform.scale(
                    scale: 0.7,
                    child: Switch(
                      value: ep.active,
                      onChanged: (val) => setState(() => ep.active = val),
                    ),
                  ),
                  if (_endpoints.length > 1)
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      tooltip: '移除此 Endpoint',
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
                validator: (val) => val == null || val.trim().isEmpty
                    ? '请输入 Endpoint URL'
                    : null,
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

class _EndpointEntry {
  final int endpointId;
  final TextEditingController urlController;
  final TextEditingController apiKeyController;
  bool active;

  _EndpointEntry({
    required this.endpointId,
    required this.urlController,
    required this.apiKeyController,
    required this.active,
  });
}

class _HistoryEndpointPickerDialog extends StatefulWidget {
  final List<EndpointConfig> endpoints;

  const _HistoryEndpointPickerDialog({required this.endpoints});

  @override
  State<_HistoryEndpointPickerDialog> createState() =>
      _HistoryEndpointPickerDialogState();
}

class _HistoryEndpointPickerDialogState
    extends State<_HistoryEndpointPickerDialog> {
  final Set<int> _selectedIds = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择历史 Endpoint'),
      content: SizedBox(
        width: 450,
        height: 400,
        child: widget.endpoints.isEmpty
            ? const Center(child: Text('没有可用的历史 Endpoint'))
            : ListView.builder(
                itemCount: widget.endpoints.length,
                itemBuilder: (context, index) {
                  final ep = widget.endpoints[index];
                  final selected = _selectedIds.contains(ep.id);
                  return CheckboxListTile(
                    value: selected,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedIds.add(ep.id);
                        } else {
                          _selectedIds.remove(ep.id);
                        }
                      });
                    },
                    title: Text(ep.url,
                        style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                      ep.apiKey.isEmpty
                          ? '无 API Key'
                          : 'Key: ${ep.apiKey.substring(0, (ep.apiKey.length > 8 ? 8 : ep.apiKey.length))}...',
                      style: const TextStyle(fontSize: 11),
                    ),
                    dense: true,
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _selectedIds.isEmpty
              ? null
              : () {
                  final selected = widget.endpoints
                      .where((e) => _selectedIds.contains(e.id))
                      .toList();
                  Navigator.pop(context, selected);
                },
          child: Text('添加 (${_selectedIds.length})'),
        ),
      ],
    );
  }
}
