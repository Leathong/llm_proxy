import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/features/logs/presentation/providers/file_log_providers.dart';
import 'package:llm_proxy/features/logs/presentation/widgets/file_log_item.dart';
import 'package:llm_proxy/features/logs/presentation/widgets/log_summary_bar.dart';
import 'package:llm_proxy/features/settings/presentation/providers/settings_providers.dart';

class FileLogPage extends ConsumerStatefulWidget {
  const FileLogPage({super.key});

  @override
  ConsumerState<FileLogPage> createState() => _FileLogPageState();
}

class _FileLogPageState extends ConsumerState<FileLogPage> {
  bool _reversed = false;
  bool _subtractFirstByte = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreSelection());
  }

  Future<void> _restoreSelection() async {
    if (!mounted) return;
    final prefs = ref.read(sharedPreferencesProvider);
    final savedFiles = prefs.getStringList('fileLogLoadedFiles');
    if (savedFiles != null && savedFiles.isNotEmpty) {
      final existingFiles =
          savedFiles.where((f) => File(f).existsSync()).toList();
      if (existingFiles.isNotEmpty) {
        ref.read(logOutputProvider.notifier).loadFiles(existingFiles);
      }
    }
  }

  Future<void> _saveSelection(List<String> filePaths) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setStringList('fileLogLoadedFiles', filePaths);
  }

  Future<void> _clearSavedSelection() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove('fileLogLoadedFiles');
  }

  Future<void> _confirmClearLog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空日志'),
        content: const Text('确定要清空当前选中的日志文件吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(logOutputProvider.notifier).clearLoadedFiles();
      _clearSavedSelection();
    }
  }

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
            tooltip: '选择日志目录',
            onPressed: () => _pickDirAndShowFileSelector(ref),
          ),
          if (logState.loadedFiles.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.playlist_add_check),
              tooltip: '选择文件 (已加载 ${logState.loadedFiles.length} 个)',
              onPressed: () => _showFileSelector(ref, logState.filePath!, logState.loadedFiles),
            ),
          if (logState.loadedFiles.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重新加载',
              onPressed: () =>
                  ref.read(logOutputProvider.notifier).loadFiles(logState.loadedFiles),
            ),
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
              icon: Icon(
                _subtractFirstByte ? Icons.flash_on : Icons.schedule,
              ),
              tooltip: _subtractFirstByte ? '速度已减去首字节时间' : '速度包含首字节时间',
              onPressed: () => setState(() => _subtractFirstByte = !_subtractFirstByte),
            ),
          if (logState.entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '关闭文件',
              onPressed: () {
                ref.read(logOutputProvider.notifier).clear();
                _clearSavedSelection();
              },
            ),
          if (logState.loadedFiles.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.cleaning_services),
              tooltip: '清空当前文件',
              onPressed: () => _confirmClearLog(),
            ),
        ],
      ),
      body: _buildBody(context, logState),
    );
  }

  /// 选择目录后弹出文件勾选对话框
  Future<void> _pickDirAndShowFileSelector(WidgetRef ref) async {
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: '选择日志目录',
    );
    if (dir != null) {
      _showFileSelector(ref, dir, const []);
    }
  }

  /// 弹出文件勾选对话框，让用户选择要加载的 .log 文件
  Future<void> _showFileSelector(
    WidgetRef ref,
    String dirPath,
    List<String> preSelected,
  ) async {
    // 扫描目录下的 .log 文件
    final directory = Directory(dirPath);
    final allLogFiles = <String>[];
    try {
      await for (final entity in directory.list()) {
        if (entity is File && entity.path.endsWith('.log')) {
          allLogFiles.add(entity.path);
        }
      }
      allLogFiles.sort();
    } catch (_) {
      return;
    }

    if (allLogFiles.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该目录下没有 .log 文件')),
        );
      }
      return;
    }

    // 临时勾选状态
    final selected = <String>{...preSelected};

    final result = await showDialog<List<String>>(
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
                    const Icon(Icons.playlist_add_check, size: 20, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '选择日志文件 (${allLogFiles.length} 个)',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(ctx).pop(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 全选/取消全选
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setDialogState(() {
                        selected.addAll(allLogFiles);
                      }),
                      child: const Text('全选'),
                    ),
                    TextButton(
                      onPressed: () => setDialogState(() {
                        selected.clear();
                      }),
                      child: const Text('取消全选'),
                    ),
                    const Spacer(),
                    Text(
                      '已选 ${selected.length}/${allLogFiles.length}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                const Divider(),
                // 文件列表
                Flexible(
                  child: SizedBox(
                    width: double.maxFinite,
                    height: 300,
                    child: ListView.builder(
                      itemCount: allLogFiles.length,
                      itemBuilder: (ctx, i) {
                        final path = allLogFiles[i];
                        final fileName = path.split(Platform.pathSeparator).last;
                        final isChecked = selected.contains(path);
                        return CheckboxListTile(
                          value: isChecked,
                          dense: true,
                          title: Text(
                            fileName,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (v) => setDialogState(() {
                            if (v == true) {
                              selected.add(path);
                            } else {
                              selected.remove(path);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () => Navigator.of(ctx).pop(selected.toList()..sort()),
                      child: const Text('加载'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result != null && result.isNotEmpty) {
      _saveSelection(result);
      ref.read(logOutputProvider.notifier).loadFiles(result);
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
            Text('点击右上角 📂 按钮选择日志目录，再勾选要加载的 .log 文件',
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
          subtractFirstByte: _subtractFirstByte,
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
                  FileLogItem(
                entry: displayEntries[index],
                subtractFirstByte: _subtractFirstByte,
              ),
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
