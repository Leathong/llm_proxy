/// 日志输出文件中的单条记录（对应 log_output.json 的每个元素）
class FileLogEntry {
  final String timestamp;
  final String method;
  final String path;
  final String? model;
  final String? forwardTo;
  final int? durationMs;
  final int? statusCode;
  final FileLogRequest? request;
  final FileLogResponse? response;
  final int index;

  const FileLogEntry({
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

  factory FileLogEntry.fromJson(Map<String, dynamic> json, int index) {
    return FileLogEntry(
      timestamp: json['timestamp'] as String? ?? '',
      method: json['method'] as String? ?? 'UNKNOWN',
      path: json['path'] as String? ?? '',
      model: json['model'] as String?,
      forwardTo: json['forward_to'] as String?,
      durationMs: json['duration_ms'] as int?,
      statusCode: json['status_code'] as int?,
      request: json['request'] != null
          ? FileLogRequest.fromJson(json['request'] as Map<String, dynamic>)
          : null,
      response: json['response'] != null
          ? FileLogResponse.fromJson(json['response'] as Map<String, dynamic>)
          : null,
      index: index,
    );
  }
}

/// 请求体
class FileLogRequest {
  final String? model;
  final bool? stream;
  final List<FileLogMessage> messages;
  /// system prompt 内容（截断后的文本预览）
  final String? systemPreview;
  /// system prompt 完整内容
  final String? systemFull;
  /// 工具定义列表（仅保留名称和描述摘要）
  final List<FileLogToolDef>? tools;
  final Map<String, dynamic>? otherParams;

  const FileLogRequest({
    this.model,
    this.stream,
    required this.messages,
    this.systemPreview,
    this.systemFull,
    this.tools,
    this.otherParams,
  });

  factory FileLogRequest.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'] as List<dynamic>? ?? [];
    return FileLogRequest(
      model: json['model'] as String?,
      stream: json['stream'] as bool?,
      messages: rawMessages
          .map((m) => FileLogMessage.fromJson(m as Map<String, dynamic>))
          .toList(),
      systemPreview: json['system_preview'] as String?,
      systemFull: json['system_full'] as String?,
      tools: (json['tools'] as List<dynamic>?)
          ?.map((t) => FileLogToolDef.fromJson(t as Map<String, dynamic>))
          .toList(),
      otherParams: json['other_params'] as Map<String, dynamic>?,
    );
  }
}

/// 对话消息
class FileLogMessage {
  final String role;
  final String? text;
  final List<FileLogToolUse>? toolUses;
  final List<FileLogToolResult>? toolResults;

  const FileLogMessage({
    required this.role,
    this.text,
    this.toolUses,
    this.toolResults,
  });

  factory FileLogMessage.fromJson(Map<String, dynamic> json) {
    final rawToolUses = json['tool_uses'] as List<dynamic>?;
    final rawToolResults = json['tool_results'] as List<dynamic>?;
    return FileLogMessage(
      role: json['role'] as String? ?? 'unknown',
      text: json['text'] as String?,
      toolUses: rawToolUses
          ?.map((t) => FileLogToolUse.fromJson(t as Map<String, dynamic>))
          .toList(),
      toolResults: rawToolResults
          ?.map((t) => FileLogToolResult.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// 工具调用
class FileLogToolUse {
  final String name;
  final String id;
  final String? inputPreview;

  const FileLogToolUse({
    required this.name,
    required this.id,
    this.inputPreview,
  });

  factory FileLogToolUse.fromJson(Map<String, dynamic> json) {
    return FileLogToolUse(
      name: json['name'] as String? ?? '',
      id: json['id'] as String? ?? '',
      inputPreview: json['input_preview'] as String?,
    );
  }
}

/// 工具调用结果
class FileLogToolResult {
  final String toolUseId;
  final String? contentPreview;

  const FileLogToolResult({
    required this.toolUseId,
    this.contentPreview,
  });

  factory FileLogToolResult.fromJson(Map<String, dynamic> json) {
    return FileLogToolResult(
      toolUseId: json['tool_use_id'] as String? ?? '',
      contentPreview: json['content_preview'] as String?,
    );
  }
}

/// 响应体
class FileLogResponse {
  final String? type;
  final String? model;
  final String? stopReason;
  final FileLogUsage? usage;
  final List<FileLogContentBlock>? content;
  final String? id;

  const FileLogResponse({
    this.type,
    this.model,
    this.stopReason,
    this.usage,
    this.content,
    this.id,
  });

  factory FileLogResponse.fromJson(Map<String, dynamic> json) {
    final rawContent = json['content'] as List<dynamic>?;
    return FileLogResponse(
      type: json['type'] as String?,
      model: json['model'] as String?,
      stopReason: json['stop_reason'] as String?,
      usage: json['usage'] != null
          ? FileLogUsage.fromJson(json['usage'] as Map<String, dynamic>)
          : null,
      content: rawContent
          ?.map((c) =>
              FileLogContentBlock.fromJson(c as Map<String, dynamic>))
          .toList(),
      id: json['id'] as String?,
    );
  }
}

/// Token 用量统计
class FileLogUsage {
  final int? cacheCreationInputTokens;
  final int? cacheReadInputTokens;
  final int? inputTokens;
  final int? outputTokens;
  final String? serviceTier;

  const FileLogUsage({
    this.cacheCreationInputTokens,
    this.cacheReadInputTokens,
    this.inputTokens,
    this.outputTokens,
    this.serviceTier,
  });

  factory FileLogUsage.fromJson(Map<String, dynamic> json) {
    return FileLogUsage(
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
class FileLogContentBlock {
  final String type;
  final String? text;
  final String? id;
  final String? name;
  final Map<String, dynamic>? input;

  const FileLogContentBlock({
    required this.type,
    this.text,
    this.id,
    this.name,
    this.input,
  });

  factory FileLogContentBlock.fromJson(Map<String, dynamic> json) {
    return FileLogContentBlock(
      type: json['type'] as String? ?? '',
      text: json['text'] as String?,
      id: json['id'] as String?,
      name: json['name'] as String?,
      input: json['input'] as Map<String, dynamic>?,
    );
  }
}

/// 工具定义（请求体中的 tools 数组元素）
class FileLogToolDef {
  final String name;
  final String? descriptionPreview;
  /// 完整描述文本（用于弹窗展示）
  final String? description;
  /// 工具参数 schema（用于弹窗展示）
  final Map<String, dynamic>? inputSchema;

  const FileLogToolDef({
    required this.name,
    this.descriptionPreview,
    this.description,
    this.inputSchema,
  });

  factory FileLogToolDef.fromJson(Map<String, dynamic> json) {
    return FileLogToolDef(
      name: json['name'] as String? ?? '',
      descriptionPreview: json['description_preview'] as String?,
      description: json['description'] as String?,
      inputSchema: json['input_schema'] as Map<String, dynamic>?,
    );
  }
}
