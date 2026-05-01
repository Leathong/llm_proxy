import 'package:flutter/material.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';

/// 对话消息列表
class MessageList extends StatelessWidget {
  final List<LogOutputMessage> messages;

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
            Expanded(
              child: Text(
                _previewText(),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        // 工具调用标记
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.toolUses != null && message.toolUses!.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
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
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(
                      message.text!,
                      style: const TextStyle(fontSize: 12, height: 1.5),
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
class ToolUseCard extends StatelessWidget {
  final LogOutputToolUse toolUse;

  const ToolUseCard({super.key, required this.toolUse});

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
class ToolResultCard extends StatelessWidget {
  final LogOutputToolResult result;

  const ToolResultCard({super.key, required this.result});

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
              const Icon(Icons.assignment_returned,
                  size: 14, color: Colors.teal),
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
