import 'dart:convert';

import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';

/// 请求体/响应体解析工具，提取 LogFileParser 和 LogResponseParser 的公共逻辑。
class RequestBodyParser {
  /// 简化消息对象，返回 [FileLogMessage]（带 truncate）
  static FileLogMessage simplifyMessage(
    Map<String, dynamic> msg, {
    bool truncate = true,
  }) {
    final role = msg['role'] as String? ?? 'unknown';
    final content = msg['content'];

    if (content is String) {
      if (truncate) {
        final truncated = _truncate(content, 500);
        return FileLogMessage(
          role: role,
          text: truncated,
          textFull: truncated != content ? content : null,
        );
      }
      return FileLogMessage(role: role, text: content);
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
            toolUses.add(FileLogToolUse(
              name: item['name'] as String? ?? '',
              id: item['id'] as String? ?? '',
              inputPreview: truncate ? _truncate(inputJson, 200) : null,
              inputFull: inputJson,
            ));
          case 'tool_result':
            final c = item['content'];
            final contentStr = c is String ? c : jsonEncode(c ?? '');
            toolResults.add(FileLogToolResult(
              toolUseId: item['tool_use_id'] as String? ?? '',
              contentPreview: truncate ? _truncate(contentStr, 200) : null,
              contentFull: contentStr,
            ));
          case 'image':
            textParts.add('[image]');
        }
      }

      final fullText = textParts.join('\n');
      if (truncate) {
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
        text: fullText.isNotEmpty ? fullText : null,
        toolUses: toolUses.isNotEmpty ? toolUses : null,
        toolResults: toolResults.isNotEmpty ? toolResults : null,
      );
    }

    if (truncate) {
      return FileLogMessage(
        role: role,
        text: content != null ? _truncate(content.toString(), 500) : null,
        textFull: content != null && content.toString().length > 500
            ? content.toString()
            : null,
      );
    }
    return FileLogMessage(
      role: role,
      text: content?.toString(),
    );
  }

  /// 提取 system prompt，返回 (preview, full)
  static (String?, String?) extractSystem(dynamic system) {
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
  static List<FileLogToolDef>? extractToolDefs(dynamic tools) {
    if (tools is! List || tools.isEmpty) return null;

    final result = <FileLogToolDef>[];
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
        descriptionPreview: desc != null ? _truncate(desc, 100) : null,
        description: desc,
        inputSchema: inputSchema,
      ));
    }

    return result.isNotEmpty ? result : null;
  }

  /// 解析请求体 JSON，返回 [FileLogRequest]
  static FileLogRequest? parseRequestBody(String raw) {
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
          messages.add(simplifyMessage(msg));
        }
      }
    }

    final (systemPreview, systemFull) = extractSystem(body['system']);

    final tools = extractToolDefs(body['tools']);

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

  /// 解析请求体 JSON，返回 Map（用于跨 isolate 传递）
  static Map<String, dynamic> parseRequestBodyToMap(String rawJson) {
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
          messages.add(simplifyMessage(msg, truncate: false).toJson());
        }
      }
    }

    final (_, systemFull) = extractSystem(body['system']);

    final tools = extractToolDefs(body['tools']);

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
      'tools': tools?.map((t) => t.toJson()).toList(),
      'other_params': extras.isNotEmpty ? extras : null,
    };
  }

  static String _truncate(String s, int maxLen) {
    if (s.length <= maxLen) return s;
    return '${s.substring(0, maxLen)}... (${s.length} chars total)';
  }
}
