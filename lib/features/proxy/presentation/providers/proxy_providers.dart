import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/features/logs/data/datasources/log_file_writer.dart';
import 'package:llm_proxy/features/proxy/data/datasources/proxy_server_datasource.dart';
import 'package:llm_proxy/features/logs/domain/repositories/log_repository.dart';
import 'package:llm_proxy/features/logs/data/repositories/drift_log_repository.dart';
import 'package:llm_proxy/features/proxy/domain/services/request_forwarder.dart';
import 'package:llm_proxy/features/proxy/domain/services/request_transformer.dart';
import 'package:llm_proxy/features/proxy/domain/services/rule_matcher.dart';
import 'package:llm_proxy/features/rules/presentation/providers/rules_providers.dart';
import 'package:llm_proxy/features/settings/presentation/providers/settings_providers.dart';

final logRepositoryProvider = Provider<LogRepository>((ref) {
  final db = ref.read(appDatabaseProvider);
  return DriftLogRepository(db);
});

final ruleMatcherProvider = Provider<RuleMatcher>((ref) {
  return RuleMatcher();
});

final requestTransformerProvider = Provider<RequestTransformer>((ref) {
  return RequestTransformer();
});

final requestForwarderProvider = Provider<RequestForwarder>((ref) {
  return RequestForwarder();
});

final logFileWriterProvider = Provider<LogFileWriter>((ref) {
  return LogFileWriter();
});

final proxyServerDataSourceProvider = Provider<ProxyServerDataSource>((ref) {
  final logRepo = ref.read(logRepositoryProvider);
  final ruleMatcher = ref.read(ruleMatcherProvider);
  final transformer = ref.read(requestTransformerProvider);
  final forwarder = ref.read(requestForwarderProvider);
  final logWriter = ref.read(logFileWriterProvider);
  return ProxyServerDataSource(
    ruleMatcher: ruleMatcher,
    transformer: transformer,
    forwarder: forwarder,
    logWriter: logWriter,
    logRepository: logRepo,
    getRules: () => ref.read(ruleRepositoryProvider).getRules(),
    onLog: (msg) => debugPrint('[ProxyServer] $msg'),
  );
});

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
