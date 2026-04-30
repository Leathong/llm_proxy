import 'package:llm_proxy/features/logs/domain/entities/log_entry.dart';
import 'package:llm_proxy/features/logs/domain/repositories/log_repository.dart';
import 'package:llm_proxy/features/logs/data/datasources/ring_buffer.dart';

class LogRepositoryImpl implements LogRepository {
  static const int maxLogs = 500;
  final RingBuffer<LogEntry> _ring = RingBuffer<LogEntry>(maxLogs);

  @override
  int get logCount => _ring.length;

  @override
  LogEntry getLog(int index) => _ring.get(index);

  @override
  void addLog(LogEntry log) {
    _ring.add(log);
  }

  @override
  void updateLog(LogEntry updatedLog, {bool silent = false}) {
    _ring.updateWhere(
      (entry) => entry.id == updatedLog.id,
      (_) => updatedLog,
    );
  }

  @override
  void clearLogs() {
    _ring.clear();
  }
}
