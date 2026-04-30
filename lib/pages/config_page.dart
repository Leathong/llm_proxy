import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/config_provider.dart';
import '../models/proxy_rule.dart';

class ConfigPage extends StatelessWidget {
  const ConfigPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('规则配置'),
      ),
      body: Consumer<ConfigProvider>(
        builder: (context, provider, child) {
          if (!provider.isInitialized) {
            return const Center(child: CircularProgressIndicator());
          }
          final rules = provider.proxyRules;
          if (rules.isEmpty) {
            return const Center(
              child: Text('暂无代理规则，请点击右下角添加'),
            );
          }
          return ListView.builder(
            itemCount: rules.length,
            itemBuilder: (context, index) {
              final rule = rules[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text(rule.name),
                  subtitle: Text('${rule.customModelId} -> ${rule.targetModelId}\n${rule.endpoint}'),
                  isThreeLine: true,
                  trailing: Switch(
                    value: rule.active,
                    onChanged: (val) {
                      provider.toggleProxyRule(rule.id, val);
                    },
                  ),
                  onTap: () {
                    _showRuleDialog(context, rule: rule);
                  },
                  onLongPress: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('删除规则'),
                        content: const Text('确定要删除这条规则吗？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () {
                              provider.deleteProxyRule(rule.id);
                              Navigator.pop(ctx);
                            },
                            child: const Text('删除', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showRuleDialog(context);
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showRuleDialog(BuildContext context, {ProxyRule? rule}) {
    showDialog(
      context: context,
      builder: (context) => RuleEditDialog(rule: rule),
    );
  }
}

class RuleEditDialog extends StatefulWidget {
  final ProxyRule? rule;

  const RuleEditDialog({super.key, this.rule});

  @override
  State<RuleEditDialog> createState() => _RuleEditDialogState();
}

class _RuleEditDialogState extends State<RuleEditDialog> {
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
              // 思考模式下拉选择
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
              // 思考强度下拉选择
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
                onChanged: (val) {
                  setState(() {
                    _active = val;
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        // 编辑模式下提供"另存为"功能（添加模式下不显示）
        if (widget.rule != null)
          TextButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                _formKey.currentState!.save();
                final provider = Provider.of<ConfigProvider>(context, listen: false);
                // 基于当前表单创建一个新规则（新 ID），实现另存为
                final savedRule = ProxyRule(
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
                provider.addProxyRule(savedRule);
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
              final provider = Provider.of<ConfigProvider>(context, listen: false);
              
              if (widget.rule == null) {
                final newRule = ProxyRule(
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
                provider.addProxyRule(newRule);
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
                provider.updateProxyRule(updatedRule);
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
