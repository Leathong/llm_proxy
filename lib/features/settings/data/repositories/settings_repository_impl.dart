import 'package:llm_proxy/features/settings/domain/entities/app_settings.dart';
import 'package:llm_proxy/features/settings/domain/repositories/settings_repository.dart';
import 'package:llm_proxy/features/settings/data/datasources/settings_local_datasource.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  final SettingsLocalDataSource _dataSource;
  AppSettings _cache;

  SettingsRepositoryImpl(this._dataSource)
      : _cache = AppSettings(
          proxyPort: _dataSource.loadProxyPort(),
          enableSystemProxy: _dataSource.loadEnableSystemProxy(),
          certPath: _dataSource.loadCertPath(),
          keyPath: _dataSource.loadKeyPath(),
          certDomains: _dataSource.loadCertDomains(),
          logFilePath: _dataSource.loadLogFilePath() ?? '',
        );

  @override
  AppSettings getSettings() => _cache;

  @override
  Future<void> setProxyPort(int port) async {
    _cache = _cache.copyWith(proxyPort: port);
    await _dataSource.saveProxyPort(port);
  }

  @override
  Future<void> setEnableSystemProxy(bool enable) async {
    _cache = _cache.copyWith(enableSystemProxy: enable);
    await _dataSource.saveEnableSystemProxy(enable);
  }

  @override
  Future<void> setCertPaths(String certPath, String keyPath) async {
    _cache = _cache.copyWith(certPath: certPath, keyPath: keyPath);
    await _dataSource.saveCertPaths(certPath, keyPath);
  }

  @override
  Future<void> setCertDomains(List<String> domains) async {
    _cache = _cache.copyWith(certDomains: domains);
    await _dataSource.saveCertDomains(domains);
  }

  @override
  Future<void> setLogFilePath(String path) async {
    _cache = _cache.copyWith(logFilePath: path);
    await _dataSource.saveLogFilePath(path);
  }
}
