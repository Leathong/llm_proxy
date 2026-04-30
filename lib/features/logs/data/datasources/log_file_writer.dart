import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

/// 代理请求/响应日志写入器。
/// 将每个请求和对应的响应内容写入指定的日志文件。
class LogFileWriter {
  String? _logFilePath;

  /// 更新日志文件路径（空字符串或 null 表示不写入文件）
  void setLogFilePath(String path) {
    _logFilePath = path.isEmpty ? null : path;
  }

  /// 写入一条完整的请求-响应日志
  Future<void> writeLog({
    required DateTime time,
    required String method,
    required String path,
    required String? requestBody,
    required int statusCode,
    String? responseBody,
    String? error,
    String? targetEndpoint,
    String? model,
    int? requestDurationMs,
  }) async {
    if (_logFilePath == null) return;

    try {
      final file = File(_logFilePath!);
      await file.parent.create(recursive: true);

      final buf = StringBuffer();
      final separator = '${'-' * 20} ${_formatTime(time)} ${'-' * 20}';
      buf.writeln(separator);
      buf.writeln('[REQUEST] $method $path');

      if (model != null) buf.writeln('[Model] $model');
      if (targetEndpoint != null) buf.writeln('[Forward To] $targetEndpoint');
      if (requestDurationMs != null) buf.writeln('[Duration] ${requestDurationMs}ms');
      buf.writeln('[Status] $statusCode');

      if (requestBody != null && requestBody.isNotEmpty) {
        buf.writeln('[Request Body]');
        buf.writeln(_formatJson(requestBody));
      }

      if (responseBody != null && responseBody.isNotEmpty) {
        buf.writeln('[Response Body]');
        buf.writeln(_formatJson(responseBody));
      }

      if (error != null && error.isNotEmpty) {
        buf.writeln('[Error] $error');
      }

      buf.writeln();
      await file.writeAsString(buf.toString(), mode: FileMode.append);
    } catch (e) {
      developer.log('[LogFileWriter] 写入日志文件失败: $e');
    }
  }

  String _formatTime(DateTime dt) {
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
        '${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  String _formatJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return raw;
    }
  }
}
