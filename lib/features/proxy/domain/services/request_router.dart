import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:llm_proxy/features/logs/data/datasources/request_body_parser.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_entry.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';
import 'package:llm_proxy/features/logs/domain/repositories/log_repository.dart';
import 'package:llm_proxy/features/logs/domain/services/sse_parser.dart';
import 'package:llm_proxy/features/proxy/domain/entities/active_request_info.dart';
import 'package:llm_proxy/features/proxy/domain/services/proxy_logger.dart';
import 'package:llm_proxy/features/proxy/domain/services/provider_format.dart';
import 'package:llm_proxy/features/proxy/domain/services/request_forwarder.dart';
import 'package:llm_proxy/features/proxy/domain/services/request_transformer.dart';
import 'package:llm_proxy/features/proxy/domain/services/rule_matcher.dart';
import 'package:llm_proxy/features/rules/domain/repositories/rule_repository.dart';
import 'package:llm_proxy/features/rules/domain/entities/system_prompt.dart';

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

  /// 从已修改的 bodyJson 构建结构化请求日志
  FileLogRequest? _buildParsedRequest(Map<String, dynamic> bodyJson) {
    final model = bodyJson['model'] as String?;
    if (model == null) return null;

    final messages = <FileLogMessage>[];
    if (bodyJson['messages'] is List) {
      for (final msg in bodyJson['messages'] as List) {
        if (msg is Map<String, dynamic>) {
          messages.add(RequestBodyParser.simplifyMessage(msg, truncate: false));
        }
      }
    }

    final (_, systemFull) = RequestBodyParser.extractSystem(bodyJson['system']);

    final tools = RequestBodyParser.extractToolDefs(bodyJson['tools']);

    final extras = Map<String, dynamic>.from(bodyJson)
      ..remove('model')
      ..remove('stream')
      ..remove('messages')
      ..remove('system')
      ..remove('tools');

    return FileLogRequest(
      model: model,
      stream: bodyJson['stream'] as bool?,
      messages: messages,
      systemFull: systemFull,
      tools: tools,
      otherParams: extras.isNotEmpty ? extras : null,
    );
  }

  /// 构建用于日志展示的模型名称，格式：请求模型→Provider名称/实际模型
  static String buildDisplayModel(
    String requestedModelId,
    String providerName,
    String targetModelId,
  ) {
    return '$requestedModelId→$providerName/$targetModelId';
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
        await _handleModelsRequest(request);
      } else {
        final requestFormat = ProviderFormat.fromPath(path);
        if (requestFormat != null) {
          await _handleChatRequest(request, requestFormat: requestFormat);
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write('Not Found');
          await request.response.close();
        }
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

  Future<void> _handleModelsRequest(HttpRequest request) async {
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

  Future<void> _handleChatRequest(HttpRequest request, {
    required ProviderFormat requestFormat,
  }) async {
    final startTime = DateTime.now();
    var logId = 0;
    String? requestedModelId;

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

      requestedModelId = bodyJson['model'] as String?;
      if (requestedModelId == null) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('Missing model parameter');
        await request.response.close();
        return;
      }

      final initialParsedReq = _buildParsedRequest(bodyJson);

      logId = await logRepository.addLog(LogEntry(
        id: 0,
        time: startTime,
        method: request.method,
        path: request.uri.path,
        model: requestedModelId,
        status: LogStatus.pending,
        requestBody: bodyString,
        parsedRequest: initialParsedReq,
      ));

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
        final errorMsg = 'Model not found or not active: $requestedModelId';
        final errorResp = jsonEncode({
          'error': {
            'message': errorMsg,
            'type': 'invalid_request_error',
          }
        });
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(errorResp);
        await request.response.close();

        final duration = DateTime.now().difference(startTime).inMilliseconds;
        unawaited(logRepository.updateLog(LogEntry(
          id: logId, time: startTime, method: request.method,
          path: request.uri.path, model: requestedModelId,
          statusCode: HttpStatus.notFound, status: LogStatus.error, error: errorMsg,
          requestDurationMs: duration,
        )));
        return;
      }

      final rule = matchResult.rule;

      // 如果规则关联了 system prompt，加载其内容
      String? systemPromptContent;
      SystemPromptMode systemPromptMode = SystemPromptMode.replace;
      if (rule.systemPromptId != null) {
        final prompts = await ruleRepository.getSystemPrompts();
        final matched = prompts.where((p) => p.id == rule.systemPromptId).toList();
        if (matched.isNotEmpty) {
          systemPromptContent = matched.first.content;
          systemPromptMode = matched.first.mode;
          logger.log('已加载 system prompt: ${matched.first.name} (mode: ${systemPromptMode.value})');
        }
      }

      // 规则必须关联 providerModelId
      if (rule.providerModelId == null) {
        final errorMsg = 'Rule "${rule.name}" has no provider model configured';
        logger.log(errorMsg);
        final errorResp = jsonEncode({
          'error': {
            'message': errorMsg,
            'type': 'invalid_request_error',
          }
        });
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write(errorResp);
        await request.response.close();

        final duration = DateTime.now().difference(startTime).inMilliseconds;
        unawaited(logRepository.updateLog(LogEntry(
          id: logId, time: startTime, method: request.method,
          path: request.uri.path, model: requestedModelId,
          statusCode: HttpStatus.internalServerError,
          status: LogStatus.error, error: errorMsg,
          requestDurationMs: duration,
        )));
        return;
      }

      final providerModel = await ruleRepository.getProviderModelById(rule.providerModelId!);
      if (providerModel == null) {
        final errorMsg = 'Provider model not found for rule: ${rule.name}';
        logger.log(errorMsg);
        final errorResp = jsonEncode({
          'error': {
            'message': errorMsg,
            'type': 'invalid_request_error',
          }
        });
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write(errorResp);
        await request.response.close();

        final duration = DateTime.now().difference(startTime).inMilliseconds;
        unawaited(logRepository.updateLog(LogEntry(
          id: logId, time: startTime, method: request.method,
          path: request.uri.path, model: requestedModelId,
          statusCode: HttpStatus.internalServerError,
          status: LogStatus.error, error: errorMsg,
          requestDurationMs: duration,
        )));
        return;
      }

      final provider = await ruleRepository.getModelProviderById(providerModel.providerId);
      if (provider == null) {
        final errorMsg = 'Model provider not found for rule: ${rule.name}';
        logger.log(errorMsg);
        final errorResp = jsonEncode({
          'error': {
            'message': errorMsg,
            'type': 'invalid_request_error',
          }
        });
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write(errorResp);
        await request.response.close();

        final duration = DateTime.now().difference(startTime).inMilliseconds;
        unawaited(logRepository.updateLog(LogEntry(
          id: logId, time: startTime, method: request.method,
          path: request.uri.path, model: requestedModelId,
          statusCode: HttpStatus.internalServerError,
          status: LogStatus.error, error: errorMsg,
          requestDurationMs: duration,
        )));
        return;
      }

      final providerFormat = ProviderFormat.parse(provider.format) ?? ProviderFormat.openai;

      // 格式校验：请求 path 格式必须与 Provider 配置的格式匹配
      if (requestFormat != providerFormat) {
        final errorMsg = 'Format mismatch: request path indicates ${requestFormat.name} '
            'but provider "${provider.name}" is configured as ${providerFormat.name}';
        logger.log(errorMsg);
        final errorResp = jsonEncode({
          'error': {
            'message': errorMsg,
            'type': 'invalid_request_error',
          }
        });
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write(errorResp);
        await request.response.close();

        final duration = DateTime.now().difference(startTime).inMilliseconds;
        unawaited(logRepository.updateLog(LogEntry(
          id: logId, time: startTime, method: request.method,
          path: request.uri.path,
          model: buildDisplayModel(requestedModelId, provider.name, providerModel.modelId),
          statusCode: HttpStatus.badRequest, status: LogStatus.error, error: errorMsg,
          requestDurationMs: duration,
        )));
        return;
      }

      final targetModelId = providerModel.modelId;
      final apiKey = provider.apiKey;
      final targetUrl = transformer.buildTargetUrl(
        baseUrl: provider.baseUrl,
        format: providerFormat,
      );
      logger.log('匹配到规则: ${rule.name}, Provider: ${provider.name}, 模型: $targetModelId');

      // 拼接 rule 名称和实际模型名称，便于日志中区分
      final displayModel = buildDisplayModel(requestedModelId, provider.name, targetModelId);

      transformer.transform(
        bodyJson,
        rule: rule,
        targetModelId: targetModelId,
        format: providerFormat,
        systemPromptContent: systemPromptContent,
        systemPromptMode: systemPromptMode,
        onLog: logger.log,
      );
      final modifiedBodyStr = jsonEncode(bodyJson);
      final newBodyBytes = utf8.encode(modifiedBodyStr);

      final result = await forwarder.forward(
        clientRequest: request,
        targetUrl: targetUrl,
        bodyBytes: newBodyBytes,
        endpointApiKey: apiKey,
        convertThinkingToContent: rule.convertThinkingToContent,
        onFirstByte: (firstByteMs) {
          // 首字节返回后立即更新日志，让用户尽早看到 TTFB 信息
          unawaited(logRepository.updateLog(LogEntry(
            id: logId,
            time: startTime,
            method: request.method,
            path: request.uri.path,
            model: displayModel,
            targetEndpoint: targetUrl,
            status: LogStatus.pending,
            firstByteDurationMs: firstByteMs,
          )));
        },
      );

      final duration = DateTime.now().difference(startTime).inMilliseconds;

      if (result.clientDisconnected) {
        logger.log('客户端已断开连接，上游请求已取消');
        unawaited(logRepository.updateLog(LogEntry(
          id: logId, time: startTime, method: request.method,
          path: request.uri.path, model: displayModel,
          targetEndpoint: targetUrl, statusCode: result.statusCode,
          status: LogStatus.error, error: 'Client disconnected',
          firstByteDurationMs: result.firstByteMs,
          requestDurationMs: duration,
        )));
        return;
      }

      logger.log('请求转发完成，状态码: ${result.statusCode}');

      final parsedRespFuture = compute(_parseResponseBodyIsolate, {
        'body': result.responseBody ?? '',
        'path': request.uri.path,
      });

      final parsedRespResult = await parsedRespFuture;

      // 使用 transform 后的 bodyJson 构建结构化请求日志
      final parsedReq = _buildParsedRequest(bodyJson);

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
        model: displayModel,
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
    } catch (e) {
      logger.log('处理请求出错: $e');
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      if (logId > 0) {
        unawaited(logRepository.updateLog(LogEntry(
          id: logId, time: startTime, method: request.method,
          path: request.uri.path, model: requestedModelId ?? 'unknown',
          statusCode: HttpStatus.internalServerError,
          status: LogStatus.error, error: e.toString(),
          requestDurationMs: duration,
        )));
      }
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('Internal Server Error: $e');
        await request.response.close();
      } catch (err) {
        logger.log('响应关闭异常: $err');
      }
    } finally {
      // 统一兜底：无论请求从哪条分支结束（包括上面提前 return 的错误路径），
      // 都确保从“进行中的请求”中移除，防止条目永久残留、时长虚涨到数小时
      if (logId > 0) {
        onRequestComplete?.call(logId);
      }
    }
  }
}
