import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_entry.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_stats.dart';
import 'package:llm_proxy/features/logs/presentation/providers/unified_log_providers.dart';
import 'package:llm_proxy/features/logs/presentation/widgets/log_detail.dart';
import 'package:llm_proxy/features/logs/presentation/widgets/log_summary_bar.dart';

class LogPage extends ConsumerStatefulWidget {
  const LogPage({super.key});

  @override
  ConsumerState<LogPage> createState() => _UnifiedLogPageState();
}

class _UnifiedLogPageState extends ConsumerState<LogPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(unifiedLogProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(unifiedLogProvider);
    final notifier = ref.read(unifiedLogProvider.notifier);
    final hasFilter = !state.filter.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('日志'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: '导入日志',
            onPressed: () => _importLogs(),
          ),
          if (state.allEntries.isNotEmpty) ...[
            IconButton(
              icon: Icon(
                Icons.filter_list,
                color: hasFilter ? Colors.blue : null,
              ),
              tooltip: hasFilter ? '过滤中 (点击修改)' : '过滤',
              onPressed: () => _showFilterDialog(state),
            ),
            IconButton(
              icon: Icon(
                state.reversed ? Icons.arrow_upward : Icons.arrow_downward,
              ),
              tooltip: state.reversed ? '切换为正序' : '切换为倒序',
              onPressed: () {
                notifier.setReversed(!state.reversed);
              },
            ),
            IconButton(
              icon: Icon(
                state.subtractFirstByte ? Icons.flash_on : Icons.schedule,
              ),
              tooltip: state.subtractFirstByte
                  ? '速度已减去首字节时间'
                  : '速度包含首字节时间',
              onPressed: () {
                notifier.setSubtractFirstByte(!state.subtractFirstByte);
              },
            ),
            IconButton(
              icon: const Icon(Icons.file_download),
              tooltip: '导出日志',
              onPressed: () => _exportLogs(state),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '清空日志',
              onPressed: () => _confirmClear(state, notifier),
            ),
          ],
        ],
      ),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(UnifiedLogState state) {
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
            SelectableText(state.error!,
                style: const TextStyle(color: Colors.red, fontSize: 14)),
          ],
        ),
      );
    }

    if (state.allEntries.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.list_alt, size: 80, color: Colors.grey),
            SizedBox(height: 20),
            Text('暂无日志记录',
                style: TextStyle(fontSize: 18, color: Colors.grey)),
            SizedBox(height: 8),
            Text('代理请求处理完成后会自动记录到此',
                style: TextStyle(fontSize: 14, color: Colors.grey)),
          ],
        ),
      );
    }

    final displayEntries = state.displayEntries;
    final hasFilter = !state.filter.isEmpty || state.rangeStart != null;

    return Column(
      children: [
        LogSummaryBar(
          stats: state.stats ?? LogStats.compute([]),
          filePath: null,
          filteredStats: hasFilter ? state.stats : null,
          subtractFirstByte: state.subtractFirstByte,
          rangeStart: state.rangeStart,
          rangeEnd: state.rangeEnd,
          onRangeTap: () => _showRangeDialog(state),
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
              controller: _scrollController,
              itemCount: displayEntries.length + (state.hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= displayEntries.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                final item = displayEntries[index];
                return _LogItem(log: item.entry, seq: item.seq);
              },
            ),
          ),
      ],
    );
  }

  Future<void> _confirmClear(UnifiedLogState state, UnifiedLogNotifier notifier) async {
    final filtered = state.filteredEntries;
    if (filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可删除的日志记录')),
      );
      return;
    }
    final count = filtered.length;
    final hasFilter = !state.filter.isEmpty;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除日志'),
        content: Text(hasFilter
            ? '确定要删除当前过滤出的 $count 条日志记录吗？此操作不可撤销。'
            : '确定要删除全部 $count 条日志记录吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await notifier.deleteFilteredLogs();
    }
  }

  Future<void> _exportLogs(UnifiedLogState state) async {
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: '选择导出目录',
    );
    if (dir == null) return;

    final notifier = ref.read(unifiedLogProvider.notifier);
    await notifier.exportLogs(dir);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导出 ${state.filteredEntries.length} 条日志到 $dir')),
      );
    }
  }

  Future<void> _importLogs() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: '选择要导入的日志文件',
      type: FileType.custom,
      allowedExtensions: ['log'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final filePath = result.files.single.path;
    if (filePath == null) return;

    final notifier = ref.read(unifiedLogProvider.notifier);
    final count = await notifier.importLogs(filePath);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已成功导入 $count 条日志记录')),
      );
    }
  }

  Future<void> _showFilterDialog(UnifiedLogState state) async {
    final filter = state.filter;
    final models = UnifiedLogFilter.availableModels(state.allEntries);
    final endpoints = UnifiedLogFilter.availableEndpoints(state.allEntries);
    final keywordCtrl = TextEditingController(text: filter.keyword);
    var tempModelFilter = filter.modelFilter;
    var tempEndpointFilter = filter.endpointFilter;
    var tempKeyword = filter.keyword;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.filter_list,
                        size: 20, color: Colors.blue),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('过滤日志',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
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
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
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
                  onChanged: (v) =>
                      setDialogState(() => tempKeyword = v),
                ),
                if (models.isNotEmpty || endpoints.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (models.isNotEmpty)
                        Expanded(
                          child: _FilterDropdown(
                            label: '模型',
                            value: tempModelFilter,
                            items: models,
                            onChanged: (v) => setDialogState(
                                () => tempModelFilter = v),
                            onClear: tempModelFilter != null
                                ? () => setDialogState(
                                    () => tempModelFilter = null)
                                : null,
                          ),
                        ),
                      if (models.isNotEmpty && endpoints.isNotEmpty)
                        const SizedBox(width: 8),
                      if (endpoints.isNotEmpty)
                        Expanded(
                          child: _FilterDropdown(
                            label: '转发目标',
                            value: tempEndpointFilter,
                            items: endpoints,
                            onChanged: (v) => setDialogState(
                                () => tempEndpointFilter = v),
                            onClear: tempEndpointFilter != null
                                ? () => setDialogState(
                                    () => tempEndpointFilter = null)
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
                        ref
                            .read(unifiedLogProvider.notifier)
                            .setFilter(const UnifiedLogFilter());
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('清除'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        ref
                            .read(unifiedLogProvider.notifier)
                            .setFilter(UnifiedLogFilter(
                          keyword: tempKeyword,
                          modelFilter: tempModelFilter,
                          endpointFilter: tempEndpointFilter,
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
  }

  Future<void> _showRangeDialog(UnifiedLogState state) async {
    var total = state.allEntries.length;
    final curStart = state.rangeStart ?? 0;
    final curEnd = state.rangeEnd ?? total;

    var tempStart = curStart.toDouble();
    var tempEnd = curEnd.toDouble();
    final startCtrl =
        TextEditingController(text: '${curStart + 1}');
    final endCtrl = TextEditingController(text: '$curEnd');

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.linear_scale,
                        size: 20, color: Colors.blueGrey),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('统计区间',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(ctx).pop(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  '共 $total 条，选择统计范围（1 起始）：',
                  style:
                      const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: startCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          labelText: '起始',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(fontSize: 13),
                        onChanged: (v) {
                          final parsed = int.tryParse(v);
                          if (parsed == null) return;
                          final clamped =
                              parsed.clamp(1, tempEnd.toInt());
                          if (clamped != parsed) {
                            startCtrl.text = '$clamped';
                            startCtrl.selection =
                                TextSelection.collapsed(
                                    offset: startCtrl.text.length);
                          }
                          setDialogState(() {
                            tempStart = (clamped - 1).toDouble();
                          });
                        },
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('—',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                    ),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: endCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          labelText: '结束',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(fontSize: 13),
                        onChanged: (v) {
                          final parsed = int.tryParse(v);
                          if (parsed == null) return;
                          final clamped = parsed.clamp(
                              tempStart.toInt() + 1, total);
                          if (clamped != parsed) {
                            endCtrl.text = '$clamped';
                            endCtrl.selection =
                                TextSelection.collapsed(
                                    offset: endCtrl.text.length);
                          }
                          setDialogState(() {
                            tempEnd = clamped.toDouble();
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                RangeSlider(
                  values: RangeValues(tempStart, tempEnd),
                  min: 0,
                  max: total.toDouble(),
                  divisions: total > 1 ? total : null,
                  labels: RangeLabels(
                    '${tempStart.toInt() + 1}',
                    '${tempEnd.toInt()}',
                  ),
                  onChanged: (v) {
                    setDialogState(() {
                      tempStart = v.start;
                      tempEnd = v.end;
                    });
                    startCtrl.text = '${v.start.toInt() + 1}';
                    endCtrl.text = '${v.end.toInt()}';
                  },
                ),
                Text(
                  '显示 ${tempStart.toInt() + 1} ~ ${tempEnd.toInt()}，共 ${(tempEnd - tempStart).toInt()} 条',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (state.hasMore)
                      TextButton.icon(
                        onPressed: () async {
                          await ref.read(unifiedLogProvider.notifier).loadMore();
                          final newState = ref.read(unifiedLogProvider);
                          final newTotal = newState.allEntries.length;
                          setDialogState(() {
                            total = newTotal;
                            if (tempEnd.toInt() > newTotal) {
                              tempEnd = newTotal.toDouble();
                              endCtrl.text = '$newTotal';
                            }
                          });
                        },
                        label: const Text('加载下一页'),
                      )
                    else
                      const SizedBox.shrink(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () {
                            ref
                                .read(unifiedLogProvider.notifier)
                                .clearRange();
                            Navigator.of(ctx).pop();
                          },
                          child: const Text('清除'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () {
                            ref
                                .read(unifiedLogProvider.notifier)
                                .setRange(tempStart.toInt(), tempEnd.toInt());
                            Navigator.of(ctx).pop();
                          },
                          child: const Text('应用'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LogItem extends StatelessWidget {
  final LogEntry log;
  final int seq;
  const _LogItem({required this.log, required this.seq});

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    String statusText;

    if (log.status == LogStatus.pending) {
      statusColor = Colors.orange;
      statusText = '...';
    } else if (log.statusCode != null) {
      statusText = '${log.statusCode}';
      if (log.statusCode! >= 200 && log.statusCode! < 300) {
        statusColor = Colors.green;
      } else if (log.statusCode! >= 400 && log.statusCode! < 500) {
        statusColor = Colors.orange;
      } else if (log.statusCode! >= 500) {
        statusColor = Colors.red;
      } else {
        statusColor = Colors.grey;
      }
    } else {
      statusColor = Colors.red;
      statusText = 'ERR';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      child: ExpansionTile(
        title: Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('$seq',
                  style: const TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                      fontSize: 11)),
            ),
            const SizedBox(width: 6),
            if (log.status == LogStatus.pending)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.orange, width: 1),
                ),
                child: const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: Colors.orange),
                ),
              )
            else
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: statusColor, width: 1),
                ),
                child: Text(statusText,
                    style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 11)),
              ),
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(log.method,
                  style: const TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.w600,
                      fontSize: 11)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(log.path,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis),
            ),
            if (log.status == LogStatus.pending)
              Text(
                  '${DateTime.now().difference(log.time).inMilliseconds} ms',
                  style:
                      const TextStyle(color: Colors.orange, fontSize: 12))
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${log.requestDurationMs}ms',
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 12)),
                  if (log.firstByteDurationMs != null) ...[
                    const SizedBox(width: 4),
                    Text('TTFB ${log.firstByteDurationMs}ms',
                        style: const TextStyle(
                            color: Colors.blueGrey, fontSize: 11)),
                  ],
                ],
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Row(
            children: [
              Text(
                  DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(log.time),
                  style:
                      const TextStyle(color: Colors.grey, fontSize: 12)),
              if (log.model != null) ...[
                const SizedBox(width: 8),
                const Icon(Icons.psychology, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(log.model!,
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
              if (log.targetEndpoint != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(log.targetEndpoint!,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ],
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _LogDetailContent(log: log),
          ),
        ],
      ),
    );
  }
}

class _LogDetailContent extends StatelessWidget {
  final LogEntry log;
  const _LogDetailContent({required this.log});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (log.targetEndpoint != null) ...[
          const Text('转发目标:',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          SelectableText(log.targetEndpoint!),
          const SizedBox(height: 12),
        ],
        if (log.error != null) ...[
          const Text('错误信息:',
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
          const SizedBox(height: 4),
          SelectableText(log.error!,
              style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
        ],
        // 使用 FileLogDetail 展示解析后的请求/响应内容
        if (log.parsedRequest != null || log.parsedResponse != null)
          LogDetail(
            entry: FileLogEntry(
              timestamp: DateFormat('HH:mm:ss.SSS').format(log.time),
              method: log.method,
              path: log.path,
              model: log.model,
              forwardTo: log.targetEndpoint,
              durationMs: log.requestDurationMs,
              firstByteMs: log.firstByteDurationMs,
              statusCode: log.statusCode,
              request: log.parsedRequest,
              response: log.parsedResponse,
              index: 0,
            ),
          ),
      ],
    );
  }
}

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
              child: const Icon(Icons.clear, size: 16, color: Colors.grey),
            ),
        ],
      ),
    );
  }
}
