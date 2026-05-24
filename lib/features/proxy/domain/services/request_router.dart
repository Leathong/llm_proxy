import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:llm_proxy/features/logs/data/datasources/log_response_parser.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_entry.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';
import 'package:llm_proxy/features/logs/domain/repositories/log_repository.dart';
import 'package:llm_proxy/features/logs/domain/services/sse_parser.dart';
import 'package:llm_proxy/features/proxy/domain/entities/active_request_info.dart';
import 'package:llm_proxy/features/proxy/domain/services/proxy_logger.dart';
import 'package:llm_proxy/features/proxy/domain/services/request_forwarder.dart';
import 'package:llm_proxy/features/proxy/domain/services/request_transformer.dart';
import 'package:llm_proxy/features/proxy/domain/services/rule_matcher.dart';
import 'package:llm_proxy/features/rules/domain/repositories/rule_repository.dart';

Map<String, dynamic> _parseRequestBodyIsolate(String rawJson) =>
    LogResponseParser.parseRequestBody(rawJson);

SseParseResult _parseResponseBodyIsolate(Map<String, String> params) =>
    SseParser.parseResponse(params['body']!, params['path']!);

class RequestRouter {
  final RuleRepository ruleRepository;
  final ProxyLogger logger;
  final RuleMatcher ruleMatcher;
  final RequestTransformer transformer;
  final RequestForwarder forwarder;
  final LogRepository logRepository;
  final void Function(ActiveRequestInfo)? onRequestStart;
  final void Function(int logId)? onRequestComplete;

  final StreamController<LogEntry> _logWriteController =
      StreamController<LogEntry>.broadcast();
  StreamSubscription<LogEntry>? _logWriteSub;

  RequestRouter({
    required this.ruleRepository,
    required this.logger,
    required this.ruleMatcher,
    required this.transformer,
    required this.forwarder,
    required this.logRepository,
    this.onRequestStart,
    this.onRequestComplete,
  }) {
    _logWriteSub = _logWriteController.stream
        .listen((entry) => logRepository.addLog(entry));
  }

  void dispose() {
    _logWriteSub?.cancel();
    _logWriteController.close();
  }

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
        try { await request.response.close(); } catch (_) {}
      }
    }
  }

  void _setCorsHeaders(HttpResponse response) {
    response.headers.add('Access-Control-Allow-Origin', '*');
    response.headers.add('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    response.headers.add('Access-Control-Allow-Headers', 'Origin, Content-Type, Accept, Authorization');
  }

  Future<void> _handleModels(HttpRequest request) async {
    final startTime = DateTime.now();
    final rules = (await ruleRepository.getRules()).where((r) => r.active).toList();
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

    final duration = DateTime.now().difference(startTime).inMilliseconds;
    _logWriteController.add(LogEntry(
      id: 0,
      time: startTime,
      method: request.method,
      path: request.uri.path,
      model: modelNames,
      statusCode: 200,
      requestDurationMs: duration,
    ));
  }

  Future<void> _handleChatCompletions(HttpRequest request, {required String endpoint}) async {
    final startTime = DateTime.now();
    var logId = 0;

    try {
      if (request.method != 'POST') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }

      final bodyString = await utf8.decoder.bind(request).join();
      if (bodyString.isEmpty) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('Empty body');
        await request.response.close();
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
        return;
      }

      final requestedModelId = bodyJson['model'] as String?;
      if (requestedModelId == null) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('Missing model parameter');
        await request.response.close();
        return;
      }

      final parsedReqFuture = compute(_parseRequestBodyIsolate, bodyString);

      logId = await logRepository.addLog(LogEntry(
        id: 0,
        time: startTime,
        method: request.method,
        path: request.uri.path,
        model: requestedModelId,
        status: LogStatus.pending,
      ));
      // pending 日志需要同步写入以确保 logId 可用，后续 update 可异步

      onRequestStart?.call(ActiveRequestInfo(
        logId: logId,
        model: requestedModelId,
        path: request.uri.path,
        startTime: startTime,
        method: request.method,
        clientRequest: request,
      ));

      final allRules = await ruleRepository.getRules();
      final matchResult = ruleMatcher.match(allRules, requestedModelId);

      if (matchResult == null) {
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

        final duration = DateTime.now().difference(startTime).inMilliseconds;
        unawaited(logRepository.updateLog(LogEntry(
          id: logId, time: startTime, method: request.method,
          path: request.uri.path, model: requestedModelId,
          statusCode: statusCode, status: LogStatus.error, error: errorMsg,
          requestDurationMs: duration,
        )));
        onRequestComplete?.call(logId);
        return;
      }

      final rule = matchResult.rule;
      final selectedEndpoint = matchResult.endpoint;
      logger.log('匹配到规则: ${rule.name}, 负载均衡选中 endpoint: ${selectedEndpoint.url}');

      transformer.transform(bodyJson, rule: rule, requestUri: request.uri, onLog: logger.log);
      final modifiedBodyStr = jsonEncode(bodyJson);
      final newBodyBytes = utf8.encode(modifiedBodyStr);
      final targetUrl = transformer.buildTargetUrl(selectedEndpoint.url, endpoint);

      final result = await forwarder.forward(
        clientRequest: request,
        targetUrl: targetUrl,
        bodyBytes: newBodyBytes,
        endpointApiKey: selectedEndpoint.apiKey,
        convertThinkingToContent: rule.convertThinkingToContent,
      );

      final duration = DateTime.now().difference(startTime).inMilliseconds;

      if (result.clientDisconnected) {
        logger.log('客户端已断开连接，上游请求已取消');
        unawaited(logRepository.updateLog(LogEntry(
          id: logId, time: startTime, method: request.method,
          path: request.uri.path, model: requestedModelId,
          targetEndpoint: targetUrl, statusCode: result.statusCode,
          status: LogStatus.error, error: 'Client disconnected',
          firstByteDurationMs: result.firstByteMs,
          requestDurationMs: duration,
        )));
        onRequestComplete?.call(logId);
        return;
      }

      logger.log('请求转发完成，状态码: ${result.statusCode}');

      final parsedRespFuture = compute(_parseResponseBodyIsolate, {
        'body': result.responseBody ?? '',
        'path': endpoint,
      });

      final parsedReqMap = await parsedReqFuture;
      final parsedRespResult = await parsedRespFuture;

      FileLogRequest? parsedReq;
      if (parsedReqMap.isNotEmpty && parsedReqMap['model'] != null) {
        final msgs = (parsedReqMap['messages'] as List?)
                ?.map((m) => FileLogMessage.fromJson(m as Map<String, dynamic>))
                .toList() ??
            [];
        final tools = (parsedReqMap['tools'] as List?)
            ?.map((t) => FileLogToolDef.fromJson(t as Map<String, dynamic>))
            .toList();
        parsedReq = FileLogRequest(
          model: parsedReqMap['model'] as String?,
          stream: parsedReqMap['stream'] as bool?,
          messages: msgs,
          systemFull: parsedReqMap['system_prompt'] as String?,
          tools: tools,
          otherParams: parsedReqMap['other_params'] as Map<String, dynamic>?,
        );
      }

      FileLogResponse? parsedResp;
      if (parsedRespResult.type != null && parsedRespResult.type != 'empty' && parsedRespResult.type != 'raw') {
        FileLogUsage? usage;
        if (parsedRespResult.usage != null) {
          usage = FileLogUsage.fromJson(parsedRespResult.usage!);
        }
        final content = parsedRespResult.content
            ?.map((c) => FileLogContentBlock.fromJson(c))
            .toList();
        parsedResp = FileLogResponse(
          type: parsedRespResult.type,
          model: parsedRespResult.model,
          stopReason: parsedRespResult.stopReason,
          usage: usage,
          content: content,
          id: parsedRespResult.id,
        );
      }

      final updatedEntry = LogEntry(
        id: logId,
        time: startTime,
        method: request.method,
        path: request.uri.path,
        model: requestedModelId,
        targetEndpoint: targetUrl,
        statusCode: result.statusCode,
        error: result.error,
        requestDurationMs: duration,
        firstByteDurationMs: result.firstByteMs,
        status: result.isError ? LogStatus.error : LogStatus.completed,
        requestBody: modifiedBodyStr,
        responseBody: result.responseBody,
        parsedRequest: parsedReq,
        parsedResponse: parsedResp,
      );

      unawaited(logRepository.updateLog(updatedEntry));
      onRequestComplete?.call(logId);
    } catch (e) {
      logger.log('处理请求出错: $e');
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      if (logId > 0) {
        unawaited(logRepository.updateLog(LogEntry(
          id: logId, time: startTime, method: request.method,
          path: request.uri.path, statusCode: HttpStatus.internalServerError,
          status: LogStatus.error, error: e.toString(),
          requestDurationMs: duration,
        )));
        onRequestComplete?.call(logId);
      }
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('Internal Server Error: $e');
        await request.response.close();
      } catch (err) {
        logger.log('响应关闭异常: $err');
      }
    }
  }
}
