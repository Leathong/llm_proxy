/// 日志输出文件中的单条记录（对应 log_output.json 的每个元素）
class FileLogEntry {
  final String timestamp;
  final String method;
  final String path;
  final String? model;
  final String? forwardTo;
  final int? durationMs;
  /// 首字节耗时（毫秒）
  final int? firstByteMs;
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
    this.firstByteMs,
    this.statusCode,
    this.request,
    this.response,
    required this.index,
  });

  // 输出 token 速度（tokens/s），基于纯生成耗时（总耗时 - 首字节耗时）
  double? get outputTokensPerSecond {
    final out = response?.usage?.outputTokens;
    final dur = durationMs;
    if (out == null || dur == null || dur <= 0) return null;
    // 首字节之前的耗时属于网络延迟，不计入生成速度
    final genMs = firstByteMs != null ? dur - firstByteMs! : dur;
    if (genMs <= 0) return null;
    return out / (genMs / 1000.0);
  }

  factory FileLogEntry.fromJson(Map<String, dynamic> json, int index) {
    return FileLogEntry(
      timestamp: json['timestamp'] as String? ?? '',
      method: json['method'] as String? ?? 'UNKNOWN',
      path: json['path'] as String? ?? '',
      model: json['model'] as String?,
      forwardTo: json['forward_to'] as String?,
      durationMs: json['duration_ms'] as int?,
      firstByteMs: json['first_byte_ms'] as int?,
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
  /// 完整消息文本（未截断）
  final String? textFull;
  final List<FileLogToolUse>? toolUses;
  final List<FileLogToolResult>? toolResults;

  const FileLogMessage({
    required this.role,
    this.text,
    this.textFull,
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
  /// 完整的 input JSON 字符串
  final String? inputFull;

  const FileLogToolUse({
    required this.name,
    required this.id,
    this.inputPreview,
    this.inputFull,
  });

  factory FileLogToolUse.fromJson(Map<String, dynamic> json) {
    return FileLogToolUse(
      name: json['name'] as String? ?? '',
      id: json['id'] as String? ?? '',
      inputPreview: json['input_preview'] as String?,
      inputFull: json['input_full'] as String?,
    );
  }
}

/// 工具调用结果
class FileLogToolResult {
  final String toolUseId;
  final String? contentPreview;
  /// 完整的工具结果内容
  final String? contentFull;

  const FileLogToolResult({
    required this.toolUseId,
    this.contentPreview,
    this.contentFull,
  });

  factory FileLogToolResult.fromJson(Map<String, dynamic> json) {
    return FileLogToolResult(
      toolUseId: json['tool_use_id'] as String? ?? '',
      contentPreview: json['content_preview'] as String?,
      contentFull: json['content_full'] as String?,
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
    // 提取 OpenAI prompt_tokens_details 中的缓存信息
    final details =
        json['prompt_tokens_details'] as Map<String, dynamic>? ?? {};

    return FileLogUsage(
      // Anthropic 格式缓存字段 + OpenAI 格式兼容
      cacheCreationInputTokens:
          json['cache_creation_input_tokens'] as int?,
      cacheReadInputTokens:
          json['cache_read_input_tokens'] as int? ??
          json['prompt_cache_hit_tokens'] as int? ??
          details['cached_tokens'] as int?,
      // 输入 token：兼容 Anthropic(input_tokens) 和 OpenAI(prompt_tokens)
      inputTokens:
          json['input_tokens'] as int? ?? json['prompt_tokens'] as int?,
      // 输出 token：兼容 Anthropic(output_tokens) 和 OpenAI(completion_tokens)
      outputTokens:
          json['output_tokens'] as int? ?? json['completion_tokens'] as int?,
      serviceTier: json['service_tier'] as String?,
    );
  }

  // input_tokens/prompt_tokens 已包含缓存 token，缓存字段是其子计数
  int get totalInputTokens => inputTokens ?? 0;
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
