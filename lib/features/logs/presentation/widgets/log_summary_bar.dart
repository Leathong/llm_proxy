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

    // 汇总 token 用量，同时收集有 usage 的条目用于详情弹窗
    int totalInput = 0;
    int totalOutput = 0;
    int totalCacheCreation = 0;
    int totalCacheRead = 0;
    int entryWithUsage = 0;
    for (final entry in statsEntries) {
      final usage = entry.response?.usage;
      if (usage != null) {
        totalInput += usage.totalInputTokens;
        totalOutput += usage.outputTokens ?? 0;
        totalCacheCreation += usage.cacheCreationInputTokens ?? 0;
        totalCacheRead += usage.cacheReadInputTokens ?? 0;
        entryWithUsage++;
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
            onTap: durations.isNotEmpty ? () => _showDurationStats(context, durations) : null,
          ),
          const SizedBox(width: 8),
          if (ttfbDurations.isNotEmpty) ...[
            _StatChip(
              label: 'TTFB',
              value: '${ttfbP90}ms',
              color: Colors.teal,
              onTap: () => _showTtfbStats(context, ttfbDurations),
            ),
            const SizedBox(width: 8),
          ],
          _StatChip(
            label: 'Tokens',
            value: '${_formatNumber(totalInput)} / ${_formatNumber(totalOutput)}',
            color: Colors.purple,
            onTap: entryWithUsage > 0
                ? () => _showTokenStats(
                      context,
                      totalInput: totalInput,
                      totalOutput: totalOutput,
                      totalCacheCreation: totalCacheCreation,
                      totalCacheRead: totalCacheRead,
                      entryCount: entryWithUsage,
                    )
                : null,
          ),
        ],
      ),
    );
  }

  /// 弹出总耗时详细统计面板
  void _showDurationStats(BuildContext context, List<int> sorted) {
    final max = sorted.last;
    final p90 = _percentile(sorted, 90);
    final p70 = _percentile(sorted, 70);
    final p50 = _percentile(sorted, 50);
    final avg = sorted.fold<int>(0, (s, v) => s + v) ~/ sorted.length;

    showDialog(
      context: context,
      builder: (ctx) => _buildStatsDialog(
        ctx,
        title: '总耗时统计',
        iconColor: Colors.orange,
        sorted: sorted,
        max: max,
        p90: p90,
        p70: p70,
        p50: p50,
        avg: avg,
      ),
    );
  }

  /// 弹出 TTFB 首字节耗时统计面板
  void _showTtfbStats(BuildContext context, List<int> sorted) {
    final max = sorted.last;
    final p90 = _percentile(sorted, 90);
    final p70 = _percentile(sorted, 70);
    final p50 = _percentile(sorted, 50);
    final avg = sorted.fold<int>(0, (s, v) => s + v) ~/ sorted.length;

    showDialog(
      context: context,
      builder: (ctx) => _buildStatsDialog(
        ctx,
        title: '首字节耗时 (TTFB)',
        iconColor: Colors.teal,
        sorted: sorted,
        max: max,
        p90: p90,
        p70: p70,
        p50: p50,
        avg: avg,
      ),
    );
  }

  /// 弹出 Token 用量详情面板
  void _showTokenStats(
    BuildContext context, {
    required int totalInput,
    required int totalOutput,
    required int totalCacheCreation,
    required int totalCacheRead,
    required int entryCount,
  }) {
    final totalTokens = totalInput + totalOutput;
    final hasCache = totalCacheCreation > 0 || totalCacheRead > 0;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
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
                    const Icon(Icons.token_outlined, size: 20, color: Colors.purple),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Token 用量统计', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(ctx).pop(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _TokenRow(label: '总输入', value: totalInput, color: Colors.blue),
                _TokenRow(label: '总输出', value: totalOutput, color: Colors.green),
                const Divider(height: 20),
                _TokenRow(label: '合计', value: totalTokens, color: Colors.purple, bold: true),
                if (hasCache) ...[
                  const SizedBox(height: 12),
                  Text('缓存用量', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  const SizedBox(height: 6),
                  if (totalCacheCreation > 0)
                    _TokenRow(label: '缓存写入', value: totalCacheCreation, color: Colors.orange),
                  if (totalCacheRead > 0) ...[
                    _TokenRow(label: '缓存命中', value: totalCacheRead, color: Colors.teal),
                    if (totalInput > 0)
                      _TokenRow(
                        label: '命中率',
                        value: totalCacheRead,
                        color: Colors.teal,
                        suffix: '${(totalCacheRead / totalInput * 100).toStringAsFixed(1)}%',
                      ),
                  ],
                ],
                const SizedBox(height: 8),
                Text('共 $entryCount 条请求包含 Token 数据', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建统计弹窗的通用 Widget
  Widget _buildStatsDialog(
    BuildContext dialogContext, {
    required String title,
    required Color iconColor,
    required List<int> sorted,
    required int max,
    required int p90,
    int? p70,
    required int p50,
    required int avg,
  }) {
    return Dialog(
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
                  Icon(Icons.timer_outlined, size: 20, color: iconColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _DurationRow(label: '最慢', value: max, ratio: 1.0, barColor: Colors.red),
              _DurationRow(label: 'P90', value: p90, ratio: max > 0 ? p90 / max : 0, barColor: Colors.orange),
              if (p70 != null)
                _DurationRow(label: 'P70', value: p70, ratio: max > 0 ? p70 / max : 0, barColor: Colors.amber),
              _DurationRow(label: 'P50', value: p50, ratio: max > 0 ? p50 / max : 0, barColor: Colors.teal),
              _DurationRow(label: '平均', value: avg, ratio: max > 0 ? avg / max : 0, barColor: Colors.blue),
              const SizedBox(height: 8),
              Text('共 ${sorted.length} 条请求', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
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

/// Token 弹窗中的用量行
class _TokenRow extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final bool bold;
  final String? suffix;

  const _TokenRow({
    required this.label,
    required this.value,
    required this.color,
    this.bold = false,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            _format(value),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          if (suffix != null) ...[
            const SizedBox(width: 6),
            Text(
              suffix!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _format(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(2)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}
