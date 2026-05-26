/// Provider 格式枚举，决定请求/响应的解析方式
enum ProviderFormat {
  openai,
  anthropic;

  static ProviderFormat? fromPath(String path) {
    if (path == '/v1/chat/completions') return ProviderFormat.openai;
    if (path == '/v1/messages') return ProviderFormat.anthropic;
    return null;
  }

  String get path {
    switch (this) {
      case ProviderFormat.openai:
        return '/v1/chat/completions';
      case ProviderFormat.anthropic:
        return '/v1/messages';
    }
  }

  static ProviderFormat? parse(String format) {
    switch (format.toLowerCase()) {
      case 'openai':
        return ProviderFormat.openai;
      case 'anthropic':
        return ProviderFormat.anthropic;
      default:
        return null;
    }
  }
}
