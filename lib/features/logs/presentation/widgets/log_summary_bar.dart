import 'package:flutter/material.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';

/// 顶部统计摘要栏
class LogSummaryBar extends StatelessWidget {
  final List<FileLogEntry> entries;
  final String? filePath;

  /// 过滤后的条目（非空时以此为准计算统计）
  final List<FileLogEntry>? filteredEntries;

  const LogSummaryBar({
    super.key,
    required this.entries,
    this.filePath,
    this.filteredEntries,
  });

  /// 计算百分位耗时（P50/P70/P90 等）
  int _percentile(List<int> sorted, int p) {
    if (sorted.isEmpty) return 0;
    final idx = ((p / 100) * (sorted.length - 1)).round();
    return sorted[idx];
  }

  @override
  Widget build(BuildContext context) {
    // 当有过滤条件时，统计针对过滤后的列表
    final statsEntries = filteredEntries ?? entries;

    final totalRequests = statsEntries.length;
    final successCount = statsEntries
        .where((e) => e.statusCode != null && e.statusCode! >= 200 && e.statusCode! < 300)
        .length;
    final errorCount = totalRequests - successCount;

    // 排序后的耗时列表，用于百分位计算
    final durations = statsEntries.where((e) => e.durationMs != null).map((e) => e.durationMs!).toList()..sort();
    final p90 = _percentile(durations, 90);

    // TTFB 首字节耗时统计
    final ttfbDurations = statsEntries.where((e) => e.firstByteMs != null).map((e) => e.firstByteMs!).toList()..sort();
    final ttfbP90 = _percentile(ttfbDurations, 90);

    // 汇总 token 用量
    int totalInput = 0;
    int totalOutput = 0;
    for (final entry in statsEntries) {
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
          // P90 耗时，点击弹出详细统计
          _StatChip(
            label: 'P90',
            value: '${p90}ms',
            color: Colors.orange,
            onTap: durations.isNotEmpty ? () => _showDurationStats(context, durations, ttfbDurations) : null,
          ),
          const SizedBox(width: 8),
          if (ttfbDurations.isNotEmpty) ...[
            _StatChip(
              label: 'TTFB',
              value: '${ttfbP90}ms',
              color: Colors.teal,
            ),
            const SizedBox(width: 8),
          ],
          _StatChip(
            label: 'Tokens',
            value: '${_formatNumber(totalInput)} / ${_formatNumber(totalOutput)}',
            color: Colors.purple,
          ),
        ],
      ),
    );
  }

  /// 弹出耗时详细统计面板
  void _showDurationStats(BuildContext context, List<int> sorted, List<int> ttfbSorted) {
    final max = sorted.last;
    final p90 = _percentile(sorted, 90);
    final p70 = _percentile(sorted, 70);
    final p50 = _percentile(sorted, 50);
    final avg = sorted.fold<int>(0, (s, v) => s + v) ~/ sorted.length;

    // TTFB 统计
    final ttfbMax = ttfbSorted.isNotEmpty ? ttfbSorted.last : 0;
    final ttfbP90 = _percentile(ttfbSorted, 90);
    final ttfbP50 = _percentile(ttfbSorted, 50);
    final ttfbAvg = ttfbSorted.isNotEmpty ? ttfbSorted.fold<int>(0, (s, v) => s + v) ~/ ttfbSorted.length : 0;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 20, color: Colors.orange),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('耗时统计', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  '总耗时',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange),
                ),
                const SizedBox(height: 4),
                _DurationRow(label: '最慢', value: max, ratio: 1.0, barColor: Colors.red),
                _DurationRow(label: 'P90', value: p90, ratio: max > 0 ? p90 / max : 0, barColor: Colors.orange),
                _DurationRow(label: 'P70', value: p70, ratio: max > 0 ? p70 / max : 0, barColor: Colors.amber),
                _DurationRow(label: 'P50', value: p50, ratio: max > 0 ? p50 / max : 0, barColor: Colors.teal),
                _DurationRow(label: '平均', value: avg, ratio: max > 0 ? avg / max : 0, barColor: Colors.blue),
                if (ttfbSorted.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    '首字节 (TTFB)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.teal),
                  ),
                  const SizedBox(height: 4),
                  _DurationRow(label: '最慢', value: ttfbMax, ratio: 1.0, barColor: Colors.red),
                  _DurationRow(
                    label: 'P90',
                    value: ttfbP90,
                    ratio: ttfbMax > 0 ? ttfbP90 / ttfbMax : 0,
                    barColor: Colors.orange,
                  ),
                  _DurationRow(
                    label: 'P50',
                    value: ttfbP50,
                    ratio: ttfbMax > 0 ? ttfbP50 / ttfbMax : 0,
                    barColor: Colors.teal,
                  ),
                  _DurationRow(
                    label: '平均',
                    value: ttfbAvg,
                    ratio: ttfbMax > 0 ? ttfbAvg / ttfbMax : 0,
                    barColor: Colors.blue,
                  ),
                ],
                const SizedBox(height: 8),
                Text('共 ${sorted.length} 条请求', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        ),
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
  final VoidCallback? onTap;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 3),
            Icon(Icons.chevron_right, size: 14, color: color),
          ],
        ],
      ),
    );
    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: child);
    }
    return child;
  }
}

/// 弹窗中的耗时行（带横向 bar 对比）
class _DurationRow extends StatelessWidget {
  final String label;
  final int value;
  final double ratio;
  final Color barColor;

  const _DurationRow({
    required this.label,
    required this.value,
    required this.ratio,
    required this.barColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 14,
                backgroundColor: barColor.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation(barColor.withValues(alpha: 0.5)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: Text(
              '${value}ms',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: barColor),
            ),
          ),
        ],
      ),
    );
  }
}
