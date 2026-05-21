import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 转发结果
class ForwardResult {
  final int statusCode;
  final String? responseBody;
  final String? error;
  final bool clientDisconnected;
  /// 首字节耗时（毫秒），从请求发出到收到第一个响应 chunk 的时间
  final int? firstByteMs;

  const ForwardResult({
    required this.statusCode,
    this.responseBody,
    this.error,
    this.clientDisconnected = false,
    this.firstByteMs,
  });

  bool get isError => statusCode >= 400 || error != null;
}

/// 负责将客户端请求转发到上游 API，并将响应回写给客户端
class RequestForwarder {
  /// 转发请求到目标 URL，返回转发结果
  /// 当客户端断开连接时，会立即取消上游请求以节省资源
  /// SSE 流式响应会逐块透传给客户端，不再缓冲全部数据
  /// [convertThinkingToContent] 为 true 时将 thinking/reasoning 内容转写为普通 content
  Future<ForwardResult> forward({
    required HttpRequest clientRequest,
    required String targetUrl,
    required List<int> bodyBytes,
    required String? endpointApiKey,
    bool convertThinkingToContent = false,
  }) async {
    final uri = Uri.parse(targetUrl);
    final client = HttpClient();
    var clientDisconnected = false;

    // 监听客户端断开：response.done 完成时说明客户端已断开或响应已关闭
    // 注意：不能用 catchError，因为客户端断开时 done 是正常完成而非报错
    clientRequest.response.done.whenComplete(() {
      clientDisconnected = true;
      client.close(force: true);
    });

    try {
      final targetRequest = await client.postUrl(uri);

      // 复制原始 header（排除 host/content-length/authorization）
      clientRequest.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        if (lower == 'host' || lower == 'content-length' || lower == 'authorization') {
          return;
        }
        for (var value in values) {
          targetRequest.headers.add(name, value);
        }
      });

      // 设置 Authorization：endpoint apiKey 优先，否则透传原始 header
      if (endpointApiKey != null && endpointApiKey.isNotEmpty) {
        targetRequest.headers.add('Authorization', 'Bearer $endpointApiKey');
      } else {
        final authHeader = clientRequest.headers.value('authorization');
        if (authHeader != null) {
          targetRequest.headers.add('Authorization', authHeader);
        }
      }

      targetRequest.headers.contentLength = bodyBytes.length;
      targetRequest.headers.contentType = ContentType.json;
      targetRequest.add(bodyBytes);

      // 记录请求发出时间（用于 TTFB 计算）
      final forwardStartTime = DateTime.now();
      final targetResponse = await targetRequest.close();

      // 客户端已断开，无需回写
      if (clientDisconnected) {
        return ForwardResult(
          statusCode: targetResponse.statusCode,
          clientDisconnected: true,
        );
      }

      // 回写状态码和 header
      clientRequest.response.statusCode = targetResponse.statusCode;
      targetResponse.headers.forEach((name, values) {
        if (name.toLowerCase() == 'transfer-encoding') return;
        for (var value in values) {
          clientRequest.response.headers.add(name, value);
        }
      });

      // 流式转发：逐块读取上游响应并立即回写给客户端
      final responseBodyBuf = StringBuffer();
      int? firstByteMs;
      await for (final chunk in targetResponse) {
        if (clientDisconnected) break;

        // 记录首字节耗时
        firstByteMs ??= DateTime.now().difference(forwardStartTime).inMilliseconds;

        var chunkStr = utf8.decode(chunk, allowMalformed: true);
        if (convertThinkingToContent) {
          chunkStr = _convertThinkingChunk(chunkStr);
        }
        responseBodyBuf.write(chunkStr);
        clientRequest.response.add(utf8.encode(chunkStr));
      }

      if (clientDisconnected) {
        return ForwardResult(
          statusCode: targetResponse.statusCode,
          responseBody: responseBodyBuf.toString(),
          clientDisconnected: true,
          firstByteMs: firstByteMs,
        );
      }

      await clientRequest.response.close();

      return ForwardResult(
        statusCode: targetResponse.statusCode,
        responseBody: responseBodyBuf.toString(),
        firstByteMs: firstByteMs,
      );
    } catch (e) {
      // 客户端断开导致的异常，直接返回，不再尝试回写
      if (clientDisconnected) {
        return ForwardResult(
          statusCode: HttpStatus.clientClosedRequest,
          error: 'Client disconnected',
          clientDisconnected: true,
        );
      }

      // 转发失败，返回 Bad Gateway
      String? errorResp;
      try {
        errorResp = jsonEncode({
          'error': {
            'message': 'Bad Gateway: $e',
            'type': 'proxy_error',
          }
        });
        clientRequest.response.statusCode = HttpStatus.badGateway;
        clientRequest.response.write(errorResp);
        await clientRequest.response.close();
      } catch (_) {
        // 如果响应头已发送（流式场景中途异常），强制关闭
        try { await clientRequest.response.close(); } catch (_) {}
      }

      return ForwardResult(
        statusCode: HttpStatus.badGateway,
        responseBody: errorResp,
        error: e.toString(),
      );
    } finally {
      client.close();
      // 确保客户端响应被关闭，防止客户端一直等待
      if (!clientDisconnected) {
        try { await clientRequest.response.close(); } catch (_) {}
      }
    }
  }

  /// 将 SSE chunk 中的 thinking/reasoning 内容转写为普通 content
  /// 支持 OpenAI（delta.reasoning_content → delta.content）和
  /// Anthropic（thinking/thinking_delta → text/text_delta）两种格式
  String _convertThinkingChunk(String chunk) {
    final lines = chunk.split('\n');
    final converted = <String>[];

    for (final line in lines) {
      if (!line.startsWith('data: ')) {
        converted.add(line);
        continue;
      }

      final dataStr = line.substring(6).trim();
      if (dataStr == '[DONE]') {
        converted.add(line);
        continue;
      }

      try {
        final json = jsonDecode(dataStr) as Map<String, dynamic>;

        // OpenAI 格式：delta.reasoning_content → delta.content
        final delta = json['choices']?[0]?['delta'];
        if (delta is Map<String, dynamic> && delta.containsKey('reasoning_content')) {
          final reasoning = delta['reasoning_content'];
          delta.remove('reasoning_content');
          if (reasoning != null && reasoning.toString().isNotEmpty) {
            delta['content'] = reasoning;
          }
          converted.add('data: ${jsonEncode(json)}');
          continue;
        }

        // Anthropic 格式：content_block_start type:thinking → type:text
        final contentBlock = json['content_block'];
        if (contentBlock is Map<String, dynamic> && contentBlock['type'] == 'thinking') {
          contentBlock['type'] = 'text';
          // 将 thinking 字段重命名为 text
          if (contentBlock.containsKey('thinking')) {
            contentBlock['text'] = contentBlock['thinking'];
            contentBlock.remove('thinking');
          }
          converted.add('data: ${jsonEncode(json)}');
          continue;
        }

        // Anthropic 格式：content_block_delta type:thinking_delta → type:text_delta
        final deltaBlock = json['delta'];
        if (deltaBlock is Map<String, dynamic> && deltaBlock['type'] == 'thinking_delta') {
          deltaBlock['type'] = 'text_delta';
          if (deltaBlock.containsKey('thinking')) {
            deltaBlock['text'] = deltaBlock['thinking'];
            deltaBlock.remove('thinking');
          }
          converted.add('data: ${jsonEncode(json)}');
          continue;
        }

        converted.add(line);
      } catch (_) {
        // JSON 解析失败（如 chunk 被截断），原样保留
        converted.add(line);
      }
    }

    return converted.join('\n');
  }
}
