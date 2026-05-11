import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';

/// 将 .log 文本文件解析为结构化的 [FileLogEntry] 列表。
/// 支持 Anthropic 和 OpenAI 的 SSE 流式响应拼接。
class LogFileParser {
  // 匹配分隔线: -------------------- 2026-05-01 10:14:53 --------------------
  static final _separatorRe = RegExp(
    r'^-{20}\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s+-{20}$',
  );

  // 元数据行正则
  static final _requestRe = RegExp(r'^\[REQUEST\]\s+(\S+)\s+(.+)$');
  static final _modelRe = RegExp(r'^\[Model\]\s+(.+)$');
  static final _forwardToRe = RegExp(r'^\[Forward To\]\s+(.+)$');
  static final _durationRe = RegExp(r'^\[Duration\]\s+(\d+)ms$');
  static final _statusRe = RegExp(r'^\[Status\]\s+(\d+)$');

  /// 解析 .log 文件，在 Isolate 中执行以避免阻塞 UI
  static Future<List<FileLogEntry>> parseFile(String filePath) async {
    final content = await File(filePath).readAsString();
    return compute(_parseContent, content);
  }

  /// Isolate 入口：解析日志文本内容
  static List<FileLogEntry> _parseContent(String content) {
    final rawEntries = _splitLogEntries(content);
    final results = <FileLogEntry>[];

    for (var i = 0; i < rawEntries.length; i++) {
      try {
        results.add(_parseLogEntry(rawEntries[i], i));
      } catch (e) {
        // 解析失败时创建一条最小记录
        results.add(FileLogEntry(
          timestamp: rawEntries[i].timestamp,
          method: 'UNKNOWN',
          path: '解析失败: $e',
          index: i,
        ));
      }
    }

    return results;
  }

  // ==================== 日志分割 ====================

  /// 按分隔线切分日志文本为独立条目
  static List<_RawEntry> _splitLogEntries(String content) {
    final entries = <_RawEntry>[];
    final lines = content.split('\n');
    String? currentTime;
    final currentLines = <String>[];

    for (final line in lines) {
      final m = _separatorRe.firstMatch(line);
      if (m != null) {
        if (currentTime != null && currentLines.isNotEmpty) {
          entries.add(_RawEntry(currentTime, List.of(currentLines)));
        }
        currentTime = m.group(1)!;
        currentLines.clear();
      } else {
        currentLines.add(line);
      }
    }

    // 最后一条
    if (currentTime != null && currentLines.isNotEmpty) {
      entries.add(_RawEntry(currentTime, List.of(currentLines)));
    }

    return entries;
  }

  // ==================== 单条日志解析 ====================

  static FileLogEntry _parseLogEntry(_RawEntry raw, int index) {
    final (meta, bodyStart) = _parseMetadata(raw.lines);
    final (reqRaw, respRaw) = _splitRequestResponse(raw.lines, bodyStart);

    return FileLogEntry(
      timestamp: raw.timestamp,
      method: meta['method'] as String? ?? 'UNKNOWN',
      path: meta['path'] as String? ?? '',
      model: meta['model'] as String?,
      forwardTo: meta['forward_to'] as String?,
      durationMs: meta['duration_ms'] as int?,
      statusCode: meta['status_code'] as int?,
      request: reqRaw.isNotEmpty ? _parseRequestBody(reqRaw) : null,
      response: respRaw.isNotEmpty
          ? _parseSseResponse(respRaw, meta['path'] as String? ?? '')
          : null,
      index: index,
    );
  }

  // ==================== 元数据解析 ====================

  /// 返回 (metadata, bodyStartIndex)
  static (Map<String, Object>, int) _parseMetadata(List<String> lines) {
    final meta = <String, Object>{};
    var idx = 0;

    while (idx < lines.length) {
      final line = lines[idx];

      if (line.trim() == '[Request Body]') {
        idx++;
        break;
      }

      RegExpMatch? m;
      if ((m = _requestRe.firstMatch(line)) != null) {
        meta['method'] = m!.group(1)!;
        meta['path'] = m.group(2)!;
      } else if ((m = _modelRe.firstMatch(line)) != null) {
        meta['model'] = m!.group(1)!;
      } else if ((m = _forwardToRe.firstMatch(line)) != null) {
        meta['forward_to'] = m!.group(1)!;
      } else if ((m = _durationRe.firstMatch(line)) != null) {
        meta['duration_ms'] = int.parse(m!.group(1)!);
      } else if ((m = _statusRe.firstMatch(line)) != null) {
        meta['status_code'] = int.parse(m!.group(1)!);
      }

      idx++;
    }

    return (meta, idx);
  }

  // ==================== 请求体 / 响应体分割 ====================

  static (String, String) _splitRequestResponse(
    List<String> lines,
    int bodyStart,
  ) {
    int? responseMarker;
    for (var i = bodyStart; i < lines.length; i++) {
      if (lines[i].trim() == '[Response Body]') {
        responseMarker = i;
        break;
      }
    }

    String reqBody;
    String respBody;
    if (responseMarker != null) {
      reqBody = lines.sublist(bodyStart, responseMarker).join('\n');
      respBody = lines.sublist(responseMarker + 1).join('\n');
    } else {
      reqBody = lines.sublist(bodyStart).join('\n');
      respBody = '';
    }

    return (reqBody.trim(), respBody.trim());
  }

  // ==================== 请求体解析 ====================

  static FileLogRequest? _parseRequestBody(String raw) {
    if (raw.isEmpty) return null;

    Map<String, dynamic> body;
    try {
      body = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    final messages = <FileLogMessage>[];
    if (body['messages'] is List) {
      for (final msg in body['messages'] as List) {
        if (msg is Map<String, dynamic>) {
          messages.add(_simplifyMessage(msg));
        }
      }
    }

    // 提取 system prompt
    final (systemPreview, systemFull) = _extractSystem(body['system']);

    // 提取 tools 定义列表
    final tools = _extractToolDefs(body['tools']);

    final extras = Map<String, dynamic>.from(body)
      ..remove('model')
      ..remove('stream')
      ..remove('messages')
      ..remove('system')
      ..remove('tools');

    return FileLogRequest(
      model: body['model'] as String?,
      stream: body['stream'] as bool?,
      messages: messages,
      systemPreview: systemPreview,
      systemFull: systemFull,
      tools: tools,
      otherParams: extras.isNotEmpty ? extras : null,
    );
  }

  /// 提取 system prompt，返回 (preview, full)
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

    if (full == null) return (null, null);
    return (_truncate(full, 500), full);
  }

  /// 提取工具定义列表（兼容 Anthropic 和 OpenAI 两种格式）
  static List<FileLogToolDef>? _extractToolDefs(dynamic tools) {
    if (tools is! List || tools.isEmpty) return null;

    final result = <FileLogToolDef>[];
    for (final tool in tools) {
      if (tool is! Map<String, dynamic>) continue;

      // OpenAI 格式：{ "type": "function", "function": { "name", "description", "parameters" } }
      // Anthropic 格式：{ "name", "description", "input_schema" }
      final funcObj = tool['function'] as Map<String, dynamic>?;
      final source = funcObj ?? tool;

      final name = source['name'] as String? ?? '';
      final desc = source['description'] as String?;
      final inputSchema = (source['input_schema'] ?? source['parameters'])
          as Map<String, dynamic>?;
      result.add(FileLogToolDef(
        name: name,
        descriptionPreview: desc != null ? _truncate(desc, 100) : null,
        description: desc,
        inputSchema: inputSchema,
      ));
    }

    return result.isNotEmpty ? result : null;
  }

  static FileLogMessage _simplifyMessage(Map<String, dynamic> msg) {
    final role = msg['role'] as String? ?? 'unknown';
    final content = msg['content'];

    if (content is String) {
      final truncated = _truncate(content, 500);
      return FileLogMessage(
        role: role,
        text: truncated,
        textFull: truncated != content ? content : null,
      );
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
            final inputJson = jsonEncode(item['input'] ?? {});
            final inputTruncated = _truncate(inputJson, 200);
            toolUses.add(FileLogToolUse(
              name: item['name'] as String? ?? '',
              id: item['id'] as String? ?? '',
              inputPreview: inputTruncated,
              inputFull: inputJson,
            ));
          case 'tool_result':
            final c = item['content'];
            final contentStr = c is String ? c : jsonEncode(c ?? '');
            final contentTruncated = _truncate(contentStr, 200);
            toolResults.add(FileLogToolResult(
              toolUseId: item['tool_use_id'] as String? ?? '',
              contentPreview: contentTruncated,
              contentFull: contentStr,
            ));
          case 'image':
            textParts.add('[image]');
        }
      }

      final fullText = textParts.join('\n');
      final truncatedText = _truncate(fullText, 500);
      return FileLogMessage(
        role: role,
        text: truncatedText,
        textFull: truncatedText != fullText ? fullText : null,
        toolUses: toolUses.isNotEmpty ? toolUses : null,
        toolResults: toolResults.isNotEmpty ? toolResults : null,
      );
    }

    return FileLogMessage(
      role: role,
      text: content != null ? _truncate(content.toString(), 500) : null,
      textFull: content != null && content.toString().length > 500
          ? content.toString()
          : null,
    );
  }

  static String _truncate(String s, int maxLen) {
    if (s.length <= maxLen) return s;
    return '${s.substring(0, maxLen)}... (${s.length} chars total)';
  }

  // ==================== SSE 响应解析 ====================

  static FileLogResponse _parseSseResponse(
    String raw,
    String endpointPath,
  ) {
    if (raw.isEmpty) {
      return const FileLogResponse(type: 'empty');
    }

    // 非 SSE：尝试直接解析为 JSON
    if (!raw.startsWith('event:') && !raw.startsWith('data:')) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        return _jsonToResponse('json', data);
      } catch (_) {
        return const FileLogResponse(type: 'raw');
      }
    }

    final events = _parseSseEvents(raw);
    if (events.isEmpty) {
      return const FileLogResponse(type: 'raw');
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

    // 兜底：按路径判断
    if (endpointPath.endsWith('/v1/messages')) {
      return _assembleAnthropicSse(events);
    }
    if (endpointPath.endsWith('/v1/chat/completions')) {
      return _assembleOpenaiSse(events);
    }

    return _assembleAnthropicSse(events);
  }

  /// 将非流式 JSON 响应转为 FileLogResponse
  static FileLogResponse _jsonToResponse(
    String type,
    Map<String, dynamic> data,
  ) {
    // 尝试提取 Anthropic 格式的字段
    final contentList = data['content'] as List<dynamic>?;
    List<FileLogContentBlock>? blocks;
    if (contentList != null) {
      blocks = contentList
          .whereType<Map<String, dynamic>>()
          .map((c) => FileLogContentBlock.fromJson(c))
          .toList();
    }

    return FileLogResponse(
      type: type,
      model: data['model'] as String?,
      stopReason:
          data['stop_reason'] as String? ?? data['finish_reason'] as String?,
      usage: data['usage'] is Map<String, dynamic>
          ? FileLogUsage.fromJson(data['usage'] as Map<String, dynamic>)
          : null,
      content: blocks,
      id: data['id'] as String?,
    );
  }

  // ==================== SSE 事件解析 ====================

  static List<Map<String, dynamic>> _parseSseEvents(String raw) {
    final events = <Map<String, dynamic>>[];
    String? currentEvent;
    final dataLines = <String>[];

    for (final line in raw.split('\n')) {
      final trimmed = line.trimRight();

      if (trimmed.startsWith('event:')) {
        // 保存上一个事件
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

    // 处理末尾
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

  static FileLogResponse _assembleAnthropicSse(
    List<Map<String, dynamic>> events,
  ) {
    String? model;
    String? stopReason;
    String? id;
    Map<String, dynamic>? usage;

    // 按 index 收集 content blocks
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
    final contentBlocks = <FileLogContentBlock>[];

    for (final idx in sortedKeys) {
      final block = blocks[idx]!;
      final type = block['type'] as String;

      if (type == 'tool_use') {
        // 尝试解析拼接的 JSON
        final inputStr = block['input_json'] as String? ?? '';
        Map<String, dynamic>? input;
        try {
          input = jsonDecode(inputStr) as Map<String, dynamic>;
        } catch (_) {
          // input 保持 null
        }
        contentBlocks.add(FileLogContentBlock(
          type: 'tool_use',
          id: block['id'] as String?,
          name: block['name'] as String?,
          input: input,
        ));
      } else {
        // text 或 thinking
        contentBlocks.add(FileLogContentBlock(
          type: type,
          text: block[type == 'thinking' ? 'thinking' : 'text'] as String?,
        ));
      }
    }

    return FileLogResponse(
      type: 'anthropic_sse',
      model: model,
      stopReason: stopReason,
      usage: usage != null ? FileLogUsage.fromJson(usage) : null,
      content: contentBlocks,
      id: id,
    );
  }

  // ==================== OpenAI SSE 拼接 ====================

  static FileLogResponse _assembleOpenaiSse(
    List<Map<String, dynamic>> events,
  ) {
    String? model;
    String? finishReason;
    Map<String, dynamic>? usage;
    final contentBuf = StringBuffer();
    final reasoningBuf = StringBuffer();

    // 按 index 收集 tool_calls
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

        // 文本内容
        final c = delta['content'] as String?;
        if (c != null && c.isNotEmpty) contentBuf.write(c);

        // 推理内容
        final rc = delta['reasoning_content'] as String?;
        if (rc != null && rc.isNotEmpty) reasoningBuf.write(rc);

        // 工具调用
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

    // 将 tool_calls 转为 content blocks（复用 FileLogContentBlock）
    final contentBlocks = <FileLogContentBlock>[];

    // 文本内容块
    final text = contentBuf.toString();
    if (text.isNotEmpty) {
      contentBlocks.add(FileLogContentBlock(type: 'text', text: text));
    }

    // 推理内容块
    final reasoning = reasoningBuf.toString();
    if (reasoning.isNotEmpty) {
      contentBlocks.add(
        FileLogContentBlock(type: 'thinking', text: reasoning),
      );
    }

    // 工具调用块
    final sortedTcKeys = toolCallsMap.keys.toList()..sort();
    for (final idx in sortedTcKeys) {
      final tc = toolCallsMap[idx]!;
      final fn = tc['function'] as Map<String, dynamic>;
      Map<String, dynamic>? parsedArgs;
      try {
        parsedArgs =
            jsonDecode(fn['arguments'] as String) as Map<String, dynamic>;
      } catch (_) {
        // 保持 null
      }
      contentBlocks.add(FileLogContentBlock(
        type: 'tool_use',
        id: tc['id'] as String?,
        name: fn['name'] as String?,
        input: parsedArgs,
      ));
    }

    return FileLogResponse(
      type: 'openai_sse',
      model: model,
      stopReason: finishReason,
      usage: usage != null ? FileLogUsage.fromJson(usage) : null,
      content: contentBlocks.isNotEmpty ? contentBlocks : null,
    );
  }
}

/// 原始日志条目（分割后、解析前）
class _RawEntry {
  final String timestamp;
  final List<String> lines;

  const _RawEntry(this.timestamp, this.lines);
}
