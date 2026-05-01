import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/features/logs/domain/repositories/log_repository.dart';
import 'package:llm_proxy/features/logs/data/repositories/log_repository_impl.dart';

final logRepositoryProvider = Provider<LogRepository>((ref) {
  return LogRepositoryImpl();
});

/// state 为递增版本号，仅用于通知 UI 刷新；
/// 实际数据由 [logRepositoryProvider] 持有，UI 按索引直接读取。
class LogsNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void refresh() => state++;

  void clear() {
    ref.read(logRepositoryProvider).clearLogs();
    state++;
  }
}

final logsProvider = NotifierProvider<LogsNotifier, int>(
  LogsNotifier.new,
);


