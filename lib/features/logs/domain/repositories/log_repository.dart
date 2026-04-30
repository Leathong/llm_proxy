import 'package:llm_proxy/features/logs/domain/entities/log_entry.dart';

abstract class LogRepository {
  int get logCount;
  LogEntry getLog(int index);
  void addLog(LogEntry log);
  void updateLog(LogEntry updatedLog, {bool silent = false});
  void clearLogs();
}
