import 'package:llm_proxy/features/settings/domain/entities/app_settings.dart';

abstract class SettingsRepository {
  AppSettings getSettings();
  Future<void> setProxyPort(int port);
  Future<void> setEnableSystemProxy(bool enable);
  Future<void> setCertPaths(String certPath, String keyPath);
  Future<void> setCertDomains(List<String> domains);
  Future<void> setLogFileDir(String path);
  Future<void> setSplitByEndpoint(bool split);
}
