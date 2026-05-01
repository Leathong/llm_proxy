import 'dart:developer' as developer;

import 'package:llm_proxy/features/logs/domain/entities/log_entry.dart';

/// 代理服务器日志辅助类，统一管理日志条目的创建、更新和文本日志输出
class ProxyLogger {
  int _logIdCounter = 0;

  final void Function(String message)? onLog;
  final void Function(LogEntry logEntry)? onLogEntry;
  final void Function(LogEntry logEntry)? onLogEntryUpdate;

  ProxyLogger({this.onLog, this.onLogEntry, this.onLogEntryUpdate});

  String nextLogId() => 'log_${++_logIdCounter}';

  /// 输出文本日志
  void log(String message) {
    if (onLog != null) {
      onLog!(message);
    } else {
      developer.log(message, name: 'ProxyServer');
    }
  }

  /// 发射一条 pending 状态的日志条目（请求刚进入时）
  void emitPending({
    required String id,
    required DateTime time,
    required String method,
    required String path,
  }) {
    onLogEntry?.call(
      LogEntry(
        id: id,
        time: time,
        method: method,
        path: path,
        status: LogStatus.pending,
      ),
    );
  }

  /// 更新已有日志条目的状态
  void update({
    required String id,
    required DateTime time,
    required String method,
    required String path,
    String? model,
    String? targetEndpoint,
    int? statusCode,
    String? error,
    LogStatus status = LogStatus.completed,
  }) {
    onLogEntryUpdate?.call(
      LogEntry(
        id: id,
        time: time,
        method: method,
        path: path,
        model: model,
        targetEndpoint: targetEndpoint,
        statusCode: statusCode,
        error: error,
        requestDurationMs: DateTime.now().difference(time).inMilliseconds,
        status: status,
      ),
    );
  }

  /// 发射一条已完成的日志条目（一次性请求，如 /v1/models）
  void emit({
    required DateTime time,
    required String method,
    required String path,
    String? model,
    String? targetEndpoint,
    int? statusCode,
    String? error,
  }) {
    onLogEntry?.call(
      LogEntry(
        id: nextLogId(),
        time: time,
        method: method,
        path: path,
        model: model,
        targetEndpoint: targetEndpoint,
        statusCode: statusCode,
        error: error,
        requestDurationMs: DateTime.now().difference(time).inMilliseconds,
        status: LogStatus.completed,
      ),
    );
  }
}
