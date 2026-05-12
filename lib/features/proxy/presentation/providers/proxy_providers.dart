import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/features/proxy/data/datasources/proxy_server_datasource.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_entry.dart';
import 'package:llm_proxy/features/logs/presentation/providers/logs_providers.dart';
import 'package:llm_proxy/features/rules/presentation/providers/rules_providers.dart';
import 'package:llm_proxy/features/settings/presentation/providers/settings_providers.dart';

/// ProxyServer 数据源单例
final proxyServerDataSourceProvider = Provider<ProxyServerDataSource>((ref) {
  final logRepo = ref.read(logRepositoryProvider);
  final logsNotifier = ref.read(logsProvider.notifier);
  return ProxyServerDataSource(
    getRules: () => ref.read(ruleRepositoryProvider).getRules(),
    onLog: (msg) => debugPrint('[ProxyServer] $msg'),
    onLogEntry: (log) {
      logRepo.addLog(log);
      logsNotifier.refresh();
    },
    onLogEntryUpdate: (log) {
      final silent = log.status == LogStatus.pending;
      logRepo.updateLog(log, silent: silent);
      // silent 模式（pending 中间态）不刷新 UI，减少不必要的重绘
      if (!silent) {
        logsNotifier.refresh();
      }
    },
  );
});

/// 代理服务器运行状态
class ProxyState {
  final bool isRunning;
  final bool isLoading;
  final String? error;

  const ProxyState({
    this.isRunning = false,
    this.isLoading = false,
    this.error,
  });

  ProxyState copyWith({bool? isRunning, bool? isLoading, String? error}) {
    return ProxyState(
      isRunning: isRunning ?? this.isRunning,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class ProxyNotifier extends Notifier<ProxyState> {
  @override
  ProxyState build() => const ProxyState();

  Future<void> toggle() async {
    final dataSource = ref.read(proxyServerDataSourceProvider);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final settings = settingsRepo.getSettings();

    if (state.isRunning) {
      await dataSource.stop();
      state = state.copyWith(isRunning: false);
    } else {
      state = state.copyWith(isLoading: true, error: null);
      try {
        await dataSource.start(
          port: settings.proxyPort,
          certPath: settings.certPath,
          keyPath: settings.keyPath,
        );
        dataSource.setLogFileDir(settings.logFileDir);
        state = state.copyWith(isRunning: true, isLoading: false);
      } catch (e) {
        state = state.copyWith(isRunning: false, isLoading: false, error: e.toString());
      }
    }
  }
}

final proxyProvider = NotifierProvider<ProxyNotifier, ProxyState>(
  ProxyNotifier.new,
);
