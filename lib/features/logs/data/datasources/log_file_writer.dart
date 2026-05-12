import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

/// 代理请求/响应日志写入器。
/// 按模型名 + endpoint ID 分文件写入日志目录。
class LogFileWriter {
  String? _logFileDir;

  /// 更新日志目录路径（空字符串或 null 表示不写入文件）
  void setLogFileDir(String dir) {
    _logFileDir = dir.isEmpty ? null : dir;
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
    int? firstByteMs,
    int? endpointId,
  }) async {
    if (_logFileDir == null) return;

    try {
      final filePath = _buildFilePath(model, endpointId);
      final file = File(filePath);
      await file.parent.create(recursive: true);

      final buf = StringBuffer();
      final separator = '${'-' * 20} ${_formatTime(time)} ${'-' * 20}';
      buf.writeln(separator);
      buf.writeln('[REQUEST] $method $path');

      if (model != null) buf.writeln('[Model] $model');
      if (targetEndpoint != null) buf.writeln('[Forward To] $targetEndpoint');
      if (requestDurationMs != null) buf.writeln('[Duration] ${requestDurationMs}ms');
      if (firstByteMs != null) buf.writeln('[First Byte] ${firstByteMs}ms');
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

  /// 根据 model 和 endpointId 生成文件路径
  String _buildFilePath(String? model, int? endpointId) {
    final safeModel = _safeFileName(model ?? '_models');
    final epId = endpointId?.toString() ?? '_unknown';
    return '$_logFileDir${safeModel}_$epId.log';
  }

  /// 文件名安全处理：替换非法字符，截断过长名称
  String _safeFileName(String name) {
    var safe = name.replaceAll(RegExp(r'[\/\\:*?"<>|]'), '_');
    if (safe.length > 100) safe = safe.substring(0, 100);
    return safe;
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
