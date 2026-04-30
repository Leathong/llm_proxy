
class ProxyLog {
  final DateTime time;
  final String method;
  final String path;
  final String? model;
  final String? targetEndpoint;
  final int? statusCode;
  final String? error;
  final int requestDurationMs;

  ProxyLog({
    required this.time,
    required this.method,
    required this.path,
    this.model,
    this.targetEndpoint,
    this.statusCode,
    this.error,
    this.requestDurationMs = 0,
  });
}
