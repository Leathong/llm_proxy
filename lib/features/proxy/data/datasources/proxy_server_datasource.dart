import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:llm_proxy/features/logs/data/datasources/log_file_writer.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_entry.dart';
import 'package:llm_proxy/features/rules/domain/entities/endpoint_config.dart';
import 'package:llm_proxy/features/rules/domain/entities/rule.dart';

class ProxyServerDataSource {
  HttpServer? _server;
  bool get isRunning => _server != null;
  int _port = 8080;

  int _logIdCounter = 0;

  // Round-Robin 计数器，key 为 rule.id
  final Map<int, int> _rrCounters = {};

  final Future<List<Rule>> Function() getRules;
  final void Function(String message)? onLog;
  final void Function(LogEntry logEntry)? onLogEntry;
  final void Function(LogEntry logEntry)? onLogEntryUpdate;
  final LogFileWriter _logWriter = LogFileWriter();

  ProxyServerDataSource({
    required this.getRules,
    this.onLog,
    this.onLogEntry,
    this.onLogEntryUpdate,
  });

  String _nextLogId() => 'log_${++_logIdCounter}';

  void setLogFilePath(String path) {
    _logWriter.setLogFilePath(path);
  }

  /// Round-Robin 选择一个活跃的 endpoint
  EndpointConfig _pickEndpoint(Rule rule) {
    final active = rule.activeEndpoints;
    if (active.length == 1) return active.first;
    final counter = _rrCounters[rule.id] ?? 0;
    final picked = active[counter % active.length];
    _rrCounters[rule.id] = counter + 1;
    return picked;
  }

  Future<void> start({int port = 8080, String? certPath, String? keyPath}) async {
    if (isRunning) return;
    _port = port;
    try {
      if (certPath != null && keyPath != null && certPath.isNotEmpty && keyPath.isNotEmpty) {
        final certFile = File(certPath);
        final keyFile = File(keyPath);

        if (await certFile.exists() && await keyFile.exists()) {
          final securityContext = SecurityContext();
          securityContext.useCertificateChain(certPath);
          securityContext.usePrivateKey(keyPath);
          _server = await HttpServer.bindSecure(InternetAddress.anyIPv4, _port, securityContext);
          _log('代理服务器已启动(HTTPS)，监听端口: $_port');
        } else {
          _log('证书文件不存在，降级为 HTTP 启动，监听端口: $_port');
          _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
        }
      } else {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
        _log('代理服务器已启动(HTTP)，监听端口: $_port');
      }
      _server!.listen(
        _handleRequest,
        onError: (error) {
          _log('服务器监听出错: $error');
        },
        onDone: () {
          _log('服务器监听结束');
        },
      );
    } catch (e) {
      _log('代理服务器启动失败: $e');
      rethrow;
    }
  }

  Future<void> stop() async {
    if (!isRunning) return;
    await _server!.close(force: true);
    _server = null;
    _rrCounters.clear();
    _log('代理服务器已停止');
  }

  void _log(String message) {
    if (onLog != null) {
      onLog!(message);
    } else {
      developer.log(message, name: 'ProxyServer');
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      _setCorsHeaders(request.response);
      if (request.method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
        return;
      }

      final path = request.uri.path;
      _log('收到请求: ${request.method} $path');

      if (path.endsWith('/v1/models')) {
        await _handleModelsRequest(request);
      } else if (path == '/v1/chat/completions' || path == '/v1/messages') {
        await _handleChatCompletionsRequest(request, endpoint: path);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('Not Found');
        await request.response.close();
      }
    } catch (e) {
      _log('处理请求出错: $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('Internal Server Error: $e');
        await request.response.close();
      } catch (err) {
        _log('响应关闭异常: $err');
      }
    }
  }

  void _setCorsHeaders(HttpResponse response) {
    response.headers.add('Access-Control-Allow-Origin', '*');
    response.headers.add('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    response.headers.add('Access-Control-Allow-Headers', 'Origin, Content-Type, Accept, Authorization');
  }

  Future<void> _handleModelsRequest(HttpRequest request) async {
    final startTime = DateTime.now();
    final rules = (await getRules()).where((r) => r.active).toList();
    final models = rules.map((r) => {
      'id': r.customModelId,
      'object': 'model',
      'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'owned_by': 'llm-proxy',
    }).toList();

    final responseJson = {
      'object': 'list',
      'data': models,
    };
    final responseStr = jsonEncode(responseJson);

    request.response.headers.contentType = ContentType.json;
    request.response.write(responseStr);
    await request.response.close();
    _log('已返回可用模型列表: ${models.map((m) => m['id']).join(', ')}');
    _emitLog(
      time: startTime,
      method: request.method,
      path: request.uri.path,
      model: models.map((m) => m['id']).join(', '),
      statusCode: 200,
    );
    _logWriter.writeLog(
      time: startTime,
      method: request.method,
      path: request.uri.path,
      requestBody: null,
      statusCode: 200,
      responseBody: responseStr,
      model: models.map((m) => m['id']).join(', '),
    );
  }

  Future<void> _handleChatCompletionsRequest(HttpRequest request, {required String endpoint}) async {
    final startTime = DateTime.now();
    final logId = _nextLogId();
    String? responseBodyStr;

    int? finalStatusCode;
    String? finalError;

    _emitPendingLog(
      id: logId,
      time: startTime,
      method: request.method,
      path: request.uri.path,
    );

    try {
      if (request.method != 'POST') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        _updateLog(
          id: logId, time: startTime, method: request.method,
          path: request.uri.path, statusCode: HttpStatus.methodNotAllowed,
          status: LogStatus.error, error: 'Method not allowed',
        );
        _logWriter.writeLog(
          time: startTime, method: request.method, path: request.uri.path,
          requestBody: null, statusCode: HttpStatus.methodNotAllowed,
          responseBody: null, error: 'Method not allowed',
        );
        return;
      }

      final bodyString = await utf8.decoder.bind(request).join();
      if (bodyString.isEmpty) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('Empty body');
        await request.response.close();
        _updateLog(
          id: logId, time: startTime, method: request.method,
          path: request.uri.path, statusCode: HttpStatus.badRequest,
          status: LogStatus.error, error: 'Empty body',
        );
        _logWriter.writeLog(
          time: startTime, method: request.method, path: request.uri.path,
          requestBody: bodyString, statusCode: HttpStatus.badRequest,
          error: 'Empty body',
        );
        return;
      }

      Map<String, dynamic> bodyJson;
      try {
        bodyJson = jsonDecode(bodyString);
      } catch (e) {
        _log('JSON解析错误: $e');
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('Invalid JSON');
        await request.response.close();
        _updateLog(
          id: logId, time: startTime, method: request.method,
          path: request.uri.path, statusCode: HttpStatus.badRequest,
          status: LogStatus.error, error: 'Invalid JSON',
        );
        _logWriter.writeLog(
          time: startTime, method: request.method, path: request.uri.path,
          requestBody: bodyString, statusCode: HttpStatus.badRequest,
          error: 'Invalid JSON',
        );
        return;
      }

      final requestedModelId = bodyJson['model'] as String?;
      if (requestedModelId == null) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('Missing model parameter');
        await request.response.close();
        _updateLog(
          id: logId, time: startTime, method: request.method,
          path: request.uri.path, statusCode: HttpStatus.badRequest,
          status: LogStatus.error, error: 'Missing model parameter',
        );
        _logWriter.writeLog(
          time: startTime, method: request.method, path: request.uri.path,
          requestBody: bodyString, statusCode: HttpStatus.badRequest,
          error: 'Missing model parameter',
        );
        return;
      }

      _updateLog(
        id: logId, time: startTime, method: request.method,
        path: request.uri.path, model: requestedModelId,
        status: LogStatus.pending,
      );

      final allRules = await getRules();
      Rule? rule;
      for (final r in allRules) {
        if (r.active && r.customModelId == requestedModelId) {
          rule = r;
          break;
        }
      }

      if (rule == null) {
        final errorResp = jsonEncode({
          'error': {
            'message': 'Model not found or not active: $requestedModelId',
            'type': 'invalid_request_error',
          }
        });
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(errorResp);
        await request.response.close();
        _log('未找到匹配的活跃规则，模型: $requestedModelId');
        _updateLog(
          id: logId, time: startTime, method: request.method,
          path: request.uri.path, model: requestedModelId,
          statusCode: HttpStatus.notFound, status: LogStatus.error,
          error: 'Model not found',
        );
        _logWriter.writeLog(
          time: startTime, method: request.method, path: request.uri.path,
          requestBody: bodyString, statusCode: HttpStatus.notFound,
          responseBody: errorResp, error: 'Model not found',
          model: requestedModelId,
        );
        return;
      }

      // 负载均衡：从活跃的 endpoints 中选择
      final activeEps = rule.activeEndpoints;
      if (activeEps.isEmpty) {
        final errorResp = jsonEncode({
          'error': {
            'message': 'No active endpoint for rule: ${rule.name}',
            'type': 'invalid_request_error',
          }
        });
        request.response.statusCode = HttpStatus.serviceUnavailable;
        request.response.write(errorResp);
        await request.response.close();
        _log('规则 ${rule.name} 没有可用的 endpoint');
        _updateLog(
          id: logId, time: startTime, method: request.method,
          path: request.uri.path, model: requestedModelId,
          statusCode: HttpStatus.serviceUnavailable, status: LogStatus.error,
          error: 'No active endpoint',
        );
        _logWriter.writeLog(
          time: startTime, method: request.method, path: request.uri.path,
          requestBody: bodyString, statusCode: HttpStatus.serviceUnavailable,
          responseBody: errorResp, error: 'No active endpoint',
          model: requestedModelId,
        );
        return;
      }

      final selectedEndpoint = _pickEndpoint(rule);
      _log('匹配到规则: ${rule.name}, 负载均衡选中 endpoint: ${selectedEndpoint.url}');

      bodyJson['model'] = rule.targetModelId;

      String? thinkingParam;
      String? reasoningParam;
      final queryParams = request.uri.queryParameters;
      final thinkingValue = queryParams['thinking'];
      if (thinkingValue != null && thinkingValue.isNotEmpty) {
        if (thinkingValue == 'high' || thinkingValue == 'max') {
          thinkingParam = 'enabled';
          reasoningParam = thinkingValue;
          _log('从 URL 参数注入 thinking: enabled, reasoning_effort: $thinkingValue');
        }
      }

      if (thinkingParam != null) {
        bodyJson['thinking'] = {'type': thinkingParam};
        bodyJson['reasoning_effort'] = reasoningParam;
      } else {
        if (rule.thinkingMode.isNotEmpty) {
          bodyJson['thinking'] = {'type': rule.thinkingMode};
          _log('注入 thinking: ${rule.thinkingMode}');
        }
        if (rule.thinkingMode == 'enabled') {
          if (rule.reasoningEffort.isNotEmpty) {
            bodyJson['reasoning_effort'] = rule.reasoningEffort;
            _log('注入 reasoning_effort: ${rule.reasoningEffort}');
          }
        }
      }

      final modifiedBodyStr = jsonEncode(bodyJson);
      final newBodyBytes = utf8.encode(modifiedBodyStr);

      // 使用负载均衡选中的 endpoint URL
      var targetUrl = selectedEndpoint.url;
      if (!targetUrl.endsWith(endpoint)) {
        if (targetUrl.endsWith('/')) {
          targetUrl = targetUrl.substring(0, targetUrl.length - 1);
        }

        targetUrl += endpoint;
      }

      _updateLog(
        id: logId, time: startTime, method: request.method,
        path: request.uri.path, model: requestedModelId,
        targetEndpoint: targetUrl, status: LogStatus.pending,
      );

      final uri = Uri.parse(targetUrl);
      final client = HttpClient();

      try {
        final targetRequest = await client.postUrl(uri);

        request.headers.forEach((name, values) {
          if (name.toLowerCase() == 'host' ||
              name.toLowerCase() == 'content-length' ||
              name.toLowerCase() == 'authorization') {
            return;
          }
          for (var value in values) {
            targetRequest.headers.add(name, value);
          }
        });

        // 使用选中 endpoint 的 apiKey，若为空则透传原始 Authorization
        if (selectedEndpoint.apiKey.isNotEmpty) {
          targetRequest.headers.add('Authorization', 'Bearer ${selectedEndpoint.apiKey}');
        } else {
          final authHeader = request.headers.value('authorization');
          if (authHeader != null) {
            targetRequest.headers.add('Authorization', authHeader);
          }
        }

        targetRequest.headers.contentLength = newBodyBytes.length;
        targetRequest.headers.contentType = ContentType.json;

        targetRequest.add(newBodyBytes);

        final targetResponse = await targetRequest.close();

        request.response.statusCode = targetResponse.statusCode;
        finalStatusCode = targetResponse.statusCode;

        targetResponse.headers.forEach((name, values) {
          if (name.toLowerCase() == 'transfer-encoding') return;
          for (var value in values) {
            request.response.headers.add(name, value);
          }
        });

        final responseBytes = await targetResponse.toList();
        final allBytes = responseBytes.expand((b) => b).toList();
        responseBodyStr = utf8.decode(allBytes);

        request.response.add(allBytes);
        await request.response.close();
        _log('请求转发完成，状态码: ${targetResponse.statusCode}');

        final isError = targetResponse.statusCode >= 400;
        _updateLog(
          id: logId, time: startTime, method: request.method,
          path: request.uri.path, model: requestedModelId,
          targetEndpoint: targetUrl, statusCode: targetResponse.statusCode,
          status: isError ? LogStatus.error : LogStatus.completed,
        );
      } catch (e) {
        _log('转发请求失败: $e');
        finalError = e.toString();
        try {
          final errorResp = jsonEncode({
            'error': {
              'message': 'Bad Gateway: $e',
              'type': 'proxy_error',
            }
          });
          request.response.statusCode = HttpStatus.badGateway;
          finalStatusCode = HttpStatus.badGateway;
          responseBodyStr = errorResp;
          request.response.write(errorResp);
          await request.response.close();
        } catch (err) {
          _log('响应关闭异常: $err');
        }

        _updateLog(
          id: logId, time: startTime, method: request.method,
          path: request.uri.path, model: requestedModelId,
          targetEndpoint: targetUrl,
          statusCode: finalStatusCode ?? HttpStatus.badGateway,
          status: LogStatus.error, error: e.toString(),
        );
      } finally {
        client.close();
      }

      _logWriter.writeLog(
        time: startTime, method: request.method, path: request.uri.path,
        requestBody: modifiedBodyStr, statusCode: finalStatusCode ?? 0,
        responseBody: responseBodyStr, error: finalError,
        model: requestedModelId, targetEndpoint: targetUrl,
        requestDurationMs: DateTime.now().difference(startTime).inMilliseconds,
      );
    } catch (e) {
      _log('处理请求出错: $e');
      finalError = e.toString();
      _updateLog(
        id: logId, time: startTime, method: request.method,
        path: request.uri.path, statusCode: HttpStatus.internalServerError,
        status: LogStatus.error, error: e.toString(),
      );
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('Internal Server Error: $e');
        await request.response.close();
      } catch (err) {
        _log('响应关闭异常: $err');
      }
    }
  }

  void _emitPendingLog({
    required String id,
    required DateTime time,
    required String method,
    required String path,
  }) {
    if (onLogEntry != null) {
      onLogEntry!(
        LogEntry(
          id: id,
          time: time,
          method: method,
          path: path,
          status: LogStatus.pending,
        ),
      );
    }
  }

  void _updateLog({
    required String id,
    required DateTime time,
    required String method,
    required String path,
    String? model,
    String? targetEndpoint,
    int? statusCode,
    String? error,
    LogStatus status = LogStatus.completed,
  }) {
    if (onLogEntryUpdate != null) {
      onLogEntryUpdate!(
        LogEntry(
          id: id,
          time: time,
          method: method,
          path: path,
          model: model,
          targetEndpoint: targetEndpoint,
          statusCode: statusCode,
          error: error,
          requestDurationMs: DateTime.now().difference(time).inMilliseconds,
          status: status,
        ),
      );
    }
  }

  void _emitLog({
    required DateTime time,
    required String method,
    required String path,
    String? model,
    String? targetEndpoint,
    int? statusCode,
    String? error,
  }) {
    if (onLogEntry != null) {
      onLogEntry!(
        LogEntry(
          id: _nextLogId(),
          time: time,
          method: method,
          path: path,
          model: model,
          targetEndpoint: targetEndpoint,
          statusCode: statusCode,
          error: error,
          requestDurationMs: DateTime.now().difference(time).inMilliseconds,
          status: LogStatus.completed,
        ),
      );
    }
  }
}
