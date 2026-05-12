import 'package:json_annotation/json_annotation.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_entry.dart';

part 'log_entry_dto.g.dart';

LogStatus _logStatusFromJson(String status) {
  switch (status) {
    case 'pending':
      return LogStatus.pending;
    case 'completed':
      return LogStatus.completed;
    case 'error':
      return LogStatus.error;
    default:
      return LogStatus.completed;
  }
}

String _logStatusToJson(LogStatus status) {
  switch (status) {
    case LogStatus.pending:
      return 'pending';
    case LogStatus.completed:
      return 'completed';
    case LogStatus.error:
      return 'error';
  }
}

@JsonSerializable()
class LogEntryDTO {
  final String id;
  final DateTime time;
  final String method;
  final String path;
  final String? model;
  final String? targetEndpoint;
  final int? statusCode;
  final String? error;
  final int requestDurationMs;
  final int? firstByteDurationMs;
  @JsonKey(fromJson: _logStatusFromJson, toJson: _logStatusToJson)
  final LogStatus status;

  const LogEntryDTO({
    required this.id,
    required this.time,
    required this.method,
    required this.path,
    this.model,
    this.targetEndpoint,
    this.statusCode,
    this.error,
    this.requestDurationMs = 0,
    this.firstByteDurationMs,
    this.status = LogStatus.completed,
  });

  factory LogEntryDTO.fromJson(Map<String, dynamic> json) => _$LogEntryDTOFromJson(json);
  Map<String, dynamic> toJson() => _$LogEntryDTOToJson(this);

  LogEntry toEntity() => LogEntry(
        id: id,
        time: time,
        method: method,
        path: path,
        model: model,
        targetEndpoint: targetEndpoint,
        statusCode: statusCode,
        error: error,
        requestDurationMs: requestDurationMs,
        firstByteDurationMs: firstByteDurationMs,
        status: status,
      );

  factory LogEntryDTO.fromEntity(LogEntry entity) => LogEntryDTO(
        id: entity.id,
        time: entity.time,
        method: entity.method,
        path: entity.path,
        model: entity.model,
        targetEndpoint: entity.targetEndpoint,
        statusCode: entity.statusCode,
        error: entity.error,
        requestDurationMs: entity.requestDurationMs,
        firstByteDurationMs: entity.firstByteDurationMs,
        status: entity.status,
      );
}
