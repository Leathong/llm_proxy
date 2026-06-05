import 'package:llm_proxy/features/logs/domain/entities/log_entry.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_storage_stats.dart';

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
  /// 获取单条日志，[withBody] 为 true 时同时返回原始 requestBody/responseBody（已解压）
  Future<LogEntry?> getLog(int id, {bool withBody = false});
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

  /// 批量获取带原始 body 的日志（用于导出）
  Future<List<LogEntry>> getLogsWithBody(List<int> ids);

  Future<int> addLog(LogEntry log);
  Future<void> updateLog(LogEntry updatedLog);
  Future<void> clearLogs();
  Future<void> deleteLog(int id);
  Future<void> deleteLogs(List<int> ids);

  Future<LogStorageStats> get storageStats;
}
