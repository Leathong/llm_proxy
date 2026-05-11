import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';

/// 响应内容块列表
class ResponseContent extends StatelessWidget {
  final List<FileLogContentBlock> content;

  const ResponseContent({super.key, required this.content});

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
        // 思考/推理内容块
        if (block.type == 'thinking' && block.text != null) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: Colors.deepPurple.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.psychology,
                        size: 14,
                        color: Colors.deepPurple.withValues(alpha: 0.7)),
                    const SizedBox(width: 6),
                    Text('Thinking',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color:
                                Colors.deepPurple.withValues(alpha: 0.7))),
                  ],
                ),
                const SizedBox(height: 6),
                SelectableText(block.text!,
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: Colors.grey[700])),
              ],
            ),
          );
        }
        if (block.type == 'tool_use') {
          // 格式化 input JSON
          String? inputStr;
          if (block.input != null && block.input!.isNotEmpty) {
            try {
              inputStr =
                  const JsonEncoder.withIndent('  ').convert(block.input);
            } catch (_) {
              inputStr = block.input.toString();
            }
          }

          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 工具名称和 ID
                Row(
                  children: [
                    const Icon(Icons.build, size: 14, color: Colors.amber),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(block.name ?? 'tool_use',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 12)),
                    ),
                    if (block.id != null && block.id!.isNotEmpty)
                      Text(block.id!,
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 10)),
                  ],
                ),
                // 输入参数
                if (inputStr != null && inputStr.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      inputStr,
                      style: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          height: 1.4),
                    ),
                  ),
                ],
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      }).toList(),
    );
  }
}
