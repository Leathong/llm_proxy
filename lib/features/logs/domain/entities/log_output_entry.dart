/// 日志输出文件中的单条记录（对应 log_output.json 的每个元素）
class LogOutputEntry {
  final String timestamp;
  final String method;
  final String path;
  final String? model;
  final String? forwardTo;
  final int? durationMs;
  final int? statusCode;
  final LogOutputRequest? request;
  final LogOutputResponse? response;
  final int index;

  const LogOutputEntry({
    required this.timestamp,
    required this.method,
    required this.path,
    this.model,
    this.forwardTo,
    this.durationMs,
    this.statusCode,
    this.request,
    this.response,
    required this.index,
  });

  factory LogOutputEntry.fromJson(Map<String, dynamic> json, int index) {
    return LogOutputEntry(
      timestamp: json['timestamp'] as String? ?? '',
      method: json['method'] as String? ?? 'UNKNOWN',
      path: json['path'] as String? ?? '',
      model: json['model'] as String?,
      forwardTo: json['forward_to'] as String?,
      durationMs: json['duration_ms'] as int?,
      statusCode: json['status_code'] as int?,
      request: json['request'] != null
          ? LogOutputRequest.fromJson(json['request'] as Map<String, dynamic>)
          : null,
      response: json['response'] != null
          ? LogOutputResponse.fromJson(json['response'] as Map<String, dynamic>)
          : null,
      index: index,
    );
  }
}

/// 请求体
class LogOutputRequest {
  final String? model;
  final bool? stream;
  final List<LogOutputMessage> messages;
  final Map<String, dynamic>? otherParams;

  const LogOutputRequest({
    this.model,
    this.stream,
    required this.messages,
    this.otherParams,
  });

  factory LogOutputRequest.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'] as List<dynamic>? ?? [];
    return LogOutputRequest(
      model: json['model'] as String?,
      stream: json['stream'] as bool?,
      messages: rawMessages
          .map((m) => LogOutputMessage.fromJson(m as Map<String, dynamic>))
          .toList(),
      otherParams: json['other_params'] as Map<String, dynamic>?,
    );
  }
}

/// 对话消息
class LogOutputMessage {
  final String role;
  final String? text;
  final List<LogOutputToolUse>? toolUses;
  final List<LogOutputToolResult>? toolResults;

  const LogOutputMessage({
    required this.role,
    this.text,
    this.toolUses,
    this.toolResults,
  });

  factory LogOutputMessage.fromJson(Map<String, dynamic> json) {
    final rawToolUses = json['tool_uses'] as List<dynamic>?;
    final rawToolResults = json['tool_results'] as List<dynamic>?;
    return LogOutputMessage(
      role: json['role'] as String? ?? 'unknown',
      text: json['text'] as String?,
      toolUses: rawToolUses
          ?.map((t) => LogOutputToolUse.fromJson(t as Map<String, dynamic>))
          .toList(),
      toolResults: rawToolResults
          ?.map((t) => LogOutputToolResult.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// 工具调用
class LogOutputToolUse {
  final String name;
  final String id;
  final String? inputPreview;

  const LogOutputToolUse({
    required this.name,
    required this.id,
    this.inputPreview,
  });

  factory LogOutputToolUse.fromJson(Map<String, dynamic> json) {
    return LogOutputToolUse(
      name: json['name'] as String? ?? '',
      id: json['id'] as String? ?? '',
      inputPreview: json['input_preview'] as String?,
    );
  }
}

/// 工具调用结果
class LogOutputToolResult {
  final String toolUseId;
  final String? contentPreview;

  const LogOutputToolResult({
    required this.toolUseId,
    this.contentPreview,
  });

  factory LogOutputToolResult.fromJson(Map<String, dynamic> json) {
    return LogOutputToolResult(
      toolUseId: json['tool_use_id'] as String? ?? '',
      contentPreview: json['content_preview'] as String?,
    );
  }
}

/// 响应体
class LogOutputResponse {
  final String? type;
  final String? model;
  final String? stopReason;
  final LogOutputUsage? usage;
  final List<LogOutputContentBlock>? content;
  final String? id;

  const LogOutputResponse({
    this.type,
    this.model,
    this.stopReason,
    this.usage,
    this.content,
    this.id,
  });

  factory LogOutputResponse.fromJson(Map<String, dynamic> json) {
    final rawContent = json['content'] as List<dynamic>?;
    return LogOutputResponse(
      type: json['type'] as String?,
      model: json['model'] as String?,
      stopReason: json['stop_reason'] as String?,
      usage: json['usage'] != null
          ? LogOutputUsage.fromJson(json['usage'] as Map<String, dynamic>)
          : null,
      content: rawContent
          ?.map((c) =>
              LogOutputContentBlock.fromJson(c as Map<String, dynamic>))
          .toList(),
      id: json['id'] as String?,
    );
  }
}

/// Token 用量统计
class LogOutputUsage {
  final int? cacheCreationInputTokens;
  final int? cacheReadInputTokens;
  final int? inputTokens;
  final int? outputTokens;
  final String? serviceTier;

  const LogOutputUsage({
    this.cacheCreationInputTokens,
    this.cacheReadInputTokens,
    this.inputTokens,
    this.outputTokens,
    this.serviceTier,
  });

  factory LogOutputUsage.fromJson(Map<String, dynamic> json) {
    return LogOutputUsage(
      cacheCreationInputTokens: json['cache_creation_input_tokens'] as int?,
      cacheReadInputTokens: json['cache_read_input_tokens'] as int?,
      inputTokens: json['input_tokens'] as int?,
      outputTokens: json['output_tokens'] as int?,
      serviceTier: json['service_tier'] as String?,
    );
  }

  int get totalInputTokens =>
      (inputTokens ?? 0) +
      (cacheCreationInputTokens ?? 0) +
      (cacheReadInputTokens ?? 0);
}

/// 响应内容块（text / tool_use）
class LogOutputContentBlock {
  final String type;
  final String? text;
  final String? id;
  final String? name;
  final Map<String, dynamic>? input;

  const LogOutputContentBlock({
    required this.type,
    this.text,
    this.id,
    this.name,
    this.input,
  });

  factory LogOutputContentBlock.fromJson(Map<String, dynamic> json) {
    return LogOutputContentBlock(
      type: json['type'] as String? ?? '',
      text: json['text'] as String?,
      id: json['id'] as String?,
      name: json['name'] as String?,
      input: json['input'] as Map<String, dynamic>?,
    );
  }
}
