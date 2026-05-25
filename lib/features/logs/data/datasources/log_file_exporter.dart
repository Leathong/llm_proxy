import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:llm_proxy/features/logs/domain/entities/log_entry.dart';

/// 日志文件导出器。
/// 将日志条目追加写入到指定的单个文件。
class LogFileExporter {
  /// 将多条日志条目写入指定文件（追加模式）
  static Future<void> exportToFile({
    required String filePath,
    required List<LogEntry> entries,
  }) async {
    if (entries.isEmpty) return;

    final file = File(filePath);
    await file.parent.create(recursive: true);

    final buf = StringBuffer();
    for (final entry in entries) {
      final separator = '${'-' * 20} ${_formatTime(entry.time)} ${'-' * 20}';
      buf.writeln(separator);
      buf.writeln('[REQUEST] ${entry.method} ${entry.path}');

      if (entry.model != null) buf.writeln('[Model] ${entry.model}');
      if (entry.targetEndpoint != null) buf.writeln('[Forward To] ${entry.targetEndpoint}');
      buf.writeln('[Duration] ${entry.requestDurationMs}ms');
      if (entry.firstByteDurationMs != null) buf.writeln('[First Byte] ${entry.firstByteDurationMs}ms');
      buf.writeln('[Status] ${entry.statusCode ?? 0}');

      if (entry.requestBody != null && entry.requestBody!.isNotEmpty) {
        buf.writeln('[Request Body]');
        buf.writeln(_formatJson(entry.requestBody!));
      }

      if (entry.responseBody != null && entry.responseBody!.isNotEmpty) {
        buf.writeln('[Response Body]');
        buf.writeln(_formatJson(entry.responseBody!));
      }

      if (entry.error != null && entry.error!.isNotEmpty) {
        buf.writeln('[Error] ${entry.error}');
      }

      buf.writeln();
    }

    try {
      await file.writeAsString(buf.toString(), mode: FileMode.append);
    } catch (e) {
      developer.log('[LogFileExporter] 写入日志文件失败: $e');
    }
  }

  static String _formatTime(DateTime dt) {
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
        '${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}.'
        '${dt.millisecond.toString().padLeft(3, '0')}';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  static String _formatJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return raw;
    }
  }
}
