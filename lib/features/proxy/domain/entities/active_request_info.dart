import 'dart:io';

class ActiveRequestInfo {
  final int logId;
  final String model;
  final String path;
  final DateTime startTime;
  final String method;
  final String? targetEndpoint;
  final HttpRequest clientRequest;

  ActiveRequestInfo({
    required this.logId,
    required this.model,
    required this.path,
    required this.startTime,
    required this.method,
    this.targetEndpoint,
    required this.clientRequest,
  });

  Duration get elapsed => DateTime.now().difference(startTime);
}
