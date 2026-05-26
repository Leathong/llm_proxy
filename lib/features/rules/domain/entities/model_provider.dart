class ModelProvider {
  final int id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final String format;

  const ModelProvider({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.apiKey = '',
    this.format = 'openai',
  });

  ModelProvider copyWith({
    int? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    String? format,
  }) {
    return ModelProvider(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      format: format ?? this.format,
    );
  }
}
