import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:llm_proxy/models/proxy_rule.dart';
import 'package:llm_proxy/models/proxy_log.dart';
import 'package:llm_proxy/services/proxy_log_writer.dart';

class ProxyServer {
  HttpServer? _server;
  bool get isRunning => _server != null;
  int _port = 8080;

  // 自增 ID，用于为每条日志分配唯一标识
  int _logIdCounter = 0;

  final List<ProxyRule> Function() getRules;
  final void Function(String message)? onLog;
  final void Function(ProxyLog proxyLog)? onProxyLog;
  // 新增：日志更新回调，用于请求完成后刷新已有日志条目
  final void Function(ProxyLog proxyLog)? onProxyLogUpdate;
  final ProxyLogWriter _logWriter = ProxyLogWriter();

  ProxyServer({
    required this.getRules,
    this.onLog,
    this.onProxyLog,
    this.onProxyLogUpdate,
  });

  String _nextLogId() => 'log_${++_logIdCounter}';

  void setLogFilePath(String path) {
    _logWriter.setLogFilePath(path);
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
      } else if (path.endsWith('/v1/chat/completions')) {
        await _handleChatCompletionsRequest(request);
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
    final rules = getRules().where((r) => r.active).toList();
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
    // models 请求较快，直接以 completed 状态 emit
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

  Future<void> _handleChatCompletionsRequest(HttpRequest request) async {
    final startTime = DateTime.now();
    final logId = _nextLogId();
    String? responseBodyStr;

    int? finalStatusCode;
    String? finalError;

    // 立即发出 pending 状态日志，让 UI 显示"请求中"
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

      // 解析到 model 后，更新 pending 日志的 model 信息
      _updateLog(
        id: logId, time: startTime, method: request.method,
        path: request.uri.path, model: requestedModelId,
        status: LogStatus.pending,
      );

      final rule = getRules().where((r) => r.active).cast<ProxyRule?>().firstWhere(
        (r) => r?.customModelId == requestedModelId,
        orElse: () => null,
      );

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

      _log('匹配到规则: ${rule.name}, 转发至 ${rule.endpoint}');

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

      var targetUrl = rule.endpoint;
      if (!targetUrl.endsWith('/v1/chat/completions')) {
        if (targetUrl.endsWith('/')) {
          targetUrl += 'v1/chat/completions';
        } else {
          targetUrl += '/v1/chat/completions';
        }
      }

      // 更新日志：补充转发目标信息
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

        if (rule.apiKey.isNotEmpty) {
          targetRequest.headers.add('Authorization', 'Bearer ${rule.apiKey}');
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

        // 请求完成，更新日志状态为 completed
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

  /// 发出 pending 状态的日志（请求刚发起）
  void _emitPendingLog({
    required String id,
    required DateTime time,
    required String method,
    required String path,
  }) {
    if (onProxyLog != null) {
      onProxyLog!(
        ProxyLog(
          id: id,
          time: time,
          method: method,
          path: path,
          status: LogStatus.pending,
        ),
      );
    }
  }

  /// 更新已有日志条目（请求完成 / 出错时调用）
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
    if (onProxyLogUpdate != null) {
      onProxyLogUpdate!(
        ProxyLog(
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

  /// 直接 emit 已完成的日志（用于 models 等快速请求）
  void _emitLog({
    required DateTime time,
    required String method,
    required String path,
    String? model,
    String? targetEndpoint,
    int? statusCode,
    String? error,
  }) {
    if (onProxyLog != null) {
      onProxyLog!(
        ProxyLog(
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
