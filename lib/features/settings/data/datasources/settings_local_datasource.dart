import 'package:shared_preferences/shared_preferences.dart';

class SettingsLocalDataSource {
  final SharedPreferences _prefs;

  SettingsLocalDataSource(this._prefs);

  int loadProxyPort() => _prefs.getInt('proxyPort') ?? 8080;
  bool loadEnableSystemProxy() => _prefs.getBool('enableSystemProxy') ?? false;
  String? loadCertPath() => _prefs.getString('certPath');
  String? loadKeyPath() => _prefs.getString('keyPath');
  List<String> loadCertDomains() {
    final saved = _prefs.getStringList('certDomains');
    if (saved != null && saved.isNotEmpty) return saved;
    return const ['localhost', 'api.openai.com'];
  }

  String? loadLogFileDir() {
    final path = _prefs.getString('logFileDir');
    return (path != null && path.isNotEmpty) ? path : null;
  }

  bool loadSplitByEndpoint() => _prefs.getBool('splitByEndpoint') ?? true;

  Future<void> saveProxyPort(int port) => _prefs.setInt('proxyPort', port);
  Future<void> saveEnableSystemProxy(bool enable) => _prefs.setBool('enableSystemProxy', enable);
  Future<void> saveCertPaths(String certPath, String keyPath) async {
    await _prefs.setString('certPath', certPath);
    await _prefs.setString('keyPath', keyPath);
  }

  Future<void> saveCertDomains(List<String> domains) =>
      _prefs.setStringList('certDomains', domains);
  Future<void> saveLogFileDir(String path) => _prefs.setString('logFileDir', path);
  Future<void> saveSplitByEndpoint(bool split) => _prefs.setBool('splitByEndpoint', split);
}
