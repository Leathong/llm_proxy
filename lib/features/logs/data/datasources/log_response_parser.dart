import 'dart:convert';

import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';

/// 代理请求/响应解析器，可在 isolate 中执行。
/// 负责将原始 JSON/SSE 字符串解析为结构化模型。
class LogResponseParser {
  /// 解析请求体 JSON，返回预解析的结构化字段
  static Map<String, dynamic> parseRequestBody(String rawJson) {
    if (rawJson.isEmpty) return {};

    Map<String, dynamic> body;
    try {
      body = jsonDecode(rawJson) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }

    final messages = <Map<String, dynamic>>[];
    if (body['messages'] is List) {
      for (final msg in body['messages'] as List) {
        if (msg is Map<String, dynamic>) {
          messages.add(_simplifyMessage(msg));
        }
      }
    }

    final (_, systemFull) = _extractSystem(body['system']);

    final tools = _extractToolDefs(body['tools']);

    final extras = Map<String, dynamic>.from(body)
      ..remove('model')
      ..remove('stream')
      ..remove('messages')
      ..remove('system')
      ..remove('tools');

    return {
      'model': body['model'] as String?,
      'stream': body['stream'] as bool?,
      'messages': messages,
      'system_prompt': systemFull,
      'tools': tools,
      'other_params': extras.isNotEmpty ? extras : null,
    };
  }

  /// 解析响应体，返回预解析的结构化字段
  /// [rawBody] 可能是 SSE 流式文本或纯 JSON
  /// [endpointPath] 用于兜底判断 SSE 格式
  static Map<String, dynamic> parseResponseBody(
    String rawBody,
    String endpointPath,
  ) {
    if (rawBody.isEmpty) {
      return {'type': 'empty'};
    }

    // 非 SSE：尝试直接解析为 JSON
    if (!rawBody.startsWith('event:') && !rawBody.startsWith('data:')) {
      try {
        final data = jsonDecode(rawBody) as Map<String, dynamic>;
        return _jsonToResponse('json', data);
      } catch (_) {
        return {'type': 'raw'};
      }
    }

    final events = _parseSseEvents(rawBody);
    if (events.isEmpty) {
      return {'type': 'raw'};
    }

    // 根据第一个事件判断格式
    final firstData = events.first['data'];
    if (firstData is Map<String, dynamic>) {
      final msgType = firstData['type'] as String? ?? '';
      if (msgType == 'message_start' ||
          msgType == 'ping' ||
          firstData.containsKey('message')) {
        return _assembleAnthropicSse(events);
      }
      if (firstData.containsKey('choices')) {
        return _assembleOpenaiSse(events);
      }
    }

    if (endpointPath.endsWith('/v1/messages')) {
      return _assembleAnthropicSse(events);
    }
    if (endpointPath.endsWith('/v1/chat/completions')) {
      return _assembleOpenaiSse(events);
    }

    return _assembleAnthropicSse(events);
  }

  /// 将非流式 JSON 响应转为结构化 Map
  static Map<String, dynamic> _jsonToResponse(
    String type,
    Map<String, dynamic> data,
  ) {
    final contentList = data['content'] as List<dynamic>?;
    List<Map<String, dynamic>>? blocks;
    if (contentList != null) {
      blocks = contentList
          .whereType<Map<String, dynamic>>()
          .map((c) => FileLogContentBlock.fromJson(c).toJson())
          .toList();
    }

    return {
      'type': type,
      'model': data['model'] as String?,
      'stop_reason':
          data['stop_reason'] as String? ?? data['finish_reason'] as String?,
      'usage': data['usage'] is Map<String, dynamic>
          ? _usageToJson(data['usage'] as Map<String, dynamic>)
          : null,
      'content': blocks,
      'id': data['id'] as String?,
    };
  }

  /// 将 usage Map 转为结构化 JSON，确保字段名一致
  static Map<String, dynamic>? _usageToJson(Map<String, dynamic> usage) {
    if (usage.isEmpty) return null;
    return {
      if (usage['cache_creation_input_tokens'] != null)
        'cache_creation_input_tokens': usage['cache_creation_input_tokens'],
      if (usage['cache_read_input_tokens'] != null ||
          usage['prompt_cache_hit_tokens'] != null)
        'cache_read_input_tokens':
            usage['cache_read_input_tokens'] ?? usage['prompt_cache_hit_tokens'],
      if (usage['input_tokens'] != null || usage['prompt_tokens'] != null)
        'input_tokens': usage['input_tokens'] ?? usage['prompt_tokens'],
      if (usage['output_tokens'] != null ||
          usage['completion_tokens'] != null)
        'output_tokens':
            usage['output_tokens'] ?? usage['completion_tokens'],
      if (usage['service_tier'] != null)
        'service_tier': usage['service_tier'],
    };
  }

  // ==================== SSE 事件解析 ====================

  static List<Map<String, dynamic>> _parseSseEvents(String raw) {
    final events = <Map<String, dynamic>>[];
    String? currentEvent;
    final dataLines = <String>[];

    for (final line in raw.split('\n')) {
      final trimmed = line.trimRight();

      if (trimmed.startsWith('event:')) {
        if (dataLines.isNotEmpty) {
          events.add(_buildEvent(currentEvent, dataLines.join('\n')));
          dataLines.clear();
        }
        currentEvent = trimmed.substring('event:'.length).trim();
      } else if (trimmed.startsWith('data:')) {
        dataLines.add(trimmed.substring('data:'.length).trim());
      } else if (trimmed.isEmpty && dataLines.isNotEmpty) {
        events.add(_buildEvent(currentEvent, dataLines.join('\n')));
        currentEvent = null;
        dataLines.clear();
      }
    }

    if (dataLines.isNotEmpty) {
      events.add(_buildEvent(currentEvent, dataLines.join('\n')));
    }

    return events;
  }

  static Map<String, dynamic> _buildEvent(String? eventType, String dataStr) {
    final result = <String, dynamic>{};
    if (eventType != null) result['event'] = eventType;

    try {
      result['data'] = jsonDecode(dataStr);
    } catch (_) {
      result['data'] = dataStr == '[DONE]' ? '[DONE]' : dataStr;
    }

    return result;
  }

  // ==================== Anthropic SSE 拼接 ====================

  static Map<String, dynamic> _assembleAnthropicSse(
    List<Map<String, dynamic>> events,
  ) {
    String? model;
    String? stopReason;
    String? id;
    Map<String, dynamic>? usage;

    final blocks = <int, Map<String, dynamic>>{};

    for (final evt in events) {
      final data = evt['data'];
      if (data is! Map<String, dynamic>) continue;

      final evtType = data['type'] as String? ?? '';

      switch (evtType) {
        case 'message_start':
          final msg = data['message'] as Map<String, dynamic>? ?? {};
          model = msg['model'] as String?;
          usage = msg['usage'] as Map<String, dynamic>?;
          id = msg['id'] as String?;

        case 'content_block_start':
          final idx = data['index'] as int? ?? 0;
          final block = data['content_block'] as Map<String, dynamic>? ?? {};
          final blockType = block['type'] as String? ?? 'text';

          switch (blockType) {
            case 'text':
              blocks[idx] = {'type': 'text', 'text': block['text'] ?? ''};
            case 'tool_use':
              blocks[idx] = {
                'type': 'tool_use',
                'id': block['id'] ?? '',
                'name': block['name'] ?? '',
                'input_json': '',
              };
            case 'thinking':
              blocks[idx] = {
                'type': 'thinking',
                'thinking': block['thinking'] ?? '',
              };
          }

        case 'content_block_delta':
          final idx = data['index'] as int? ?? 0;
          final delta = data['delta'] as Map<String, dynamic>? ?? {};
          final deltaType = delta['type'] as String? ?? '';

          blocks.putIfAbsent(idx, () => {'type': 'text', 'text': ''});

          switch (deltaType) {
            case 'text_delta':
              blocks[idx]!['text'] =
                  (blocks[idx]!['text'] as String? ?? '') +
                      (delta['text'] as String? ?? '');
            case 'input_json_delta':
              blocks[idx]!['input_json'] =
                  (blocks[idx]!['input_json'] as String? ?? '') +
                      (delta['partial_json'] as String? ?? '');
            case 'thinking_delta':
              blocks[idx]!['thinking'] =
                  (blocks[idx]!['thinking'] as String? ?? '') +
                      (delta['thinking'] as String? ?? '');
          }

        case 'message_delta':
          final delta = data['delta'] as Map<String, dynamic>? ?? {};
          stopReason = delta['stop_reason'] as String?;
          final deltaUsage = data['usage'] as Map<String, dynamic>?;
          if (deltaUsage != null) {
            usage = {...?usage, ...deltaUsage};
          }
      }
    }

    // 整理 content blocks
    final sortedKeys = blocks.keys.toList()..sort();
    final contentBlocks = <Map<String, dynamic>>[];

    for (final idx in sortedKeys) {
      final block = blocks[idx]!;
      final type = block['type'] as String;

      if (type == 'tool_use') {
        final inputStr = block['input_json'] as String? ?? '';
        Map<String, dynamic>? input;
        try {
          input = jsonDecode(inputStr) as Map<String, dynamic>;
        } catch (_) {}

        contentBlocks.add(FileLogContentBlock(
          type: 'tool_use',
          id: block['id'] as String?,
          name: block['name'] as String?,
          input: input,
        ).toJson());
      } else {
        contentBlocks.add(FileLogContentBlock(
          type: type,
          text: block[type == 'thinking' ? 'thinking' : 'text'] as String?,
        ).toJson());
      }
    }

    return {
      'type': 'anthropic_sse',
      'model': model,
      'stop_reason': stopReason,
      'usage': usage != null ? _usageToJson(usage) : null,
      'content': contentBlocks.isNotEmpty ? contentBlocks : null,
      'id': id,
    };
  }

  // ==================== OpenAI SSE 拼接 ====================

  static Map<String, dynamic> _assembleOpenaiSse(
    List<Map<String, dynamic>> events,
  ) {
    String? model;
    String? finishReason;
    Map<String, dynamic>? usage;
    final contentBuf = StringBuffer();
    final reasoningBuf = StringBuffer();

    final toolCallsMap = <int, Map<String, dynamic>>{};

    for (final evt in events) {
      final data = evt['data'];
      if (data is! Map<String, dynamic>) continue;

      model ??= data['model'] as String?;

      if (data['usage'] is Map<String, dynamic>) {
        usage = data['usage'] as Map<String, dynamic>;
      }

      final choices = data['choices'] as List<dynamic>? ?? [];
      for (final choice in choices) {
        if (choice is! Map<String, dynamic>) continue;
        final delta = choice['delta'] as Map<String, dynamic>? ?? {};
        final finish = choice['finish_reason'] as String?;
        if (finish != null) finishReason = finish;

        final c = delta['content'] as String?;
        if (c != null && c.isNotEmpty) contentBuf.write(c);

        final rc = delta['reasoning_content'] as String?;
        if (rc != null && rc.isNotEmpty) reasoningBuf.write(rc);

        final tcs = delta['tool_calls'] as List<dynamic>?;
        if (tcs != null) {
          for (final tc in tcs) {
            if (tc is! Map<String, dynamic>) continue;
            final tcIdx = tc['index'] as int? ?? 0;
            toolCallsMap.putIfAbsent(tcIdx, () => {
              'id': tc['id'] ?? '',
              'type': tc['type'] ?? 'function',
              'function': {'name': '', 'arguments': ''},
            });
            final entry = toolCallsMap[tcIdx]!;
            if (tc['id'] != null && (tc['id'] as String).isNotEmpty) {
              entry['id'] = tc['id'];
            }
            final func = tc['function'] as Map<String, dynamic>? ?? {};
            final fn = entry['function'] as Map<String, dynamic>;
            if (func['name'] != null && (func['name'] as String).isNotEmpty) {
              fn['name'] = func['name'];
            }
            if (func['arguments'] != null) {
              fn['arguments'] =
                  (fn['arguments'] as String) + (func['arguments'] as String);
            }
          }
        }
      }
    }

    final contentBlocks = <Map<String, dynamic>>[];

    final text = contentBuf.toString();
    if (text.isNotEmpty) {
      contentBlocks
          .add(FileLogContentBlock(type: 'text', text: text).toJson());
    }

    final reasoning = reasoningBuf.toString();
    if (reasoning.isNotEmpty) {
      contentBlocks.add(
        FileLogContentBlock(type: 'thinking', text: reasoning).toJson(),
      );
    }

    final sortedTcKeys = toolCallsMap.keys.toList()..sort();
    for (final idx in sortedTcKeys) {
      final tc = toolCallsMap[idx]!;
      final fn = tc['function'] as Map<String, dynamic>;
      Map<String, dynamic>? parsedArgs;
      try {
        parsedArgs =
            jsonDecode(fn['arguments'] as String) as Map<String, dynamic>;
      } catch (_) {}

      contentBlocks.add(FileLogContentBlock(
        type: 'tool_use',
        id: tc['id'] as String?,
        name: fn['name'] as String?,
        input: parsedArgs,
      ).toJson());
    }

    return {
      'type': 'openai_sse',
      'model': model,
      'stop_reason': finishReason,
      'usage': usage != null ? _usageToJson(usage) : null,
      'content': contentBlocks.isNotEmpty ? contentBlocks : null,
    };
  }

  // ==================== 请求体解析辅助 ====================

  static Map<String, dynamic> _simplifyMessage(Map<String, dynamic> msg) {
    final role = msg['role'] as String? ?? 'unknown';
    final content = msg['content'];

    if (content is String) {
      return FileLogMessage(
        role: role,
        text: content,
      ).toJson();
    }

    if (content is List) {
      final textParts = <String>[];
      final toolUses = <FileLogToolUse>[];
      final toolResults = <FileLogToolResult>[];

      for (final item in content) {
        if (item is! Map<String, dynamic>) continue;
        final type = item['type'] as String? ?? '';

        switch (type) {
          case 'text':
            textParts.add(item['text'] as String? ?? '');
          case 'tool_use':
            toolUses.add(FileLogToolUse(
              name: item['name'] as String? ?? '',
              id: item['id'] as String? ?? '',
              inputPreview: null,
              inputFull: jsonEncode(item['input'] ?? {}),
            ));
          case 'tool_result':
            final c = item['content'];
            final contentStr = c is String ? c : jsonEncode(c ?? '');
            toolResults.add(FileLogToolResult(
              toolUseId: item['tool_use_id'] as String? ?? '',
              contentFull: contentStr,
            ));
          case 'image':
            textParts.add('[image]');
        }
      }

      final fullText = textParts.join('\n');
      return FileLogMessage(
        role: role,
        text: fullText.isNotEmpty ? fullText : null,
        toolUses: toolUses.isNotEmpty ? toolUses : null,
        toolResults: toolResults.isNotEmpty ? toolResults : null,
      ).toJson();
    }

    return FileLogMessage(
      role: role,
      text: content?.toString(),
    ).toJson();
  }

  static (String?, String?) _extractSystem(dynamic system) {
    if (system == null) return (null, null);

    String? full;
    if (system is String) {
      full = system;
    } else if (system is List) {
      final parts = <String>[];
      for (final item in system) {
        if (item is Map<String, dynamic> && item['type'] == 'text') {
          parts.add(item['text'] as String? ?? '');
        }
      }
      if (parts.isNotEmpty) {
        full = parts.join('\n');
      }
    }

    return (full, full);
  }

  static List<Map<String, dynamic>>? _extractToolDefs(dynamic tools) {
    if (tools is! List || tools.isEmpty) return null;

    final result = <Map<String, dynamic>>[];
    for (final tool in tools) {
      if (tool is! Map<String, dynamic>) continue;

      final funcObj = tool['function'] as Map<String, dynamic>?;
      final source = funcObj ?? tool;

      final name = source['name'] as String? ?? '';
      final desc = source['description'] as String?;
      final inputSchema = (source['input_schema'] ?? source['parameters'])
          as Map<String, dynamic>?;
      result.add(FileLogToolDef(
        name: name,
        description: desc,
        inputSchema: inputSchema,
      ).toJson());
    }

    return result.isNotEmpty ? result : null;
  }
}
