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
