import 'dart:convert';

import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';
import 'package:llm_proxy/features/logs/domain/services/sse_parser.dart';

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
    final result = SseParser.parseResponse(rawBody, endpointPath);
    if (result.type == 'empty' || result.type == 'raw') {
      return {'type': result.type};
    }
    return {
      'type': result.type,
      'model': result.model,
      'stop_reason': result.stopReason,
      'usage': result.usage,
      'content': result.content,
      'id': result.id,
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
