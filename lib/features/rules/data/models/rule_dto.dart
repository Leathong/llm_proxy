import 'package:json_annotation/json_annotation.dart';
import 'package:llm_proxy/features/rules/domain/entities/rule.dart';

part 'rule_dto.g.dart';

@JsonSerializable()
class RuleDTO {
  final String id;
  final String name;
  @JsonKey(defaultValue: '')
  final String endpoint;
  @JsonKey(defaultValue: '')
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
    required this.endpoint,
    required this.apiKey,
    required this.customModelId,
    required this.targetModelId,
    this.active = true,
    this.thinkingMode = '',
    this.reasoningEffort = '',
  });

  factory RuleDTO.fromJson(Map<String, dynamic> json) => _$RuleDTOFromJson(json);
  Map<String, dynamic> toJson() => _$RuleDTOToJson(this);

  Rule toEntity() => Rule(
        id: id,
        name: name,
        endpoint: endpoint,
        apiKey: apiKey,
        customModelId: customModelId,
        targetModelId: targetModelId,
        active: active,
        thinkingMode: thinkingMode,
        reasoningEffort: reasoningEffort,
      );

  factory RuleDTO.fromEntity(Rule entity) => RuleDTO(
        id: entity.id,
        name: entity.name,
        endpoint: entity.endpoint,
        apiKey: entity.apiKey,
        customModelId: entity.customModelId,
        targetModelId: entity.targetModelId,
        active: entity.active,
        thinkingMode: entity.thinkingMode,
        reasoningEffort: entity.reasoningEffort,
      );
}
