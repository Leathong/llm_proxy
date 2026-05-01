import 'package:json_annotation/json_annotation.dart';
import 'package:llm_proxy/features/rules/domain/entities/endpoint_config.dart';
import 'package:llm_proxy/features/rules/domain/entities/rule.dart';
import 'package:llm_proxy/features/rules/data/models/endpoint_config_dto.dart';

part 'rule_dto.g.dart';

@JsonSerializable()
class RuleDTO {
  final String id;
  final String name;
  // 新字段：多 endpoint 列表
  @JsonKey(defaultValue: [])
  final List<EndpointConfigDTO> endpoints;
  // 保留旧字段用于数据迁移
  @JsonKey(defaultValue: '')
  final String endpoint;
  @JsonKey(name: 'apiKey', defaultValue: '')
  final String apiKey;
  @JsonKey(defaultValue: '')
  final String customModelId;
  @JsonKey(defaultValue: '')
  final String targetModelId;
  final bool active;
  final String thinkingMode;
  final String reasoningEffort;

  const RuleDTO({
    required this.id,
    required this.name,
    this.endpoints = const [],
    this.endpoint = '',
    this.apiKey = '',
    required this.customModelId,
    required this.targetModelId,
    this.active = true,
    this.thinkingMode = '',
    this.reasoningEffort = '',
  });

  factory RuleDTO.fromJson(Map<String, dynamic> json) => _$RuleDTOFromJson(json);
  Map<String, dynamic> toJson() => _$RuleDTOToJson(this);

  /// 转换为实体，兼容旧数据：若 endpoints 为空但 endpoint 有值，自动迁移
  Rule toEntity() {
    List<EndpointConfig> endpointList;
    if (endpoints.isNotEmpty) {
      endpointList = endpoints.map((e) => e.toEntity()).toList();
    } else if (endpoint.isNotEmpty) {
      endpointList = [
        EndpointConfig(
          id: '${id}_ep_0',
          url: endpoint,
          apiKey: apiKey,
          active: true,
        ),
      ];
    } else {
      endpointList = [];
    }

    return Rule(
      id: id,
      name: name,
      endpoints: endpointList,
      customModelId: customModelId,
      targetModelId: targetModelId,
      active: active,
      thinkingMode: thinkingMode,
      reasoningEffort: reasoningEffort,
    );
  }

  factory RuleDTO.fromEntity(Rule entity) => RuleDTO(
        id: entity.id,
        name: entity.name,
        endpoints:
            entity.endpoints.map((e) => EndpointConfigDTO.fromEntity(e)).toList(),
        customModelId: entity.customModelId,
        targetModelId: entity.targetModelId,
        active: entity.active,
        thinkingMode: entity.thinkingMode,
        reasoningEffort: entity.reasoningEffort,
      );
}
