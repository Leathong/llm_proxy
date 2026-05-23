import 'package:flutter/material.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';
import 'package:llm_proxy/features/logs/presentation/widgets/file_log_detail.dart';

/// 单条日志条目，展开后点击空白区域可收起
class FileLogItem extends StatefulWidget {
  final FileLogEntry entry;
  final bool subtractFirstByte;

  const FileLogItem({
    super.key,
    required this.entry,
    required this.subtractFirstByte,
  });

  @override
  State<FileLogItem> createState() => _FileLogItemState();
}

class _FileLogItemState extends State<FileLogItem> {
  final _controller = ExpansibleController();
  final _key = GlobalKey();

  FileLogEntry get entry => widget.entry;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 标记是否由我们主动触发收起（区分 title 点击收起 vs GestureDetector 收起）
  bool _collapsingByUs = false;

  /// 点击展开内容区域收起：先滚回可视区域，再执行收起
  Future<void> _scrollThenCollapse() async {
    final ctx = _key.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    }
    _collapsingByUs = true;
    _controller.collapse();
  }

  /// 处理 ExpansionTile 通过 title 点击触发的收起（非我们主动触发时补偿滚动）
  void _onExpansionChanged(bool expanded) {
    if (!expanded && !_collapsingByUs) {
      Future.delayed(const Duration(milliseconds: 250), () {
        final ctx = _key.currentContext;
        if (ctx != null && ctx.mounted) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
          );
        }
      });
    }
    _collapsingByUs = false;
  }

  /// 从 response content 中提取文本预览，用于标题行快速定位
  String _buildResponsePreview() {
    final content = entry.response?.content;
    if (content == null || content.isEmpty) return entry.path;

    final texts = <String>[];
    for (final block in content) {
      if (block.type == 'text' && block.text != null) {
        texts.add(block.text!);
      } else if (block.type == 'tool_use' && block.name != null) {
        texts.add('[调用工具: ${block.name}]');
      }
    }
    if (texts.isEmpty) return entry.path;
    return texts.join(' ').replaceAll('\n', ' ').trim();
  }

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
    final outputSpeed = entry.outputTokensPerSecond(
      subtractFirstByte: widget.subtractFirstByte,
    );

    // 提取 response 内容预览文本
    final responsePreview = _buildResponsePreview();

    return SelectionArea(
      key: _key,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        elevation: 1,
        child: ExpansionTile(
          controller: _controller,
          onExpansionChanged: _onExpansionChanged,
          // 标题行：序号 + 状态码 + 方法 + response 预览 + 耗时
          title: Row(
            children: [
              SizedBox(
                width: 35,
                child: Text('#${entry.index}',
                    style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ),
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
              Expanded(
                child: Text(responsePreview,
                    style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 13),
                    overflow: TextOverflow.ellipsis),
              ),
              if (entry.durationMs != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${entry.durationMs}ms',
                        style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    if (entry.firstByteMs != null) ...[
                      const SizedBox(width: 4),
                      Text('TTFB ${entry.firstByteMs}ms',
                          style: const TextStyle(color: Colors.blueGrey, fontSize: 11)),
                    ],
                    if (outputSpeed != null) ...[
                      const SizedBox(width: 4),
                      Text('${outputSpeed.toStringAsFixed(1)} tok/s',
                          style: const TextStyle(color: Colors.teal, fontSize: 11)),
                    ],
                  ],
                ),
            ],
          ),
          // 副标题：endpoint + 时间 + 模型 + 消息数
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                // endpoint 路径（限制最大宽度，避免挤掉右侧信息）
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(entry.path,
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
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
                if (entry.request?.tools != null) ...[
                  const Icon(Icons.build, size: 13, color: Colors.amber),
                  const SizedBox(width: 2),
                  Text('${entry.request!.tools!.length}',
                      style:
                          const TextStyle(color: Colors.amber, fontSize: 11)),
                  const SizedBox(width: 6),
                ],
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
          // 展开后显示详情，点击空白区域收起
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _scrollThenCollapse,
              child: Padding(
                padding: const EdgeInsets.all(12),
                // 内部内容吸收点击，避免点击消息等内容时触发收起
                child: GestureDetector(
                  onTap: () {},
                  child: FileLogDetail(entry: entry),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
