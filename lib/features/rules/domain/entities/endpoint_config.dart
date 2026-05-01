class EndpointConfig {
  final String id;
  final String url;
  final String apiKey;
  final bool active;

  const EndpointConfig({
    required this.id,
    required this.url,
    this.apiKey = '',
    this.active = true,
  });

  EndpointConfig copyWith({
    String? id,
    String? url,
    String? apiKey,
    bool? active,
  }) {
    return EndpointConfig(
      id: id ?? this.id,
      url: url ?? this.url,
      apiKey: apiKey ?? this.apiKey,
      active: active ?? this.active,
    );
  }
}
