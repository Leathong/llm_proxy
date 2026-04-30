
/// 日志请求状态
enum LogStatus {
  pending,    // 请求进行中
  completed,  // 请求已完成
  error,      // 请求出错
}

class ProxyLog {
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

  ProxyLog({
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

  /// 创建副本并覆盖指定字段
  ProxyLog copyWith({
    int? statusCode,
    String? error,
    int? requestDurationMs,
    LogStatus? status,
    String? model,
    String? targetEndpoint,
  }) {
    return ProxyLog(
      id: id,
      time: time,
      method: method,
      path: path,
      model: model ?? this.model,
      targetEndpoint: targetEndpoint ?? this.targetEndpoint,
      statusCode: statusCode ?? this.statusCode,
      error: error ?? this.error,
      requestDurationMs: requestDurationMs ?? this.requestDurationMs,
      status: status ?? this.status,
    );
  }
}
