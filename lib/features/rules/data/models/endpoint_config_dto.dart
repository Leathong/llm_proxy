import 'package:json_annotation/json_annotation.dart';
import 'package:llm_proxy/features/rules/domain/entities/endpoint_config.dart';

part 'endpoint_config_dto.g.dart';

@JsonSerializable()
class EndpointConfigDTO {
  final String id;
  final String url;
  @JsonKey(name: 'apiKey', defaultValue: '')
  final String apiKey;
  @JsonKey(defaultValue: true)
  final bool active;

  const EndpointConfigDTO({
    required this.id,
    required this.url,
    this.apiKey = '',
    this.active = true,
  });

  factory EndpointConfigDTO.fromJson(Map<String, dynamic> json) =>
      _$EndpointConfigDTOFromJson(json);
  Map<String, dynamic> toJson() => _$EndpointConfigDTOToJson(this);

  EndpointConfig toEntity() => EndpointConfig(
        id: id,
        url: url,
        apiKey: apiKey,
        active: active,
      );

  factory EndpointConfigDTO.fromEntity(EndpointConfig entity) =>
      EndpointConfigDTO(
        id: entity.id,
        url: entity.url,
        apiKey: entity.apiKey,
        active: entity.active,
      );
}
