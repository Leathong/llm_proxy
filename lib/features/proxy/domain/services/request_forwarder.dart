import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
  /// 按 host 复用的 HttpClient 连接池
  final Map<String, HttpClient> _clientPool = {};

  HttpClient _getClient(String host) {
    if (_clientPool.containsKey(host)) {
      return _clientPool[host]!;
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    _clientPool[host] = client;
    return client;
  }

  /// 不应透传给客户端的上游响应头：
  /// - hop-by-hop 头（connection 等）按 HTTP 规范本就不能转发
  /// - content-length/content-encoding：HttpClient 默认 autoUncompress 解压 gzip，
  ///   且 thinking 转写会改写 body，回传的字节与上游头部声明不再一致。
  ///   若透传 content-length，写入字节多于声明时 SDK 会丢弃数据并报错，
  ///   少于声明时 close 报错——两者都会导致客户端接收不完整
  static const _skipResponseHeaders = {
    'transfer-encoding',
    'connection',
    'keep-alive',
    'proxy-authenticate',
    'proxy-authorization',
    'te',
    'trailer',
    'upgrade',
    'content-length',
    'content-encoding',
  };

  void dispose() {
    for (final client in _clientPool.values) {
      client.close(force: true);
    }
    _clientPool.clear();
  }

  /// 转发请求到目标 URL，返回转发结果
  /// 当客户端断开连接时，会立即取消上游请求以节省资源
  /// SSE 流式响应会逐块透传给客户端，不再缓冲全部数据
  /// [convertThinkingToContent] 为 true 时将 thinking/reasoning 内容转写为普通 content
  /// [onFirstByte] 收到首个响应 chunk 时回调，参数为首字节耗时（毫秒）
  Future<ForwardResult> forward({
    required HttpRequest clientRequest,
    required String targetUrl,
    required List<int> bodyBytes,
    required String? endpointApiKey,
    bool convertThinkingToContent = false,
    void Function(int firstByteMs)? onFirstByte,
  }) async {
    final uri = Uri.parse(targetUrl);
    final client = _getClient(uri.host);
    var clientDisconnected = false;

    // 监听客户端断开：response.done 完成时说明客户端已断开或响应已关闭
    // 注意：不能用 catchError，因为客户端断开时 done 是正常完成而非报错
    clientRequest.response.done.whenComplete(() {
      clientDisconnected = true;
    });

    // 上游响应状态码 / 是否已开始向客户端回写 body（用于中途异常的区分处理）
    var upstreamStatusCode = HttpStatus.badGateway;
    var bodyWriteStarted = false;

    try {
      final targetRequest = await client.postUrl(uri);

      // 复制原始 header（排除 host/content-length/authorization）
      clientRequest.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        if (lower == 'host' ||
            lower == 'content-length' ||
            lower == 'authorization' ||
            // 不透传客户端的 accept-encoding：由 HttpClient 自己声明 gzip，
            // 避免上游选择 br/deflate 等 HttpClient 不会自动解压的编码
            lower == 'accept-encoding') {
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
      upstreamStatusCode = targetResponse.statusCode;

      // 客户端已断开，无需回写
      if (clientDisconnected) {
        return ForwardResult(
          statusCode: targetResponse.statusCode,
          clientDisconnected: true,
        );
      }

      // 回写状态码和 header（跳过与回传 body 不一致或 hop-by-hop 的头）
      clientRequest.response.statusCode = targetResponse.statusCode;
      targetResponse.headers.forEach((name, values) {
        if (_skipResponseHeaders.contains(name.toLowerCase())) return;
        for (var value in values) {
          clientRequest.response.headers.add(name, value);
        }
      });

      // 允许跨域访问
      clientRequest.response.headers.set('Access-Control-Allow-Origin', '*');
      clientRequest.response.headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, PATCH, OPTIONS');
      clientRequest.response.headers.set('Access-Control-Allow-Headers', '*');
      clientRequest.response.headers.set('Access-Control-Expose-Headers', '*');

      // 流式转发：逐块读取上游响应并立即回写给客户端
      final responseBodyBuf = StringBuffer();
      int? firstByteMs;

      void recordFirstByte() {
        if (firstByteMs != null) return;
        final ms = DateTime.now().difference(forwardStartTime).inMilliseconds;
        firstByteMs = ms;
        onFirstByte?.call(ms);
      }

      if (!convertThinkingToContent) {
        // 直通模式：转发原始字节，避免多字节 UTF-8 字符跨 chunk
        // 被逐块 decode 成替换符导致内容损坏；完整字节留给日志统一解码
        final bodyBytes = BytesBuilder(copy: false);
        await for (final chunk in targetResponse) {
          if (clientDisconnected) break;
          recordFirstByte();
          bodyBytes.add(chunk);
          clientRequest.response.add(chunk);
          bodyWriteStarted = true;
          // 立即回刷，防止小 chunk 积压在缓冲区，客户端长时间收不到数据
          await clientRequest.response.flush();
        }
        responseBodyBuf.write(
          utf8.decode(bodyBytes.takeBytes(), allowMalformed: true),
        );
      } else {
        // 转写模式：有状态 UTF-8 解码 + 跨 chunk 行缓冲，
        // 保证跨块的字符和 SSE 行都能被正确转写
        final decodedParts = <String>[];
        // 注意：不能用 StringConversionSink.withCallback，
        // 它会累积到 close 才回调一次，流式场景下拿不到中间数据
        final utf8Sink = const Utf8Decoder(allowMalformed: true)
            .startChunkedConversion(_ImmediateStringSink(decodedParts.add));
        var pendingLine = '';

        await for (final chunk in targetResponse) {
          if (clientDisconnected) break;
          recordFirstByte();
          utf8Sink.add(chunk);
          if (decodedParts.isEmpty) continue;
          pendingLine += decodedParts.join();
          decodedParts.clear();

          final lines = pendingLine.split('\n');
          pendingLine = lines.removeLast(); // 末段可能是不完整的行，留待下次
          if (lines.isEmpty) continue;

          final out = '${lines.map(_convertSseLine).join('\n')}\n';
          responseBodyBuf.write(out);
          clientRequest.response.add(utf8.encode(out));
          bodyWriteStarted = true;
          await clientRequest.response.flush();
        }
        utf8Sink.close();
        if (decodedParts.isNotEmpty) {
          pendingLine += decodedParts.join();
          decodedParts.clear();
        }
        if (pendingLine.isNotEmpty) {
          final out = _convertSseLine(pendingLine);
          responseBodyBuf.write(out);
          if (!clientDisconnected) {
            clientRequest.response.add(utf8.encode(out));
            bodyWriteStarted = true;
            await clientRequest.response.flush();
          }
        }
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

      // 响应已开始流式回写（headers 已发出），无法再改状态码。
      // 以 SSE error 事件显式告知客户端出错了再结束，
      // 避免客户端把被截断的流当成正常完成
      if (bodyWriteStarted) {
        try {
          clientRequest.response.add(utf8.encode(
            'data: ${jsonEncode({
              'error': {
                'message': 'Upstream error: $e',
                'type': 'proxy_error',
              }
            })}\n\n',
          ));
          await clientRequest.response.flush();
        } catch (_) {}
        try { await clientRequest.response.close(); } catch (_) {}

        return ForwardResult(
          statusCode: upstreamStatusCode,
          error: e.toString(),
        );
      }

      // 尚未回写任何内容，可以完整返回 Bad Gateway
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
        try { await clientRequest.response.close(); } catch (_) {}
      }

      return ForwardResult(
        statusCode: HttpStatus.badGateway,
        responseBody: errorResp,
        error: e.toString(),
      );
    } finally {
      // 确保客户端响应被关闭，防止客户端一直等待
      if (!clientDisconnected) {
        try { await clientRequest.response.close(); } catch (_) {}
      }
    }
  }

  /// 将单行 SSE data 中的 thinking/reasoning 内容转写为普通 content
  /// 支持 OpenAI（delta.reasoning_content → delta.content）和
  /// Anthropic（thinking/thinking_delta → text/text_delta）两种格式
  /// [line] 必须是不含换行符的完整行（跨 chunk 行由调用方缓冲拼接）
  String _convertSseLine(String line) {
    if (!line.startsWith('data: ')) return line;

    final dataStr = line.substring(6).trim();
    if (dataStr == '[DONE]') return line;

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
        return 'data: ${jsonEncode(json)}';
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
        return 'data: ${jsonEncode(json)}';
      }

      // Anthropic 格式：content_block_delta type:thinking_delta → type:text_delta
      final deltaBlock = json['delta'];
      if (deltaBlock is Map<String, dynamic> && deltaBlock['type'] == 'thinking_delta') {
        deltaBlock['type'] = 'text_delta';
        if (deltaBlock.containsKey('thinking')) {
          deltaBlock['text'] = deltaBlock['thinking'];
          deltaBlock.remove('thinking');
        }
        return 'data: ${jsonEncode(json)}';
      }

      return line;
    } catch (_) {
      // JSON 解析失败，原样保留
      return line;
    }
  }
}

/// 立即回调的 String Sink：每解码出一段字符串就触发回调
/// （区别于 StringConversionSink.withCallback 会累积到 close 才回调）
class _ImmediateStringSink implements Sink<String> {
  final void Function(String chunk) _onChunk;

  _ImmediateStringSink(this._onChunk);

  @override
  void add(String data) => _onChunk(data);

  @override
  void close() {}
}
