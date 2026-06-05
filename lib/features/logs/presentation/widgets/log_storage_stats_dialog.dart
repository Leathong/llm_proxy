import 'package:flutter/material.dart';
import 'package:llm_proxy/core/theme/app_colors.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_storage_stats.dart';

class LogStorageStatsDialog extends StatelessWidget {
  final LogStorageStats stats;

  const LogStorageStatsDialog({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.storage, size: 22),
          SizedBox(width: 8),
          Text('日志存储统计'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRow(Icons.list_alt, '日志记录', '${stats.totalCount} 条'),
          const Divider(),
          _buildRow(
            Icons.schedule,
            '时间跨度',
            stats.timeSpanText,
          ),
          const Divider(),
          _buildRow(
            Icons.table_chart,
            '日志表占用',
            LogStorageStats.formatBytes(stats.logTableBytes),
          ),
          const Divider(),
          _buildRow(
            Icons.dns,
            '数据库文件',
            '${LogStorageStats.formatBytes(stats.databaseFileBytes)}（含所有表）',
          ),
          if (stats.walFileBytes != null) ...[
            const Divider(),
            _buildRow(
              Icons.description,
              'WAL 文件',
              LogStorageStats.formatBytes(stats.walFileBytes!),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.grey),
          const SizedBox(width: 10),
          Text('$label：', style: const TextStyle(fontSize: 14)),
          const Spacer(),
          SelectableText(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
