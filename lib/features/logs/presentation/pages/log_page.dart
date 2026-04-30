import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_entry.dart';
import 'package:llm_proxy/features/logs/presentation/providers/logs_providers.dart';

class LogPage extends ConsumerWidget {
  const LogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(logsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('日志查看'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空日志',
            onPressed: () => ref.read(logsProvider.notifier).clear(),
          ),
        ],
      ),
      body: logs.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.list_alt, size: 80, color: Colors.grey),
                  SizedBox(height: 20),
                  Text('暂无抓包日志', style: TextStyle(fontSize: 18, color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              itemCount: logs.length,
              itemBuilder: (context, index) => _LogItem(log: logs[index]),
            ),
    );
  }
}

class _LogItem extends StatelessWidget {
  final LogEntry log;
  const _LogItem({required this.log});

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    String statusText;

    if (log.status == LogStatus.pending) {
      statusColor = Colors.orange;
      statusText = '...';
    } else if (log.statusCode != null) {
      statusText = '${log.statusCode}';
      if (log.statusCode! >= 200 && log.statusCode! < 300) {
        statusColor = Colors.green;
      } else if (log.statusCode! >= 400 && log.statusCode! < 500) {
        statusColor = Colors.orange;
      } else if (log.statusCode! >= 500) {
        statusColor = Colors.red;
      } else {
        statusColor = Colors.grey;
      }
    } else {
      statusColor = Colors.red;
      statusText = 'ERR';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      child: ExpansionTile(
        title: Row(
          children: [
            if (log.status == LogStatus.pending)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.orange, width: 1),
                ),
                child: const SizedBox(
                  width: 12, height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.orange),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: statusColor, width: 1),
                ),
                child: Text(statusText,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.w600, fontSize: 11)),
              ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(log.method,
                  style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w600, fontSize: 11)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(log.path,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis),
            ),
            if (log.status == LogStatus.pending)
              _PendingDuration(startTime: log.time)
            else
              Text('${log.requestDurationMs}ms',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Row(
            children: [
              Text(DateFormat('HH:mm:ss.SSS').format(log.time),
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
              if (log.model != null) ...[
                const SizedBox(width: 8),
                const Icon(Icons.psychology, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(log.model!,
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
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

class _PendingDuration extends StatefulWidget {
  final DateTime startTime;
  const _PendingDuration({required this.startTime});

  @override
  State<_PendingDuration> createState() => _PendingDurationState();
}

class _PendingDurationState extends State<_PendingDuration> {
  late Timer _timer;
  late int _elapsedMs;

  @override
  void initState() {
    super.initState();
    _elapsedMs = DateTime.now().difference(widget.startTime).inMilliseconds;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      setState(() {
        _elapsedMs = DateTime.now().difference(widget.startTime).inMilliseconds;
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text('$_elapsedMs ms',
        style: const TextStyle(color: Colors.orange, fontSize: 12));
  }
}
