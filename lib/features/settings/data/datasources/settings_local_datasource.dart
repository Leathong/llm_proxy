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

  String? loadLogFilePath() {
    final path = _prefs.getString('logFilePath');
    return (path != null && path.isNotEmpty) ? path : null;
  }

  Future<void> saveProxyPort(int port) => _prefs.setInt('proxyPort', port);
  Future<void> saveEnableSystemProxy(bool enable) => _prefs.setBool('enableSystemProxy', enable);
  Future<void> saveCertPaths(String certPath, String keyPath) async {
    await _prefs.setString('certPath', certPath);
    await _prefs.setString('keyPath', keyPath);
  }

  Future<void> saveCertDomains(List<String> domains) =>
      _prefs.setStringList('certDomains', domains);
  Future<void> saveLogFilePath(String path) => _prefs.setString('logFilePath', path);
}
