import 'package:llm_proxy/features/rules/domain/entities/endpoint_config.dart';

class Rule {
  final String id;
  final String name;
  // 多 endpoint 配置，支持负载均衡
  final List<EndpointConfig> endpoints;
  final String customModelId;
  final String targetModelId;
  final bool active;
  final String thinkingMode;
  final String reasoningEffort;

  const Rule({
    required this.id,
    required this.name,
    this.endpoints = const [],
    required this.customModelId,
    required this.targetModelId,
    this.active = true,
    this.thinkingMode = '',
    this.reasoningEffort = '',
  });

  /// 获取所有启用的 endpoint
  List<EndpointConfig> get activeEndpoints =>
      endpoints.where((e) => e.active).toList();

  Rule copyWith({
    String? id,
    String? name,
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
      endpoints: endpoints ?? this.endpoints,
      customModelId: customModelId ?? this.customModelId,
      targetModelId: targetModelId ?? this.targetModelId,
      active: active ?? this.active,
      thinkingMode: thinkingMode ?? this.thinkingMode,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
    );
  }
}
