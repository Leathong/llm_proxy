import 'dart:convert';
import 'dart:io';

/// 转发结果
class ForwardResult {
  final int statusCode;
  final String? responseBody;
  final String? error;

  const ForwardResult({
    required this.statusCode,
    this.responseBody,
    this.error,
  });

  bool get isError => statusCode >= 400 || error != null;
}

/// 负责将客户端请求转发到上游 API，并将响应回写给客户端
class RequestForwarder {
  /// 转发请求到目标 URL，返回转发结果
  Future<ForwardResult> forward({
    required HttpRequest clientRequest,
    required String targetUrl,
    required List<int> bodyBytes,
    required String? endpointApiKey,
  }) async {
    final uri = Uri.parse(targetUrl);
    final client = HttpClient();

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

      final targetResponse = await targetRequest.close();

      // 回写状态码和 header
      clientRequest.response.statusCode = targetResponse.statusCode;
      targetResponse.headers.forEach((name, values) {
        if (name.toLowerCase() == 'transfer-encoding') return;
        for (var value in values) {
          clientRequest.response.headers.add(name, value);
        }
      });

      // 读取并回写响应体
      final responseBytes = await targetResponse.toList();
      final allBytes = responseBytes.expand((b) => b).toList();
      final responseBodyStr = utf8.decode(allBytes);

      clientRequest.response.add(allBytes);
      await clientRequest.response.close();

      return ForwardResult(
        statusCode: targetResponse.statusCode,
        responseBody: responseBodyStr,
      );
    } catch (e) {
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
