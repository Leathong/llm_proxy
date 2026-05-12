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
  Future<ForwardResult> forward({
    required HttpRequest clientRequest,
    required String targetUrl,
    required List<int> bodyBytes,
    required String? endpointApiKey,
  }) async {
    final uri = Uri.parse(targetUrl);
    final client = HttpClient();
    var clientDisconnected = false;

    // 监听客户端断开，立即关闭上游连接
    clientRequest.response.done.catchError((_) {
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

        final chunkStr = utf8.decode(chunk, allowMalformed: true);
        responseBodyBuf.write(chunkStr);
        clientRequest.response.add(chunk);
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
      } catch (_) {}

      return ForwardResult(
        statusCode: HttpStatus.badGateway,
        responseBody: errorResp,
        error: e.toString(),
      );
    } finally {
      client.close();
    }
  }
}
