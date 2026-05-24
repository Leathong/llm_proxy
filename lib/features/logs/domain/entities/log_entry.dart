import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';

enum LogStatus {
  pending,
  completed,
  error,
}

int logStatusToInt(LogStatus s) => switch (s) {
      LogStatus.pending => 0,
      LogStatus.completed => 1,
      LogStatus.error => 2,
    };

LogStatus logStatusFromInt(int v) => switch (v) {
      0 => LogStatus.pending,
      1 => LogStatus.completed,
      _ => LogStatus.error,
    };

class LogEntry {
  final int id;
  final DateTime time;
  final String method;
  final String path;
  final String? model;
  final String? targetEndpoint;
  final int? statusCode;
  final String? error;
  final int requestDurationMs;
  final int? firstByteDurationMs;
  final LogStatus status;

  final String? requestBody;
  final String? responseBody;

  final FileLogRequest? parsedRequest;
  final FileLogResponse? parsedResponse;

  const LogEntry({
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
    this.requestBody,
    this.responseBody,
    this.parsedRequest,
    this.parsedResponse,
  });

  double? outputTokensPerSecond({bool subtractFirstByte = false}) {
    final out = parsedResponse?.usage?.outputTokens;
    final dur = requestDurationMs;
    if (out == null || dur <= 0) return null;
    final baseMs = subtractFirstByte && firstByteDurationMs != null
        ? dur - firstByteDurationMs!
        : dur;
    if (baseMs <= 0) return null;
    return out / (baseMs / 1000.0);
  }

  LogEntry copyWith({
    int? id,
    DateTime? time,
    String? method,
    String? path,
    String? model,
    String? targetEndpoint,
    int? statusCode,
    String? error,
    int? requestDurationMs,
    int? firstByteDurationMs,
    LogStatus? status,
    String? requestBody,
    String? responseBody,
    FileLogRequest? parsedRequest,
    FileLogResponse? parsedResponse,
    bool clearParsedRequest = false,
    bool clearParsedResponse = false,
  }) {
    return LogEntry(
      id: id ?? this.id,
      time: time ?? this.time,
      method: method ?? this.method,
      path: path ?? this.path,
      model: model ?? this.model,
      targetEndpoint: targetEndpoint ?? this.targetEndpoint,
      statusCode: statusCode ?? this.statusCode,
      error: error ?? this.error,
      requestDurationMs: requestDurationMs ?? this.requestDurationMs,
      firstByteDurationMs: firstByteDurationMs ?? this.firstByteDurationMs,
      status: status ?? this.status,
      requestBody: requestBody ?? this.requestBody,
      responseBody: responseBody ?? this.responseBody,
      parsedRequest: clearParsedRequest ? null : (parsedRequest ?? this.parsedRequest),
      parsedResponse: clearParsedResponse ? null : (parsedResponse ?? this.parsedResponse),
    );
  }
}
