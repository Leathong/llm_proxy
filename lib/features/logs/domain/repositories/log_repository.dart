import 'package:llm_proxy/features/logs/domain/entities/log_entry.dart';

/// 日志变更事件，用于增量更新
sealed class LogChangeEvent {
  const LogChangeEvent();
}

/// 新增日志
class LogAddedEvent extends LogChangeEvent {
  final int id;
  const LogAddedEvent(this.id);
}

/// 更新日志
class LogUpdatedEvent extends LogChangeEvent {
  final int id;
  const LogUpdatedEvent(this.id);
}

/// 删除日志（单条或多条）
class LogDeletedEvent extends LogChangeEvent {
  final List<int> ids;
  const LogDeletedEvent(this.ids);
}

/// 清空所有日志
class LogClearedEvent extends LogChangeEvent {
  const LogClearedEvent();
}

abstract class LogRepository {
  Stream<LogChangeEvent> get changeStream;

  Future<int> get logCount;
  Future<LogEntry?> getLog(int id);
  Future<List<LogEntry>> getLogs({
    int? offset,
    int? limit,
    bool desc = true,
    int? cursor,
  });
  Future<List<LogEntry>> searchLogs({
    String? keyword,
    String? modelFilter,
    String? endpointFilter,
    int? offset,
    int? limit,
    bool desc = true,
    int? cursor,
  });
  Future<List<LogEntry>> getRange(int start, int end);

  Future<int> addLog(LogEntry log);
  Future<void> updateLog(LogEntry updatedLog);
  Future<void> clearLogs();
  Future<void> deleteLog(int id);
  Future<void> deleteLogs(List<int> ids);
}
