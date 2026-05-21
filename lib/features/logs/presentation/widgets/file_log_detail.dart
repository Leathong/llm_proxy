import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';
import 'package:llm_proxy/features/logs/presentation/widgets/message_widgets.dart';
import 'package:llm_proxy/features/logs/presentation/widgets/response_content.dart';

/// 日志详情面板
class FileLogDetail extends StatelessWidget {
  final FileLogEntry entry;

  const FileLogDetail({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 转发目标
            if (entry.forwardTo != null) ...[
              DetailSection(
                title: '转发目标',
                child: Text(entry.forwardTo!,
                    style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(height: 12),
            ],

            // Token 用量
            if (entry.response?.usage != null) ...[
              DetailSection(
                title: 'Token 用量',
                child: UsageInfo(usage: entry.response!.usage!),
              ),
              const SizedBox(height: 12),
            ],

            // System Prompt
            if (entry.request?.systemPreview != null) ...[
              DetailSection(
                title: 'System Prompt',
                child: GestureDetector(
                  onTap: () => _showSystemDetail(context, entry.request!),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: Colors.purple.withValues(alpha: 0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.request!.systemPreview!,
                          style: const TextStyle(fontSize: 12, height: 1.5),
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text('点击查看完整内容',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.purple.withValues(alpha: 0.6))),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Tools 定义
            if (entry.request?.tools != null &&
                entry.request!.tools!.isNotEmpty) ...[
              DetailSection(
                title: 'Tools (${entry.request!.tools!.length})',
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: entry.request!.tools!.map((t) {
                    return ActionChip(
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      avatar:
                          const Icon(Icons.build, size: 14, color: Colors.amber),
                      label: Text(t.name, style: const TextStyle(fontSize: 11)),
                      backgroundColor: Colors.amber.withValues(alpha: 0.08),
                      side: BorderSide(
                          color: Colors.amber.withValues(alpha: 0.3)),
                      onPressed: () => _showToolDetail(context, t),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // 对话消息列表
            if (entry.request?.messages.isNotEmpty ?? false) ...[
              DetailSection(
                title: '对话消息 (${entry.request!.messages.length})',
                child: MessageList(messages: entry.request!.messages),
              ),
            ],

            // 响应内容
            if (entry.response?.content != null &&
                entry.response!.content!.isNotEmpty) ...[
              const SizedBox(height: 12),
              DetailSection(
                title: '响应内容',
                child: ResponseContent(content: entry.response!.content!),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showSystemDetail(BuildContext context, FileLogRequest request) {
    final content = request.systemFull ?? request.systemPreview ?? '';
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
          child: SelectionArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom:
                          BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.settings, size: 18, color: Colors.purple),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('System Prompt',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Text(content,
                        style: const TextStyle(fontSize: 12, height: 1.6)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showToolDetail(BuildContext context, FileLogToolDef tool) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
          child: SelectionArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom:
                          BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.build, size: 18, color: Colors.amber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(tool.name,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (tool.description != null) ...[
                          const Text('Description',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(height: 8),
                          Text(tool.description!,
                              style:
                                  const TextStyle(fontSize: 12, height: 1.6)),
                        ],
                        if (tool.inputSchema != null) ...[
                          const SizedBox(height: 16),
                          const Text('Input Schema',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              const JsonEncoder.withIndent('  ')
                                  .convert(tool.inputSchema),
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  height: 1.5),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 详情区块标题
class DetailSection extends StatelessWidget {
  final String title;
  final Widget child;

  const DetailSection({super.key, required this.title, required this.child});

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
class UsageInfo extends StatelessWidget {
  final FileLogUsage usage;

  const UsageInfo({super.key, required this.usage});

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
      label:
          Text('$label: $value', style: TextStyle(fontSize: 11, color: color)),
      backgroundColor: color.withValues(alpha: 0.08),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
    );
  }
}
