import 'package:flutter/material.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';

/// 顶部统计摘要栏
class LogSummaryBar extends StatelessWidget {
  final List<LogOutputEntry> entries;
  final String? filePath;

  const LogSummaryBar({super.key, required this.entries, this.filePath});

  @override
  Widget build(BuildContext context) {
    final totalRequests = entries.length;
    final successCount = entries
        .where((e) =>
            e.statusCode != null &&
            e.statusCode! >= 200 &&
            e.statusCode! < 300)
        .length;
    final errorCount = totalRequests - successCount;
    final avgDuration = entries
            .where((e) => e.durationMs != null)
            .fold<int>(0, (sum, e) => sum + e.durationMs!) ~/
        (entries
            .where((e) => e.durationMs != null)
            .length
            .clamp(1, totalRequests));

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
          if (filePath != null)
            Expanded(
              child: Text(
                filePath!.split('/').last,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          _StatChip(label: '请求', value: '$totalRequests', color: Colors.blue),
          const SizedBox(width: 8),
          _StatChip(
              label: '成功', value: '$successCount', color: Colors.green),
          const SizedBox(width: 8),
          _StatChip(label: '失败', value: '$errorCount', color: Colors.red),
          const SizedBox(width: 8),
          _StatChip(
              label: '平均耗时',
              value: '${avgDuration}ms',
              color: Colors.orange),
          const SizedBox(width: 8),
          _StatChip(
            label: 'Tokens',
            value:
                '${_formatNumber(totalInput)} / ${_formatNumber(totalOutput)}',
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
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w500)),
          const SizedBox(width: 4),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
