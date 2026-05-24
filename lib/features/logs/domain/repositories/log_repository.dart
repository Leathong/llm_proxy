import 'package:llm_proxy/features/logs/domain/entities/log_entry.dart';

abstract class LogRepository {
  Stream<void> get changeStream;

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
