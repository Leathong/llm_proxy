class Rule {
  final int id;
  final String name;
  final String groupName;
  final String customModelId;
  final String targetModelId;
  final int? providerModelId;
  final String providerModelName;
  final bool active;
  final String thinkingMode;
  final String reasoningEffort;
  final bool convertThinkingToContent;
  final int? systemPromptId;

  const Rule({
    required this.id,
    required this.name,
    this.groupName = '',
    required this.customModelId,
    required this.targetModelId,
    this.providerModelId,
    this.providerModelName = '',
    this.active = true,
    this.thinkingMode = '',
    this.reasoningEffort = '',
    this.convertThinkingToContent = false,
    this.systemPromptId,
  });

  Rule copyWith({
    int? id,
    String? name,
    String? groupName,
    String? customModelId,
    String? targetModelId,
    int? providerModelId,
    String? providerModelName,
    bool? active,
    String? thinkingMode,
    String? reasoningEffort,
    bool? convertThinkingToContent,
    int? systemPromptId,
  }) {
    return Rule(
      id: id ?? this.id,
      name: name ?? this.name,
      groupName: groupName ?? this.groupName,
      customModelId: customModelId ?? this.customModelId,
      targetModelId: targetModelId ?? this.targetModelId,
      providerModelId: providerModelId ?? this.providerModelId,
      providerModelName: providerModelName ?? this.providerModelName,
      active: active ?? this.active,
      thinkingMode: thinkingMode ?? this.thinkingMode,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      convertThinkingToContent: convertThinkingToContent ?? this.convertThinkingToContent,
      systemPromptId: systemPromptId ?? this.systemPromptId,
    );
  }
}
