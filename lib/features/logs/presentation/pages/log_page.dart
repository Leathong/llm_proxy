import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_entry.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_stats.dart';
import 'package:llm_proxy/features/logs/presentation/providers/log_providers.dart';
import 'package:llm_proxy/features/logs/presentation/widgets/log_filter_dialog.dart';
import 'package:llm_proxy/features/logs/presentation/widgets/log_item.dart';
import 'package:llm_proxy/features/logs/presentation/widgets/log_range_dialog.dart';
import 'package:llm_proxy/features/logs/presentation/widgets/log_summary_bar.dart';

class LogPage extends ConsumerStatefulWidget {
  const LogPage({super.key});

  @override
  ConsumerState<LogPage> createState() => _LogPageState();
}

class _LogPageState extends ConsumerState<LogPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _pageSizeController = TextEditingController(text: pageSizeConst.toString());

  LogNotifier get _notifier => ref.read(logProvider.notifier);

  @override
  void dispose() {
    _pageSizeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(logProvider);
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
              _notifier.setReversed(!state.reversed);
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
              _notifier.setSubtractFirstByte(!state.subtractFirstByte);
            },
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: '导出日志',
            onPressed: () => _exportLogs(state),
          ),
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: '清空显示',
            onPressed: () => _notifier.clearMemory(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除日志',
            onSelected: (value) {
              if (value == 'filtered') {
                _confirmClear(state);
              } else if (value == 'all') {
                _confirmClearAll();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'filtered',
                child: ListTile(
                  leading: const Icon(Icons.filter_list),
                  title: const Text('删除过滤出的日志'),
                  subtitle: Text('共 ${state.filteredEntries.length} 条'),
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              PopupMenuItem(
                value: 'all',
                child: ListTile(
                  leading: const Icon(Icons.delete_forever),
                  title: const Text('清空全部日志'),
                  subtitle: const Text('清空整个数据库的所有日志记录'),
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(LogState state) {
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

    final displayEntries = state.displayEntries;
    final hasFilter = !state.filter.isEmpty || state.rangeStart != null;
    final showLoadMore = state.hasMore && (displayEntries.isNotEmpty || state.allEntries.isEmpty);

    return Column(
      children: [
        LogSummaryBar(
          stats: state.stats ?? LogStats.compute([]),
          filePath: null,
          filteredStats: hasFilter ? state.stats : null,
          subtractFirstByte: state.subtractFirstByte,
          rangeStart: state.rangeStart,
          rangeEnd: state.rangeEnd,
          totalCount: state.totalCount,
          onRangeTap: () => _showRangeDialog(state),
        ),
        const Divider(height: 1),
        Expanded(
          child: displayEntries.isNotEmpty
              ? ListView.builder(
                  controller: _scrollController,
                  itemCount: displayEntries.length + (showLoadMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= displayEntries.length) {
                      return _buildLoadMoreButton(isLoadingMore: state.isLoadingMore);
                    }
                    final item = displayEntries[index];
                    return LogItem(
                      entry: _toFileLogEntry(item.entry, item.seq),
                      subtractFirstByte: state.subtractFirstByte,
                    );
                  },
                )
              : Center(
                  child: state.allEntries.isEmpty && !state.hasMore
                      ? const Column(
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
                        )
                      : showLoadMore
                          ? _buildLoadMoreButton(isLoadingMore: state.isLoadingMore)
                          : const Text('没有匹配的日志记录',
                              style: TextStyle(color: Colors.grey, fontSize: 14)),
                ),
        ),
      ],
    );
  }

  Widget _buildLoadMoreButton({bool isLoadingMore = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Center(
        child: isLoadingMore
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 60,
                    child: TextField(
                      controller: _pageSizeController,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        final parsed = int.tryParse(v);
                        if (parsed != null && parsed > 0) {
                          _notifier.setPageSize(parsed);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('条/页', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 32,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.expand_more, size: 18),
                      label: const Text('加载更多'),
                      onPressed: () => _notifier.loadMore(),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  FileLogEntry _toFileLogEntry(LogEntry log, int seq) {
    return FileLogEntry(
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
      index: seq,
    );
  }

  Future<void> _confirmClear(LogState state) async {
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
      await _notifier.deleteFilteredLogs();
    }
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空全部日志'),
        content: const Text('确定要清空数据库中的所有日志记录吗？此操作不可撤销。'),
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
      await _notifier.clearAllLogs();
    }
  }

  Future<void> _exportLogs(LogState state) async {
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: '选择导出目录',
    );
    if (dir == null) return;

    final notifier = ref.read(logProvider.notifier);
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

    final notifier = ref.read(logProvider.notifier);
    final count = await notifier.importLogs(filePath);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已成功导入 $count 条日志记录')),
      );
    }
  }

  void _showFilterDialog(LogState state) {
    showDialog(
      context: context,
      builder: (_) => LogFilterDialog(state: state),
    );
  }

  void _showRangeDialog(LogState state) {
    showDialog(
      context: context,
      builder: (_) => LogRangeDialog(state: state),
    );
  }
}
