import 'dart:convert';

class ProxyRule {
  String id;
  String name;
  String endpoint;
  String apiKey;
  String customModelId;
  String targetModelId;
  bool active;
  // 思考模式: enabled / disabled / 空字符串表示不注入
  String thinkingMode;
  // 思考强度: high / max / 空字符串表示不注入
  String reasoningEffort;

  ProxyRule({
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

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'endpoint': endpoint,
      'apiKey': apiKey,
      'custom_model_id': customModelId,
      'target_model_id': targetModelId,
      'active': active,
      'thinking_mode': thinkingMode,
      'reasoning_effort': reasoningEffort,
    };
  }

  factory ProxyRule.fromMap(Map<String, dynamic> map) {
    return ProxyRule(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      endpoint: map['endpoint'] ?? '',
      apiKey: map['apiKey'] ?? '',
      customModelId: map['custom_model_id'] ?? '',
      targetModelId: map['target_model_id'] ?? '',
      active: map['active'] ?? true,
      thinkingMode: map['thinking_mode'] ?? '',
      reasoningEffort: map['reasoning_effort'] ?? '',
    );
  }

  String toJson() => json.encode(toMap());

  factory ProxyRule.fromJson(String source) => ProxyRule.fromMap(json.decode(source));

  ProxyRule copyWith({
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
    return ProxyRule(
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
