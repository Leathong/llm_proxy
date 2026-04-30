import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import '../models/proxy_rule.dart';
import '../models/proxy_log.dart';
import 'proxy_log_writer.dart';

class ProxyServer {
  HttpServer? _server;
  bool get isRunning => _server != null;
  int _port = 8080;

  // 依赖外部传入规则获取逻辑
  final List<ProxyRule> Function() getRules;
  final void Function(String message)? onLog;
  final void Function(ProxyLog proxyLog)? onProxyLog;
  final ProxyLogWriter _logWriter = ProxyLogWriter();

  ProxyServer({required this.getRules, this.onLog, this.onProxyLog});

  /// 设置日志文件路径（空路径表示不记录）
  void setLogFilePath(String path) {
    _logWriter.setLogFilePath(path);
  }

  /// 启动代理服务器
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

  /// 停止代理服务器
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
      // 允许跨域
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
        // 未拦截的请求，返回 404
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

  /// 拦截 /v1/models 请求
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
    _emitLog(
      time: startTime,
      method: request.method,
      path: request.uri.path,
      model: models.map((m) => m['id']).join(', '),
      statusCode: 200,
    );
    // 写入日志文件
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

  /// 拦截 /v1/chat/completions 请求并转发
  Future<void> _handleChatCompletionsRequest(HttpRequest request) async {
    final startTime = DateTime.now();
    String? responseBodyStr;

    // 提前声明用于 finally 的变量，以便在退出时写入日志
    int? finalStatusCode;
    String? finalError;

    try {
      if (request.method != 'POST') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        _emitLog(
          time: startTime,
          method: request.method,
          path: request.uri.path,
          statusCode: HttpStatus.methodNotAllowed,
        );
        _logWriter.writeLog(
          time: startTime, method: request.method, path: request.uri.path,
          requestBody: null, statusCode: HttpStatus.methodNotAllowed,
          responseBody: null, error: 'Method not allowed',
        );
        return;
      }

      // 读取请求体
      final bodyString = await utf8.decoder.bind(request).join();
      if (bodyString.isEmpty) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('Empty body');
        await request.response.close();
        _emitLog(
          time: startTime, method: request.method, path: request.uri.path,
          statusCode: HttpStatus.badRequest, error: 'Empty body',
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
        _emitLog(
          time: startTime, method: request.method, path: request.uri.path,
          statusCode: HttpStatus.badRequest, error: 'Invalid JSON',
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
        _emitLog(
          time: startTime, method: request.method, path: request.uri.path,
          statusCode: HttpStatus.badRequest, error: 'Missing model parameter',
        );
        _logWriter.writeLog(
          time: startTime, method: request.method, path: request.uri.path,
          requestBody: bodyString, statusCode: HttpStatus.badRequest,
          error: 'Missing model parameter',
        );
        return;
      }

      // 查找匹配的规则
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
        _emitLog(
          time: startTime, method: request.method, path: request.uri.path,
          model: requestedModelId, statusCode: HttpStatus.notFound,
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

      // 替换为目标模型 ID
      bodyJson['model'] = rule.targetModelId;

      // 从 URL 查询参数中提取 thinking 参数，优先级高于规则配置
      // 参数格式: ?thinking=high 或 ?thinking=max
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

      // 注入思考模式参数（URL 参数优先）
      if (thinkingParam != null) {
        bodyJson['thinking'] = {'type': thinkingParam};
        bodyJson['reasoning_effort'] = reasoningParam;
      } else {
        if (rule.thinkingMode.isNotEmpty) {
          bodyJson['thinking'] = {'type': rule.thinkingMode};
          _log('注入 thinking: ${rule.thinkingMode}');
        }
        // 仅在 thinking 启用时（值为 enabled）才注入 reasoning_effort
        if (rule.thinkingMode == 'enabled') {
          if (rule.reasoningEffort.isNotEmpty) {
            bodyJson['reasoning_effort'] = rule.reasoningEffort;
            _log('注入 reasoning_effort: ${rule.reasoningEffort}');
          }
        }
      }

      final modifiedBodyStr = jsonEncode(bodyJson);
      final newBodyBytes = utf8.encode(modifiedBodyStr);

      // 构造目标 URL
      var targetUrl = rule.endpoint;
      if (!targetUrl.endsWith('/v1/chat/completions')) {
        if (targetUrl.endsWith('/')) {
          targetUrl += 'v1/chat/completions';
        } else {
          targetUrl += '/v1/chat/completions';
        }
      }

      final uri = Uri.parse(targetUrl);
      final client = HttpClient();

      try {
        final targetRequest = await client.postUrl(uri);

        // 复制请求头
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

        // 设置 Authorization
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

        // 复制响应头
        targetResponse.headers.forEach((name, values) {
          if (name.toLowerCase() == 'transfer-encoding') return;
          for (var value in values) {
            request.response.headers.add(name, value);
          }
        });

        // 读取响应体并透传（捕获完整响应内容用于日志）
        final responseBytes = await targetResponse.toList();
        final allBytes = responseBytes.expand((b) => b).toList();
        responseBodyStr = utf8.decode(allBytes);

        // 写入客户端响应
        request.response.add(allBytes);
        await request.response.close();
        _log('请求转发完成，状态码: ${targetResponse.statusCode}');

        _emitLog(
          time: startTime, method: request.method, path: request.uri.path,
          model: requestedModelId, targetEndpoint: targetUrl,
          statusCode: targetResponse.statusCode,
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

        _emitLog(
          time: startTime, method: request.method, path: request.uri.path,
          model: requestedModelId, targetEndpoint: targetUrl,
          statusCode: finalStatusCode ?? HttpStatus.badGateway,
          error: e.toString(),
        );
      } finally {
        client.close();
      }

      // 写入日志文件（含请求体和响应体）
      _logWriter.writeLog(
        time: startTime, method: request.method, path: request.uri.path,
        requestBody: modifiedBodyStr, statusCode: finalStatusCode ?? 0,
        responseBody: responseBodyStr, error: finalError,
        model: requestedModelId, targetEndpoint: targetUrl,
        requestDurationMs: DateTime.now().difference(startTime).inMilliseconds,
      );
    } catch (e) {
      // 最外层兜底
      _log('处理请求出错: $e');
      finalError = e.toString();
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('Internal Server Error: $e');
        await request.response.close();
      } catch (err) {
        _log('响应关闭异常: $err');
      }
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
    if (onProxyLog != null) {
      onProxyLog!(
        ProxyLog(
          time: time,
          method: method,
          path: path,
          model: model,
          targetEndpoint: targetEndpoint,
          statusCode: statusCode,
          error: error,
          requestDurationMs: DateTime.now().difference(time).inMilliseconds,
        ),
      );
    }
  }
}
