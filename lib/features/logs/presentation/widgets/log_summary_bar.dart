import 'package:flutter/material.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';

/// 顶部统计摘要栏
class LogSummaryBar extends StatelessWidget {
  final List<FileLogEntry> entries;
  final String? filePath;
  final bool subtractFirstByte;

  /// 过滤后的条目（非空时以此为准计算统计）
  final List<FileLogEntry>? filteredEntries;

  const LogSummaryBar({
    super.key,
    required this.entries,
    this.filePath,
    this.filteredEntries,
    required this.subtractFirstByte,
  });

  /// 百分位计算，支持 int/double 混合列表
  num _percentile(List<num> sorted, int p) {
    if (sorted.isEmpty) return 0;
    final idx = ((p / 100) * (sorted.length - 1)).round();
    return sorted[idx];
  }

  @override
  Widget build(BuildContext context) {
    final statsEntries = filteredEntries ?? entries;

    final totalRequests = statsEntries.length;
    final successCount = statsEntries
        .where((e) => e.statusCode != null && e.statusCode! >= 200 && e.statusCode! < 300)
        .length;
    final errorCount = totalRequests - successCount;

    final durations = statsEntries.where((e) => e.durationMs != null).map((e) => e.durationMs!).toList()..sort();
    final p90 = _percentile(durations, 90);

    final ttfbDurations = statsEntries.where((e) => e.firstByteMs != null).map((e) => e.firstByteMs!).toList()..sort();
    final ttfbP90 = _percentile(ttfbDurations, 90);

    int totalInput = 0;
    int totalOutput = 0;
    int totalCacheCreation = 0;
    int totalCacheRead = 0;
    int entryWithUsage = 0;

    // 收集输出 token 速度（tokens/s）
    final outputSpeeds = <double>[];
    for (final entry in statsEntries) {
      final usage = entry.response?.usage;
      if (usage != null) {
        totalInput += usage.totalInputTokens;
        totalOutput += usage.outputTokens ?? 0;
        totalCacheCreation += usage.cacheCreationInputTokens ?? 0;
        totalCacheRead += usage.cacheReadInputTokens ?? 0;
        entryWithUsage++;
      }
      final speed = entry.outputTokensPerSecond(subtractFirstByte: subtractFirstByte);
      if (speed != null) {
        outputSpeeds.add(speed);
      }
    }
    outputSpeeds.sort((a, b) => b.compareTo(a)); // 降序：从快到慢，last 即最慢
    final speedP90 = _percentile(outputSpeeds, 90);

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
          _StatChip(
            label: 'P90',
            value: '${p90}ms',
            color: Colors.orange,
            onTap: durations.isNotEmpty
                ? () => _showMetricStats(
                      context,
                      sorted: durations,
                      title: '总耗时统计',
                      icon: Icons.timer_outlined,
                      iconColor: Colors.orange,
                      unit: 'ms',
                    )
                : null,
          ),
          const SizedBox(width: 8),
          if (ttfbDurations.isNotEmpty) ...[
            _StatChip(
              label: 'TTFB',
              value: '${ttfbP90}ms',
              color: Colors.teal,
              onTap: () => _showMetricStats(
                context,
                sorted: ttfbDurations,
                title: '首字节耗时 (TTFB)',
                icon: Icons.timer_outlined,
                iconColor: Colors.teal,
                unit: 'ms',
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (outputSpeeds.isNotEmpty) ...[
            _StatChip(
              label: '速度',
              value: '${speedP90.toStringAsFixed(1)} tok/s',
              color: Colors.cyan,
              onTap: () => _showMetricStats(
                context,
                sorted: outputSpeeds,
                title: '输出 Token 速度',
                icon: Icons.speed,
                iconColor: Colors.cyan,
                unit: 'tok/s',
                descending: true,
              ),
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

  /// 通用数值统计弹窗（耗时、TTFB、速度等）
  void _showMetricStats(
    BuildContext context, {
    required List<num> sorted,
    required String title,
    required IconData icon,
    required Color iconColor,
    required String unit,
    bool descending = false,
  }) {
    final max = sorted.last;
    final p90 = _percentile(sorted, 90);
    final p70 = _percentile(sorted, 70);
    final p50 = _percentile(sorted, 50);
    final avg = sorted.fold<num>(0, (s, v) => s + v) / sorted.length;

    showDialog(
      context: context,
      builder: (ctx) => _buildMetricDialog(
        ctx,
        title: title,
        icon: icon,
        iconColor: iconColor,
        max: max,
        p90: p90,
        p70: p70,
        p50: p50,
        avg: avg,
        unit: unit,
        count: sorted.length,
        descending: descending,
      ),
    );
  }

  /// 通用数值统计弹窗 UI
  Widget _buildMetricDialog(
    BuildContext dialogContext, {
    required String title,
    required IconData icon,
    required Color iconColor,
    required num max,
    required num p90,
    required num p70,
    required num p50,
    required num avg,
    required String unit,
    required int count,
    bool descending = false,
  }) {
    String fmt(num v) => unit == 'ms' ? '${v}ms' : '${v.toStringAsFixed(1)} $unit';
    double ratio(num v) {
      if (max.toDouble() <= 0 || v.toDouble() <= 0) return 0;
      return descending ? (max / v).toDouble() : (v / max).toDouble();
    }

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
                  Icon(icon, size: 20, color: iconColor),
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
              _MetricRow(label: descending ? '最慢' : '最快', value: fmt(max), ratio: 1.0, barColor: Colors.red),
              _MetricRow(label: 'P90', value: fmt(p90), ratio: ratio(p90), barColor: Colors.orange),
              _MetricRow(label: 'P70', value: fmt(p70), ratio: ratio(p70), barColor: Colors.amber),
              _MetricRow(label: 'P50', value: fmt(p50), ratio: ratio(p50), barColor: Colors.teal),
              _MetricRow(label: '平均', value: fmt(avg), ratio: ratio(avg), barColor: Colors.blue),
              const SizedBox(height: 8),
              Text('共 $count 条请求', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
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

/// 弹窗中的数值行（带横向 bar 对比），接收格式化后的文本
class _MetricRow extends StatelessWidget {
  final String label;
  final String value;
  final double ratio;
  final Color barColor;

  const _MetricRow({
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
            width: 72,
            child: Text(
              value,
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
