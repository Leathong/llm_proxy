import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:llm_proxy/features/settings/domain/entities/app_settings.dart';
import 'package:llm_proxy/features/settings/domain/repositories/settings_repository.dart';
import 'package:llm_proxy/features/settings/data/datasources/settings_local_datasource.dart';
import 'package:llm_proxy/features/settings/data/repositories/settings_repository_impl.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('必须先在 main 中 override sharedPreferencesProvider');
});

final settingsLocalDataSourceProvider = Provider<SettingsLocalDataSource>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SettingsLocalDataSource(prefs);
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final dataSource = ref.watch(settingsLocalDataSourceProvider);
  return SettingsRepositoryImpl(dataSource);
});

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final repo = ref.watch(settingsRepositoryProvider);
    return repo.getSettings();
  }

  Future<void> setProxyPort(int port) async {
    await ref.read(settingsRepositoryProvider).setProxyPort(port);
    ref.invalidateSelf();
  }

  Future<void> setEnableSystemProxy(bool enable) async {
    await ref.read(settingsRepositoryProvider).setEnableSystemProxy(enable);
    ref.invalidateSelf();
  }

  Future<void> setCertPaths(String certPath, String keyPath) async {
    await ref.read(settingsRepositoryProvider).setCertPaths(certPath, keyPath);
    ref.invalidateSelf();
  }

  Future<void> setCertDomains(List<String> domains) async {
    await ref.read(settingsRepositoryProvider).setCertDomains(domains);
    ref.invalidateSelf();
  }

  Future<void> setLogFileDir(String path) async {
    await ref.read(settingsRepositoryProvider).setLogFileDir(path);
    ref.invalidateSelf();
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
