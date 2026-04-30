import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/log_provider.dart';
import '../models/proxy_log.dart';

class LogPage extends StatelessWidget {
  const LogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志查看'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空日志',
            onPressed: () {
              context.read<LogProvider>().clearLogs();
            },
          ),
        ],
      ),
      body: Consumer<LogProvider>(
        builder: (context, logProvider, child) {
          final logs = logProvider.logs;
          if (logs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.list_alt, size: 80, color: Colors.grey),
                  SizedBox(height: 20),
                  Text(
                    '暂无抓包日志',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }
          
          return ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              return _buildLogItem(context, log);
            },
          );
        },
      ),
    );
  }

  Widget _buildLogItem(BuildContext context, ProxyLog log) {
    Color statusColor = Colors.grey;
    if (log.statusCode != null) {
      if (log.statusCode! >= 200 && log.statusCode! < 300) {
        statusColor = Colors.green;
      } else if (log.statusCode! >= 400 && log.statusCode! < 500) {
        statusColor = Colors.orange;
      } else if (log.statusCode! >= 500) {
        statusColor = Colors.red;
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      child: ExpansionTile(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: statusColor),
              ),
              child: Text(
                '${log.statusCode ?? "ERR"}',
                style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                log.method,
                style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                log.path,
                style: const TextStyle(fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${log.requestDurationMs}ms',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Row(
            children: [
              Text(
                DateFormat('HH:mm:ss.SSS').format(log.time),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              if (log.model != null) ...[
                const SizedBox(width: 8),
                const Icon(Icons.psychology, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  log.model!,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (log.targetEndpoint != null) ...[
                  const Text('转发目标:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  SelectableText(log.targetEndpoint!),
                  const SizedBox(height: 12),
                ],
                if (log.error != null) ...[
                  const Text('错误信息:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  const SizedBox(height: 4),
                  SelectableText(log.error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
