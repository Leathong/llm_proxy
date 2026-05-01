import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/features/logs/presentation/providers/file_log_providers.dart';
import 'package:llm_proxy/features/logs/presentation/widgets/file_log_item.dart';
import 'package:llm_proxy/features/logs/presentation/widgets/log_summary_bar.dart';

class FileLogPage extends ConsumerWidget {
  const FileLogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logState = ref.watch(logOutputProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('日志分析'),
        actions: [
          // 加载文件按钮
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

    // 统计摘要 + 日志列表
    return Column(
      children: [
        LogSummaryBar(entries: state.entries, filePath: state.filePath),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: state.entries.length,
            itemBuilder: (context, index) =>
                FileLogItem(entry: state.entries[index]),
          ),
        ),
      ],
    );
  }
}
