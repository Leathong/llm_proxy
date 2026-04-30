import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_entry.dart';
import 'package:llm_proxy/features/logs/domain/repositories/log_repository.dart';
import 'package:llm_proxy/features/logs/data/repositories/log_repository_impl.dart';

final logRepositoryProvider = Provider<LogRepository>((ref) {
  return LogRepositoryImpl();
});

class LogsNotifier extends Notifier<List<LogEntry>> {
  @override
  List<LogEntry> build() {
    final repo = ref.watch(logRepositoryProvider);
    final count = repo.logCount;
    return List.generate(count, (i) => repo.getLog(i));
  }

  void clear() {
    ref.read(logRepositoryProvider).clearLogs();
    ref.invalidateSelf();
  }
}

final logsProvider = NotifierProvider<LogsNotifier, List<LogEntry>>(
  LogsNotifier.new,
);


