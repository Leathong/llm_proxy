import 'dart:convert';
import 'dart:io';

import 'package:llm_proxy/features/logs/data/datasources/log_file_writer.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_entry.dart';
import 'package:llm_proxy/features/proxy/domain/services/proxy_logger.dart';
import 'package:llm_proxy/features/proxy/domain/services/request_forwarder.dart';
import 'package:llm_proxy/features/proxy/domain/services/request_transformer.dart';
import 'package:llm_proxy/features/proxy/domain/services/rule_matcher.dart';
import 'package:llm_proxy/features/rules/domain/entities/rule.dart';

/// 请求路由器：根据路径分发请求到对应 handler，组装各 service 完成处理
class RequestRouter {
  final Future<List<Rule>> Function() getRules;
  final ProxyLogger logger;
  final RuleMatcher ruleMatcher;
  final RequestTransformer transformer;
  final RequestForwarder forwarder;
  final LogFileWriter logWriter;

  RequestRouter({
    required this.getRules,
    required this.logger,
    required this.ruleMatcher,
    required this.transformer,
    required this.forwarder,
    required this.logWriter,
  });

  /// 处理入站请求：CORS 预检 → 路由分发
  Future<void> handle(HttpRequest request) async {
    try {
      _setCorsHeaders(request.response);
      if (request.method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
        return;
      }

      final path = request.uri.path;
      logger.log('收到请求: ${request.method} $path');

      if (path.endsWith('/v1/models')) {
        await _handleModels(request);
      } else if (path == '/v1/chat/completions' || path == '/v1/messages') {
        await _handleChatCompletions(request, endpoint: path);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('Not Found');
        await request.response.close();
      }
    } catch (e) {
      logger.log('处理请求出错: $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('Internal Server Error: $e');
        await request.response.close();
      } catch (err) {
        logger.log('响应关闭异常: $err');
      }
    }
  }

  void _setCorsHeaders(HttpResponse response) {
    response.headers.add('Access-Control-Allow-Origin', '*');
    response.headers.add('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    response.headers.add('Access-Control-Allow-Headers', 'Origin, Content-Type, Accept, Authorization');
  }

  /// 处理 /v1/models 请求：返回所有活跃规则对应的模型列表
  Future<void> _handleModels(HttpRequest request) async {
    final startTime = DateTime.now();
    final rules = (await getRules()).where((r) => r.active).toList();
    final models = rules.map((r) => {
      'id': r.customModelId,
      'object': 'model',
      'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'owned_by': 'llm-proxy',
    }).toList();

    final responseJson = {'object': 'list', 'data': models};
    final responseStr = jsonEncode(responseJson);

    request.response.headers.contentType = ContentType.json;
    request.response.write(responseStr);
    await request.response.close();

    final modelNames = models.map((m) => m['id']).join(', ');
    logger.log('已返回可用模型列表: $modelNames');
    logger.emit(
      time: startTime,
      method: request.method,
      path: request.uri.path,
      model: modelNames,
      statusCode: 200,
    );
    logWriter.writeLog(
      time: startTime,
      method: request.method,
      path: request.uri.path,
      requestBody: null,
      statusCode: 200,
      responseBody: responseStr,
      model: modelNames,
    );
  }

  /// 处理聊天补全请求：解析 → 匹配规则 → 改写 → 转发
  Future<void> _handleChatCompletions(HttpRequest request, {required String endpoint}) async {
    final startTime = DateTime.now();
    final logId = logger.nextLogId();

    logger.emitPending(
      id: logId,
      time: startTime,
      method: request.method,
      path: request.uri.path,
    );

    try {
      // --- 请求校验 ---
      if (request.method != 'POST') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        _logError(logId, startTime, request, HttpStatus.methodNotAllowed, 'Method not allowed');
        return;
      }

      final bodyString = await utf8.decoder.bind(request).join();
      if (bodyString.isEmpty) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('Empty body');
        await request.response.close();
        _logError(logId, startTime, request, HttpStatus.badRequest, 'Empty body', requestBody: bodyString);
        return;
      }

      Map<String, dynamic> bodyJson;
      try {
        bodyJson = jsonDecode(bodyString);
      } catch (e) {
        logger.log('JSON解析错误: $e');
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('Invalid JSON');
        await request.response.close();
        _logError(logId, startTime, request, HttpStatus.badRequest, 'Invalid JSON', requestBody: bodyString);
        return;
      }

      final requestedModelId = bodyJson['model'] as String?;
      if (requestedModelId == null) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('Missing model parameter');
        await request.response.close();
        _logError(logId, startTime, request, HttpStatus.badRequest, 'Missing model parameter', requestBody: bodyString);
        return;
      }

      logger.update(
        id: logId, time: startTime, method: request.method,
        path: request.uri.path, model: requestedModelId, status: LogStatus.pending,
      );

      // --- 规则匹配 ---
      final allRules = await getRules();
      final matchResult = ruleMatcher.match(allRules, requestedModelId);

      if (matchResult == null) {
        // 区分：无匹配规则 vs 规则无可用 endpoint
        final hasRule = allRules.any((r) => r.active && r.customModelId == requestedModelId);
        final errorMsg = hasRule ? 'No active endpoint' : 'Model not found';
        final statusCode = hasRule ? HttpStatus.serviceUnavailable : HttpStatus.notFound;

        final errorResp = jsonEncode({
          'error': {
            'message': hasRule
                ? 'No active endpoint for model: $requestedModelId'
                : 'Model not found or not active: $requestedModelId',
            'type': 'invalid_request_error',
          }
        });
        request.response.statusCode = statusCode;
        request.response.write(errorResp);
        await request.response.close();
        logger.log(hasRule ? '规则无可用 endpoint，模型: $requestedModelId' : '未找到匹配的活跃规则，模型: $requestedModelId');
        logger.update(
          id: logId, time: startTime, method: request.method,
          path: request.uri.path, model: requestedModelId,
          statusCode: statusCode, status: LogStatus.error, error: errorMsg,
        );
        logWriter.writeLog(
          time: startTime, method: request.method, path: request.uri.path,
          requestBody: bodyString, statusCode: statusCode,
          responseBody: errorResp, error: errorMsg, model: requestedModelId,
        );
        return;
      }

      final rule = matchResult.rule;
      final selectedEndpoint = matchResult.endpoint;
      logger.log('匹配到规则: ${rule.name}, 负载均衡选中 endpoint: ${selectedEndpoint.url}');

      // --- 请求改写 ---
      transformer.transform(bodyJson, rule: rule, requestUri: request.uri, onLog: logger.log);
      final modifiedBodyStr = jsonEncode(bodyJson);
      final newBodyBytes = utf8.encode(modifiedBodyStr);
      final targetUrl = transformer.buildTargetUrl(selectedEndpoint.url, endpoint);

      logger.update(
        id: logId, time: startTime, method: request.method,
        path: request.uri.path, model: requestedModelId,
        targetEndpoint: targetUrl, status: LogStatus.pending,
      );

      // --- 转发请求 ---
      final result = await forwarder.forward(
        clientRequest: request,
        targetUrl: targetUrl,
        bodyBytes: newBodyBytes,
        endpointApiKey: selectedEndpoint.apiKey,
      );

      // 客户端断开连接，记录日志后直接返回
      if (result.clientDisconnected) {
        logger.log('客户端已断开连接，上游请求已取消');
        logger.update(
          id: logId, time: startTime, method: request.method,
          path: request.uri.path, model: requestedModelId,
          targetEndpoint: targetUrl, statusCode: result.statusCode,
          status: LogStatus.error, error: 'Client disconnected',
          firstByteDurationMs: result.firstByteMs,
        );
        logWriter.writeLog(
          time: startTime, method: request.method, path: request.uri.path,
          requestBody: modifiedBodyStr, statusCode: result.statusCode,
          responseBody: result.responseBody, error: 'Client disconnected',
          model: requestedModelId, targetEndpoint: targetUrl,
          requestDurationMs: DateTime.now().difference(startTime).inMilliseconds,
          firstByteMs: result.firstByteMs,
          endpointId: selectedEndpoint.id,
        );
        return;
      }

      logger.log('请求转发完成，状态码: ${result.statusCode}');
      logger.update(
        id: logId, time: startTime, method: request.method,
        path: request.uri.path, model: requestedModelId,
        targetEndpoint: targetUrl, statusCode: result.statusCode,
        status: result.isError ? LogStatus.error : LogStatus.completed,
        error: result.error,
        firstByteDurationMs: result.firstByteMs,
      );
      logWriter.writeLog(
        time: startTime, method: request.method, path: request.uri.path,
        requestBody: modifiedBodyStr, statusCode: result.statusCode,
        responseBody: result.responseBody, error: result.error,
        model: requestedModelId, targetEndpoint: targetUrl,
        requestDurationMs: DateTime.now().difference(startTime).inMilliseconds,
        firstByteMs: result.firstByteMs,
        endpointId: selectedEndpoint.id,
      );
    } catch (e) {
      logger.log('处理请求出错: $e');
      logger.update(
        id: logId, time: startTime, method: request.method,
        path: request.uri.path, statusCode: HttpStatus.internalServerError,
        status: LogStatus.error, error: e.toString(),
      );
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('Internal Server Error: $e');
        await request.response.close();
      } catch (err) {
        logger.log('响应关闭异常: $err');
      }
    }
  }

  /// 记录错误日志的便捷方法
  void _logError(
    String logId, DateTime startTime, HttpRequest request,
    int statusCode, String error, {String? requestBody,}
  ) {
    logger.update(
      id: logId, time: startTime, method: request.method,
      path: request.uri.path, statusCode: statusCode,
      status: LogStatus.error, error: error,
    );
    logWriter.writeLog(
      time: startTime, method: request.method, path: request.uri.path,
      requestBody: requestBody, statusCode: statusCode, error: error,
    );
  }
}
