import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';
import 'package:llm_proxy/features/logs/presentation/providers/log_output_providers.dart';

class LogOutputPage extends ConsumerWidget {
  const LogOutputPage({super.key});

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
      allowedExtensions: ['json'],
      dialogTitle: '选择日志 JSON 文件',
    );
    if (result != null && result.files.single.path != null) {
      ref.read(logOutputProvider.notifier).loadFile(result.files.single.path!);
    }
  }

  Widget _buildBody(BuildContext context, LogOutputState state) {
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
            Text('点击右上角 📂 按钮加载日志文件',
                style: TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      );
    }

    // 统计摘要 + 日志列表
    return Column(
      children: [
        _LogSummaryBar(entries: state.entries, filePath: state.filePath),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: state.entries.length,
            itemBuilder: (context, index) =>
                _LogOutputItem(entry: state.entries[index]),
          ),
        ),
      ],
    );
  }
}

/// 顶部统计摘要栏
class _LogSummaryBar extends StatelessWidget {
  final List<LogOutputEntry> entries;
  final String? filePath;

  const _LogSummaryBar({required this.entries, this.filePath});

  @override
  Widget build(BuildContext context) {
    final totalRequests = entries.length;
    final successCount =
        entries.where((e) => e.statusCode != null && e.statusCode! >= 200 && e.statusCode! < 300).length;
    final errorCount = totalRequests - successCount;
    final avgDuration = entries
        .where((e) => e.durationMs != null)
        .fold<int>(0, (sum, e) => sum + e.durationMs!) ~/
        (entries.where((e) => e.durationMs != null).length.clamp(1, totalRequests));

    // 汇总 token 用量
    int totalInput = 0;
    int totalOutput = 0;
    for (final entry in entries) {
      final usage = entry.response?.usage;
      if (usage != null) {
        totalInput += usage.totalInputTokens;
        totalOutput += usage.outputTokens ?? 0;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          // 文件名
          if (filePath != null)
            Expanded(
              child: Text(
                filePath!.split('/').last,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          _StatChip(label: '请求', value: '$totalRequests', color: Colors.blue),
          const SizedBox(width: 8),
          _StatChip(label: '成功', value: '$successCount', color: Colors.green),
          const SizedBox(width: 8),
          _StatChip(label: '失败', value: '$errorCount', color: Colors.red),
          const SizedBox(width: 8),
          _StatChip(label: '平均耗时', value: '${avgDuration}ms', color: Colors.orange),
          const SizedBox(width: 8),
          _StatChip(
            label: 'Tokens',
            value: '${_formatNumber(totalInput)} / ${_formatNumber(totalOutput)}',
            color: Colors.purple,
          ),
        ],
      ),
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

/// 统计指标小标签
class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500)),
          const SizedBox(width: 4),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// 单条日志条目
class _LogOutputItem extends StatelessWidget {
  final LogOutputEntry entry;

  const _LogOutputItem({required this.entry});

  @override
  Widget build(BuildContext context) {
    // 状态码颜色
    Color statusColor;
    if (entry.statusCode != null) {
      if (entry.statusCode! >= 200 && entry.statusCode! < 300) {
        statusColor = Colors.green;
      } else if (entry.statusCode! >= 400) {
        statusColor = Colors.red;
      } else {
        statusColor = Colors.orange;
      }
    } else {
      statusColor = Colors.grey;
    }

    final messageCount = entry.request?.messages.length ?? 0;
    final usage = entry.response?.usage;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 1,
      child: ExpansionTile(
        // 标题行：序号 + 状态码 + 方法 + 路径 + 耗时
        title: Row(
          children: [
            // 序号
            SizedBox(
              width: 28,
              child: Text('#${entry.index}',
                  style: const TextStyle(color: Colors.grey, fontSize: 11)),
            ),
            // 状态码
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: statusColor, width: 1),
              ),
              child: Text('${entry.statusCode ?? "N/A"}',
                  style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 11)),
            ),
            const SizedBox(width: 6),
            // 方法
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(entry.method,
                  style: const TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.w600,
                      fontSize: 11)),
            ),
            const SizedBox(width: 8),
            // 路径
            Expanded(
              child: Text(entry.path,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis),
            ),
            if (entry.durationMs != null)
              Text('${entry.durationMs}ms',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
        // 副标题：时间 + 模型 + 消息数
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Text(entry.timestamp,
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
              if (entry.model != null) ...[
                const SizedBox(width: 8),
                const Icon(Icons.psychology, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(entry.model!,
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
              const Spacer(),
              if (messageCount > 0)
                Text('$messageCount 条消息',
                    style: const TextStyle(color: Colors.grey, fontSize: 11)),
              if (usage != null) ...[
                const SizedBox(width: 8),
                const Icon(Icons.token, size: 13, color: Colors.grey),
                const SizedBox(width: 2),
                Text('${usage.totalInputTokens}→${usage.outputTokens ?? 0}',
                    style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ],
          ),
        ),
        // 展开后显示详情
        children: [_LogOutputDetail(entry: entry)],
      ),
    );
  }
}

/// 日志详情面板
class _LogOutputDetail extends StatelessWidget {
  final LogOutputEntry entry;

  const _LogOutputDetail({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 转发目标
          if (entry.forwardTo != null) ...[
            _DetailSection(
              title: '转发目标',
              child: SelectableText(entry.forwardTo!,
                  style: const TextStyle(fontSize: 13)),
            ),
            const SizedBox(height: 12),
          ],

          // Token 用量
          if (entry.response?.usage != null) ...[
            _DetailSection(
              title: 'Token 用量',
              child: _UsageInfo(usage: entry.response!.usage!),
            ),
            const SizedBox(height: 12),
          ],

          // 对话消息列表
          if (entry.request?.messages.isNotEmpty ?? false) ...[
            _DetailSection(
              title: '对话消息 (${entry.request!.messages.length})',
              child: _MessageList(messages: entry.request!.messages),
            ),
          ],

          // 响应内容
          if (entry.response?.content != null &&
              entry.response!.content!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _DetailSection(
              title: '响应内容',
              child: _ResponseContent(content: entry.response!.content!),
            ),
          ],
        ],
      ),
    );
  }
}

/// 详情区块标题
class _DetailSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _DetailSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

/// Token 用量展示
class _UsageInfo extends StatelessWidget {
  final LogOutputUsage usage;

  const _UsageInfo({required this.usage});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        if (usage.inputTokens != null)
          _tokenChip('输入', usage.inputTokens!, Colors.blue),
        if (usage.cacheCreationInputTokens != null)
          _tokenChip('缓存创建', usage.cacheCreationInputTokens!, Colors.teal),
        if (usage.cacheReadInputTokens != null)
          _tokenChip('缓存读取', usage.cacheReadInputTokens!, Colors.cyan),
        if (usage.outputTokens != null)
          _tokenChip('输出', usage.outputTokens!, Colors.orange),
      ],
    );
  }

  Widget _tokenChip(String label, int value, Color color) {
    return Chip(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      label: Text('$label: $value', style: TextStyle(fontSize: 11, color: color)),
      backgroundColor: color.withValues(alpha: 0.08),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
    );
  }
}

/// 对话消息列表
class _MessageList extends StatelessWidget {
  final List<LogOutputMessage> messages;

  const _MessageList({required this.messages});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: messages.map((msg) => _MessageBubble(message: msg)).toList(),
    );
  }
}

/// 单条对话消息
class _MessageBubble extends StatelessWidget {
  final LogOutputMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    // 角色对应的颜色和图标
    final (Color roleColor, IconData roleIcon) = switch (message.role) {
      'user' => (Colors.blue, Icons.person),
      'assistant' => (Colors.green, Icons.smart_toy),
      'system' => (Colors.purple, Icons.settings),
      _ => (Colors.grey, Icons.chat_bubble),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: roleColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: roleColor.withValues(alpha: 0.15)),
      ),
      child: ExpansionTile(
        dense: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Icon(roleIcon, size: 18, color: roleColor),
        title: Row(
          children: [
            Text(message.role.toUpperCase(),
                style: TextStyle(
                    color: roleColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12)),
            const SizedBox(width: 8),
            // 内容预览
            Expanded(
              child: Text(
                _previewText(),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        // 展示工具调用标记
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.toolUses != null && message.toolUses!.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('🔧 ${message.toolUses!.length}',
                    style: const TextStyle(fontSize: 11)),
              ),
            if (message.toolResults != null && message.toolResults!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('📋 ${message.toolResults!.length}',
                      style: const TextStyle(fontSize: 11)),
                ),
              ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 消息文本
                if (message.text != null && message.text!.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(
                      message.text!,
                      style: const TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ),

                // 工具调用列表
                if (message.toolUses != null)
                  ...message.toolUses!.map((t) => _ToolUseCard(toolUse: t)),

                // 工具结果列表
                if (message.toolResults != null)
                  ...message.toolResults!.map((t) => _ToolResultCard(result: t)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _previewText() {
    if (message.text != null && message.text!.isNotEmpty) {
      return message.text!.replaceAll('\n', ' ').trim();
    }
    if (message.toolUses != null && message.toolUses!.isNotEmpty) {
      return '调用工具: ${message.toolUses!.map((t) => t.name).join(', ')}';
    }
    if (message.toolResults != null && message.toolResults!.isNotEmpty) {
      return '工具结果 x${message.toolResults!.length}';
    }
    return '(空)';
  }
}

/// 工具调用卡片
class _ToolUseCard extends StatelessWidget {
  final LogOutputToolUse toolUse;

  const _ToolUseCard({required this.toolUse});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.build, size: 14, color: Colors.amber),
              const SizedBox(width: 6),
              Text(toolUse.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 12)),
              const Spacer(),
              Text(toolUse.id,
                  style: const TextStyle(color: Colors.grey, fontSize: 10)),
            ],
          ),
          if (toolUse.inputPreview != null) ...[
            const SizedBox(height: 6),
            SelectableText(toolUse.inputPreview!,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ],
      ),
    );
  }
}

/// 工具结果卡片
class _ToolResultCard extends StatelessWidget {
  final LogOutputToolResult result;

  const _ToolResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment_returned, size: 14, color: Colors.teal),
              const SizedBox(width: 6),
              Expanded(
                child: Text('结果 → ${result.toolUseId}',
                    style: const TextStyle(fontSize: 11, color: Colors.teal),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          if (result.contentPreview != null) ...[
            const SizedBox(height: 6),
            SelectableText(result.contentPreview!,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ],
      ),
    );
  }
}

/// 响应内容块列表
class _ResponseContent extends StatelessWidget {
  final List<LogOutputContentBlock> content;

  const _ResponseContent({required this.content});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: content.map((block) {
        if (block.type == 'text' && block.text != null) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(block.text!,
                style: const TextStyle(fontSize: 12, height: 1.5)),
          );
        }
        if (block.type == 'tool_use') {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.build, size: 14, color: Colors.amber),
                const SizedBox(width: 6),
                Text(block.name ?? 'tool_use',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 12)),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      }).toList(),
    );
  }
}
