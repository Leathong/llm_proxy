import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/features/logs/presentation/providers/file_log_providers.dart';
import 'package:llm_proxy/features/logs/presentation/widgets/file_log_item.dart';
import 'package:llm_proxy/features/logs/presentation/widgets/log_summary_bar.dart';

class FileLogPage extends ConsumerStatefulWidget {
  const FileLogPage({super.key});

  @override
  ConsumerState<FileLogPage> createState() => _FileLogPageState();
}

class _FileLogPageState extends ConsumerState<FileLogPage> {
  bool _reversed = false;

  @override
  Widget build(BuildContext context) {
    final logState = ref.watch(logOutputProvider);
    final hasFilter = !logState.filter.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('日志分析'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: '选择日志文件',
            onPressed: () => _pickAndLoadFile(ref),
          ),
          if (logState.filePath != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重新加载',
              onPressed: () =>
                  ref.read(logOutputProvider.notifier).loadFile(logState.filePath!),
            ),
          // Filter 按钮 — 有过滤时高亮
          if (logState.entries.isNotEmpty)
            IconButton(
              icon: Icon(
                Icons.filter_list,
                color: hasFilter ? Colors.blue : null,
              ),
              tooltip: hasFilter ? '过滤中 (点击修改)' : '过滤',
              onPressed: () => _showFilterDialog(logState),
            ),
          if (logState.entries.isNotEmpty)
            IconButton(
              icon: Icon(
                _reversed ? Icons.arrow_upward : Icons.arrow_downward,
              ),
              tooltip: _reversed ? '切换为正序' : '切换为倒序',
              onPressed: () => setState(() => _reversed = !_reversed),
            ),
          if (logState.entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '关闭文件',
              onPressed: () => ref.read(logOutputProvider.notifier).clear(),
            ),
        ],
      ),
      body: _buildBody(context, logState),
    );
  }

  Future<void> _pickAndLoadFile(WidgetRef ref) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['log', 'json'],
      dialogTitle: '选择日志文件（.log 或 .json）',
    );
    if (result != null && result.files.single.path != null) {
      ref.read(logOutputProvider.notifier).loadFile(result.files.single.path!);
    }
  }

  /// 弹出过滤对话框
  Future<void> _showFilterDialog(FileLogState state) async {
    final filter = state.filter;
    final models = FileLogFilter.availableModels(state.entries);
    final forwards = FileLogFilter.availableForwardTos(state.entries);
    // 临时状态，只在弹窗内有效
    final keywordCtrl = TextEditingController(text: filter.keyword);
    var tempModelFilter = filter.modelFilter;
    var tempForwardToFilter = filter.forwardToFilter;
    var tempKeyword = filter.keyword;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.filter_list, size: 20, color: Colors.blue),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('过滤日志',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(ctx).pop(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: keywordCtrl,
                  decoration: InputDecoration(
                    hintText: '搜索模型、转发目标、路径...',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: keywordCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              keywordCtrl.clear();
                              setDialogState(() => tempKeyword = '');
                            },
                          )
                        : null,
                  ),
                  style: const TextStyle(fontSize: 14),
                  onChanged: (v) => setDialogState(() => tempKeyword = v),
                ),
                if (models.isNotEmpty || forwards.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (models.isNotEmpty)
                        Expanded(
                          child: _FilterDropdown(
                            label: '模型',
                            value: tempModelFilter,
                            items: models,
                            onChanged: (v) =>
                                setDialogState(() => tempModelFilter = v),
                            onClear: tempModelFilter != null
                                ? () => setDialogState(() => tempModelFilter = null)
                                : null,
                          ),
                        ),
                      if (models.isNotEmpty && forwards.isNotEmpty)
                        const SizedBox(width: 8),
                      if (forwards.isNotEmpty)
                        Expanded(
                          child: _FilterDropdown(
                            label: '转发目标',
                            value: tempForwardToFilter,
                            items: forwards,
                            onChanged: (v) =>
                                setDialogState(() => tempForwardToFilter = v),
                            onClear: tempForwardToFilter != null
                                ? () => setDialogState(() => tempForwardToFilter = null)
                                : null,
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        ref.read(logOutputProvider.notifier).setFilter(const FileLogFilter());
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('清除'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        ref.read(logOutputProvider.notifier).setFilter(FileLogFilter(
                          keyword: tempKeyword,
                          modelFilter: tempModelFilter,
                          forwardToFilter: tempForwardToFilter,
                        ));
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('应用'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // 延迟 dispose，确保 dialog 动画和 widget 树已完全销毁
    WidgetsBinding.instance.addPostFrameCallback((_) {
      keywordCtrl.dispose();
    });
  }

  Widget _buildBody(BuildContext context, FileLogState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(state.error!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      );
    }

    if (state.entries.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.analytics_outlined, size: 80, color: Colors.grey),
            SizedBox(height: 20),
            Text('点击右上角 📂 按钮加载日志文件（.log 或 .json）',
                style: TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      );
    }

    final filtered = state.filteredEntries;
    final displayEntries =
        _reversed ? filtered.reversed.toList() : filtered;

    return Column(
      children: [
        LogSummaryBar(
          entries: state.entries,
          filePath: state.filePath,
          filteredEntries: state.filter.isEmpty ? null : filtered,
        ),
        const Divider(height: 1),
        if (displayEntries.isEmpty)
          const Expanded(
            child: Center(
              child: Text('没有匹配的日志记录',
                  style: TextStyle(color: Colors.grey, fontSize: 14)),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: displayEntries.length,
              itemBuilder: (context, index) =>
                  FileLogItem(entry: displayEntries[index]),
            ),
          ),
      ],
    );
  }
}

/// 过滤条件下拉选择器
class _FilterDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final VoidCallback? onClear;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text('$label: ',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: value,
                isExpanded: true,
                isDense: true,
                hint: const Text('全部', style: TextStyle(fontSize: 12)),
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('全部', style: TextStyle(fontSize: 12)),
                  ),
                  ...items.map((item) => DropdownMenuItem<String?>(
                        value: item,
                        child: Text(item,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
          if (value != null)
            GestureDetector(
              onTap: onClear,
              child:
                  const Icon(Icons.clear, size: 16, color: Colors.grey),
            ),
        ],
      ),
    );
  }
}
