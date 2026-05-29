import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/features/rules/domain/entities/system_prompt.dart';
import 'package:llm_proxy/features/rules/presentation/providers/rules_providers.dart';

class SystemPromptManagerDialog extends ConsumerStatefulWidget {
  const SystemPromptManagerDialog({super.key});

  @override
  ConsumerState<SystemPromptManagerDialog> createState() =>
      _SystemPromptManagerDialogState();
}

class _SystemPromptManagerDialogState
    extends ConsumerState<SystemPromptManagerDialog> {
  @override
  Widget build(BuildContext context) {
    final promptsAsync = ref.watch(systemPromptsProvider);

    return AlertDialog(
      title: const Text('管理 System Prompt'),
      content: SizedBox(
        width: 500,
        height: 400,
        child: promptsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('加载失败: $err')),
          data: (prompts) {
            if (prompts.isEmpty) {
              return const Center(child: Text('暂无 System Prompt'));
            }
            return ListView.builder(
              itemCount: prompts.length,
              itemBuilder: (context, index) {
                final prompt = prompts[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    title: Text(prompt.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      prompt.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          onPressed: () =>
                              _showEditDialog(context, prompt: prompt),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18,
                              color: Colors.red),
                          onPressed: () => _deletePrompt(prompt.id),
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
          child: const Text('关闭'),
        ),
        TextButton(
          onPressed: () => _showEditDialog(context),
          child: const Text('新增'),
        ),
      ],
    );
  }

  void _showEditDialog(BuildContext context, {SystemPrompt? prompt}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => _SystemPromptEditPage(
          prompt: prompt,
          onSave: (name, content) async {
            if (prompt == null) {
              await ref.read(systemPromptsProvider.notifier).add(
                    SystemPrompt(id: 0, name: name, content: content),
                  );
            } else {
              await ref.read(systemPromptsProvider.notifier).updatePrompt(
                    SystemPrompt(
                        id: prompt.id, name: name, content: content),
                  );
            }
          },
        ),
      ),
    );
  }

  Future<void> _deletePrompt(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('删除后，引用此 System Prompt 的规则将不再替换 prompt。'),
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
    if (confirmed == true) {
      await ref.read(systemPromptsProvider.notifier).delete(id);
    }
  }
}

class _SystemPromptEditPage extends StatefulWidget {
  final SystemPrompt? prompt;
  final Future<void> Function(String name, String content) onSave;

  const _SystemPromptEditPage({
    required this.onSave,
    this.prompt,
  });

  @override
  State<_SystemPromptEditPage> createState() =>
      _SystemPromptEditPageState();
}

class _SystemPromptEditPageState extends State<_SystemPromptEditPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _contentController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.prompt?.name ?? '');
    _contentController =
        TextEditingController(text: widget.prompt?.content ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isSaving = true);
      try {
        await widget.onSave(
          _nameController.text,
          _contentController.text,
        );
        if (!mounted) return;
        Navigator.pop(context);
      } finally {
        if (mounted) {
          setState(() => _isSaving = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.prompt == null ? '新增 System Prompt' : '编辑 System Prompt'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _handleSave,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '名称',
                  border: OutlineInputBorder(),
                ),
                validator: (val) =>
                    val == null || val.isEmpty ? '请输入名称' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contentController,
                decoration: const InputDecoration(
                  labelText: '内容',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                maxLines: null,
                minLines: 15,
                expands: false,
                validator: (val) =>
                    val == null || val.isEmpty ? '请输入内容' : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
