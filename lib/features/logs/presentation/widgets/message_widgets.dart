import 'package:flutter/material.dart';
import 'package:llm_proxy/core/theme/app_colors.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';

/// 对话消息列表
class MessageList extends StatelessWidget {
  final List<FileLogMessage> messages;

  const MessageList({super.key, required this.messages});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: messages.map((msg) => _MessageBubble(message: msg)).toList(),
    );
  }
}

/// 单条对话消息
class _MessageBubble extends StatelessWidget {
  final FileLogMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final (Color roleColor, IconData roleIcon) = switch (message.role) {
      'user' => (AppColors.roleUser, Icons.person),
      'assistant' => (AppColors.roleAssistant, Icons.smart_toy),
      'system' => (AppColors.roleSystem, Icons.settings),
      _ => (AppColors.roleDefault, Icons.chat_bubble),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: roleColor.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: roleColor.withValues(alpha: 0.15)),
        ),
        clipBehavior: Clip.antiAlias,
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
            Expanded(
              child: Text(
                _previewText(),
                style: const TextStyle(fontSize: 12, color: AppColors.grey),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.toolUses != null && message.toolUses!.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.toolCall.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('🔧 ${message.toolUses!.length}',
                    style: const TextStyle(fontSize: 11)),
              ),
            if (message.toolResults != null &&
                message.toolResults!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.toolResult.withValues(alpha: 0.15),
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
                // 消息文本（被截断时可点击查看完整内容）
                if (message.text != null && message.text!.isNotEmpty)
                  GestureDetector(
                    onTap: message.textFull != null
                        ? () => _showFullTextDialog(
                            context, message.role, message.textFull!)
                        : null,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            message.text!,
                            style:
                                const TextStyle(fontSize: 12, height: 1.5),
                          ),
                          if (message.textFull != null) ...[
                            const SizedBox(height: 6),
                            Text('点击查看完整内容',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.primary
                                        .withValues(alpha: 0.6))),
                          ],
                        ],
                      ),
                    ),
                  ),

                // 工具调用列表
                if (message.toolUses != null)
                  ...message.toolUses!
                      .map((t) => ToolUseCard(toolUse: t)),

                // 工具结果列表
                if (message.toolResults != null)
                  ...message.toolResults!
                      .map((t) => ToolResultCard(result: t)),
              ],
            ),
          ),
        ],
      ),
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

  void _showFullTextDialog(
      BuildContext context, String role, String fullText) {
    _showDetailDialog(
      context,
      title: '${role.toUpperCase()} 消息',
      icon: Icons.chat,
      iconColor: AppColors.primary,
      content: fullText,
    );
  }
}

/// 工具调用卡片
class ToolUseCard extends StatelessWidget {
  final FileLogToolUse toolUse;

  const ToolUseCard({super.key, required this.toolUse});

  /// inputFull 内容是否比 inputPreview 更长（即发生了截断）
  bool get _wasTruncated =>
      toolUse.inputFull != null &&
      toolUse.inputPreview != null &&
      toolUse.inputFull!.length > toolUse.inputPreview!.length;

  @override
  Widget build(BuildContext context) {
    // 内容较长时格式化展示，始终可点击查看详情弹窗
    final displayText = toolUse.inputFull ?? toolUse.inputPreview ?? '{}';

    return GestureDetector(
      onTap: () => _showToolUseDetail(context),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.toolCall.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.toolCall.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.build, size: 14, color: AppColors.toolCall),
                const SizedBox(width: 6),
                Text(toolUse.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 12)),
                const Spacer(),
                Text(toolUse.id,
                    style:
                        const TextStyle(color: AppColors.grey, fontSize: 10)),
              ],
            ),
            const SizedBox(height: 6),
            // 限制最大高度，超出时省略
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 130),
              child: SelectableText(
                displayText,
                style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    height: 1.3,
                    color: AppColors.greyDark),
              ),
            ),
            if (_wasTruncated) ...[
              const SizedBox(height: 4),
              Text('点击查看完整内容',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.toolCall.withValues(alpha: 0.7))),
            ],
          ],
        ),
      ),
    );
  }

  void _showToolUseDetail(BuildContext context) {
    _showDetailDialog(
      context,
      title: toolUse.name,
      icon: Icons.build,
      iconColor: AppColors.toolCall,
      content: toolUse.inputFull ?? toolUse.inputPreview ?? '{}',
    );
  }
}

/// 工具结果卡片
class ToolResultCard extends StatelessWidget {
  final FileLogToolResult result;

  const ToolResultCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: result.contentFull != null
          ? () => _showDetailDialog(
                context,
                title: '工具结果 → ${result.toolUseId}',
                icon: Icons.assignment_returned,
                iconColor: AppColors.toolResult,
                content: result.contentFull!,
              )
          : null,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.toolResult.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.toolResult.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.assignment_returned,
                    size: 14, color: AppColors.toolResult),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('结果 → ${result.toolUseId}',
                      style:
                          const TextStyle(fontSize: 11, color: AppColors.toolResult),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            if (result.contentPreview != null) ...[
              const SizedBox(height: 6),
              SelectableText(result.contentPreview!,
                  style: const TextStyle(fontSize: 11, color: AppColors.grey)),
            ],
            if (result.contentFull != null) ...[
              const SizedBox(height: 4),
              Text('点击查看完整内容',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.toolResult.withValues(alpha: 0.7))),
            ],
          ],
        ),
      ),
    );
  }
}

/// 通用详情弹窗
void _showDetailDialog(
  BuildContext context, {
  required String title,
  required IconData icon,
  required Color iconColor,
  required String content,
}) {
  showDialog(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom:
                      BorderSide(color: AppColors.grey.withValues(alpha: 0.2)),
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: iconColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
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
                child: SelectableText(content,
                    style: const TextStyle(fontSize: 12, height: 1.6)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
