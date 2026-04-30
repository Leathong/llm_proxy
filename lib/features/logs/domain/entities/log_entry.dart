enum LogStatus {
  pending,
  completed,
  error,
}

class LogEntry {
  final String id;
  final DateTime time;
  final String method;
  final String path;
  final String? model;
  final String? targetEndpoint;
  final int? statusCode;
  final String? error;
  final int requestDurationMs;
  final LogStatus status;

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
    this.status = LogStatus.completed,
  });

  LogEntry copyWith({
    String? id,
    DateTime? time,
    String? method,
    String? path,
    String? model,
    String? targetEndpoint,
    int? statusCode,
    String? error,
    int? requestDurationMs,
    LogStatus? status,
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
      status: status ?? this.status,
    );
  }
}
