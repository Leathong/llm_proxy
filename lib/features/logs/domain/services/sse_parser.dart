import 'dart:convert';

import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';

/// SSE 事件解析结果（中间表示，不绑定具体实体类型）
class SseParseResult {
  final String? type;
  final String? model;
  final String? stopReason;
  final Map<String, dynamic>? usage;
  final List<Map<String, dynamic>>? content;
  final String? id;

  const SseParseResult({
    this.type,
    this.model,
    this.stopReason,
    this.usage,
    this.content,
    this.id,
  });
}

/// SSE 流式响应解析器，可在 isolate 中执行。
/// 负责将原始 JSON/SSE 字符串解析为结构化中间表示。
class SseParser {
  /// 解析响应体，返回预解析的结构化结果
  /// [rawBody] 可能是 SSE 流式文本或纯 JSON
  /// [endpointPath] 用于兜底判断 SSE 格式
  static SseParseResult parseResponse(String rawBody, String endpointPath) {
    if (rawBody.isEmpty) {
      return const SseParseResult(type: 'empty');
    }

    if (!rawBody.startsWith('event:') && !rawBody.startsWith('data:')) {
      try {
        final data = jsonDecode(rawBody) as Map<String, dynamic>;
        return _jsonToResult('json', data);
      } catch (_) {
        return const SseParseResult(type: 'raw');
      }
    }

    final events = _parseSseEvents(rawBody);
    if (events.isEmpty) {
      return const SseParseResult(type: 'raw');
    }

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

  /// 将非流式 JSON 响应转为 SseParseResult
  /// 支持 OpenAI 格式（choices[0].message.content）和 Anthropic 格式（content blocks）
  static SseParseResult _jsonToResult(
    String type,
    Map<String, dynamic> data,
  ) {
    List<Map<String, dynamic>>? blocks;

    // 尝试 Anthropic 格式：data.content 为 content blocks 数组
    final contentList = data['content'] as List<dynamic>?;
    if (contentList != null) {
      blocks = contentList.whereType<Map<String, dynamic>>().toList();
    }

    // 尝试 OpenAI 格式：data.choices[0].message.content
    if (blocks == null || blocks.isEmpty) {
      final choices = data['choices'] as List<dynamic>?;
      if (choices != null && choices.isNotEmpty) {
        final firstChoice = choices.first;
        if (firstChoice is Map<String, dynamic>) {
          final message = firstChoice['message'] as Map<String, dynamic>?;
          if (message != null) {
            final text = message['content'] as String?;
            if (text != null && text.isNotEmpty) {
              blocks = [FileLogContentBlock(type: 'text', text: text).toJson()];
            }
            // 处理 tool_calls
            final toolCalls = message['tool_calls'] as List<dynamic>?;
            if (toolCalls != null) {
              blocks ??= [];
              for (final tc in toolCalls) {
                if (tc is Map<String, dynamic>) {
                  final func = tc['function'] as Map<String, dynamic>?;
                  Map<String, dynamic>? parsedInput;
                  if (func != null) {
                    try {
                      parsedInput = jsonDecode(
                        func['arguments'] as String? ?? '',
                      ) as Map<String, dynamic>;
                    } catch (_) {}
                  }
                  blocks.add(FileLogContentBlock(
                    type: 'tool_use',
                    id: tc['id'] as String?,
                    name: func?['name'] as String?,
                    input: parsedInput,
                  ).toJson());
                }
              }
            }
          }
          // 提取 finish_reason
          if (data['stop_reason'] == null) {
            data['stop_reason'] = firstChoice['finish_reason'] as String?;
          }
        }
      }
    }

    return SseParseResult(
      type: type,
      model: data['model'] as String?,
      stopReason:
          data['stop_reason'] as String? ?? data['finish_reason'] as String?,
      usage: data['usage'] is Map<String, dynamic>
          ? _usageToJson(data['usage'] as Map<String, dynamic>)
          : null,
      content: blocks,
      id: data['id'] as String?,
    );
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

  static SseParseResult _assembleAnthropicSse(
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

    return SseParseResult(
      type: 'anthropic_sse',
      model: model,
      stopReason: stopReason,
      usage: usage != null ? _usageToJson(usage) : null,
      content: contentBlocks.isNotEmpty ? contentBlocks : null,
      id: id,
    );
  }

  // ==================== OpenAI SSE 拼接 ====================

  static SseParseResult _assembleOpenaiSse(
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

    return SseParseResult(
      type: 'openai_sse',
      model: model,
      stopReason: finishReason,
      usage: usage != null ? _usageToJson(usage) : null,
      content: contentBlocks.isNotEmpty ? contentBlocks : null,
    );
  }
}
