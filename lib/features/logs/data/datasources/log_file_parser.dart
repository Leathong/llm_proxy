import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';
import 'package:llm_proxy/features/logs/domain/services/sse_parser.dart';

/// 将 .log 文本文件解析为结构化的 [FileLogEntry] 列表。
/// 支持 Anthropic 和 OpenAI 的 SSE 流式响应拼接。
class LogFileParser {
  // 匹配分隔线: -------------------- 2026-05-01 10:14:53.123 --------------------
  // 兼容旧格式（无毫秒）
  static final _separatorRe = RegExp(
    r'^-{20}\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}(?:\.\d{3})?)\s+-{20}$',
  );

  // 元数据行正则
  static final _requestRe = RegExp(r'^\[REQUEST\]\s+(\S+)\s+(.+)$');
  static final _modelRe = RegExp(r'^\[Model\]\s+(.+)$');
  static final _forwardToRe = RegExp(r'^\[Forward To\]\s+(.+)$');
  static final _durationRe = RegExp(r'^\[Duration\]\s+(\d+)ms$');
  static final _firstByteRe = RegExp(r'^\[First Byte\]\s+(\d+)ms$');
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
      firstByteMs: meta['first_byte_ms'] as int?,
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
      } else if ((m = _firstByteRe.firstMatch(line)) != null) {
        meta['first_byte_ms'] = int.parse(m!.group(1)!);
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

    final (systemPreview, systemFull) = _extractSystem(body['system']);

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
    final result = SseParser.parseResponse(raw, endpointPath);
    if (result.type == 'empty') {
      return const FileLogResponse(type: 'empty');
    }
    if (result.type == 'raw') {
      return const FileLogResponse(type: 'raw');
    }

    FileLogUsage? usage;
    if (result.usage != null) {
      usage = FileLogUsage.fromJson(result.usage!);
    }

    List<FileLogContentBlock>? content;
    if (result.content != null) {
      content = result.content!
          .map((c) => FileLogContentBlock.fromJson(c))
          .toList();
    }

    return FileLogResponse(
      type: result.type,
      model: result.model,
      stopReason: result.stopReason,
      usage: usage,
      content: content,
      id: result.id,
    );
  }
}

/// 原始日志条目（分割后、解析前）
class _RawEntry {
  final String timestamp;
  final List<String> lines;

  const _RawEntry(this.timestamp, this.lines);
}
