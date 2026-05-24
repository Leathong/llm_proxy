import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/features/proxy/presentation/providers/proxy_providers.dart';

/// state 为递增版本号，仅用于通知 UI 刷新。
class LogsNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void refresh() => state++;

  Future<void> clear() async {
    await ref.read(logRepositoryProvider).clearLogs();
    state++;
  }
}

final logsProvider = NotifierProvider<LogsNotifier, int>(
  LogsNotifier.new,
);
