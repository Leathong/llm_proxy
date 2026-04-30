class Rule {
  final String id;
  final String name;
  final String endpoint;
  final String apiKey;
  final String customModelId;
  final String targetModelId;
  final bool active;
  final String thinkingMode;
  final String reasoningEffort;

  const Rule({
    required this.id,
    required this.name,
    required this.endpoint,
    required this.apiKey,
    required this.customModelId,
    required this.targetModelId,
    this.active = true,
    this.thinkingMode = '',
    this.reasoningEffort = '',
  });

  Rule copyWith({
    String? id,
    String? name,
    String? endpoint,
    String? apiKey,
    String? customModelId,
    String? targetModelId,
    bool? active,
    String? thinkingMode,
    String? reasoningEffort,
  }) {
    return Rule(
      id: id ?? this.id,
      name: name ?? this.name,
      endpoint: endpoint ?? this.endpoint,
      apiKey: apiKey ?? this.apiKey,
      customModelId: customModelId ?? this.customModelId,
      targetModelId: targetModelId ?? this.targetModelId,
      active: active ?? this.active,
      thinkingMode: thinkingMode ?? this.thinkingMode,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
    );
  }
}
