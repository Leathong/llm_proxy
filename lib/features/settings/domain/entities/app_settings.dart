class AppSettings {
  final int proxyPort;
  final bool enableSystemProxy;
  final String? certPath;
  final String? keyPath;
  final List<String> certDomains;
  final String logFileDir;
  final bool splitByEndpoint;

  const AppSettings({
    this.proxyPort = 8080,
    this.enableSystemProxy = false,
    this.certPath,
    this.keyPath,
    this.certDomains = const ['localhost', 'api.openai.com'],
    this.logFileDir = '',
    this.splitByEndpoint = true,
  });

  AppSettings copyWith({
    int? proxyPort,
    bool? enableSystemProxy,
    String? certPath,
    String? keyPath,
    List<String>? certDomains,
    String? logFileDir,
    bool? splitByEndpoint,
  }) {
    return AppSettings(
      proxyPort: proxyPort ?? this.proxyPort,
      enableSystemProxy: enableSystemProxy ?? this.enableSystemProxy,
      certPath: certPath ?? this.certPath,
      keyPath: keyPath ?? this.keyPath,
      certDomains: certDomains ?? this.certDomains,
      logFileDir: logFileDir ?? this.logFileDir,
      splitByEndpoint: splitByEndpoint ?? this.splitByEndpoint,
    );
  }
}
