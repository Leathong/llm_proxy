import 'package:llm_proxy/features/rules/domain/entities/endpoint_config.dart';

class Rule {
  final int id;
  final String name;
  final String groupName;
  final List<EndpointConfig> endpoints;
  final String customModelId;
  final String targetModelId;
  final bool active;
  final String thinkingMode;
  final String reasoningEffort;

  const Rule({
    required this.id,
    required this.name,
    this.groupName = '',
    this.endpoints = const [],
    required this.customModelId,
    required this.targetModelId,
    this.active = true,
    this.thinkingMode = '',
    this.reasoningEffort = '',
  });

  List<EndpointConfig> get activeEndpoints =>
      endpoints.where((e) => e.active).toList();

  Rule copyWith({
    int? id,
    String? name,
    String? groupName,
    List<EndpointConfig>? endpoints,
    String? customModelId,
    String? targetModelId,
    bool? active,
    String? thinkingMode,
    String? reasoningEffort,
  }) {
    return Rule(
      id: id ?? this.id,
      name: name ?? this.name,
      groupName: groupName ?? this.groupName,
      endpoints: endpoints ?? this.endpoints,
      customModelId: customModelId ?? this.customModelId,
      targetModelId: targetModelId ?? this.targetModelId,
      active: active ?? this.active,
      thinkingMode: thinkingMode ?? this.thinkingMode,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
    );
  }
}
