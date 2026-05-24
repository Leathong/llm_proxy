class AppSettings {
  final int proxyPort;
  final bool enableSystemProxy;
  final String? certPath;
  final String? keyPath;
  final List<String> certDomains;
  final String logFileDir;

  const AppSettings({
    this.proxyPort = 8080,
    this.enableSystemProxy = false,
    this.certPath,
    this.keyPath,
    this.certDomains = const ['localhost', 'api.openai.com'],
    this.logFileDir = '',
  });

  AppSettings copyWith({
    int? proxyPort,
    bool? enableSystemProxy,
    String? certPath,
    String? keyPath,
    List<String>? certDomains,
    String? logFileDir,
  }) {
    return AppSettings(
      proxyPort: proxyPort ?? this.proxyPort,
      enableSystemProxy: enableSystemProxy ?? this.enableSystemProxy,
      certPath: certPath ?? this.certPath,
      keyPath: keyPath ?? this.keyPath,
      certDomains: certDomains ?? this.certDomains,
      logFileDir: logFileDir ?? this.logFileDir,
    );
  }
}
