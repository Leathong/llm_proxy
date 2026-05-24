import 'package:llm_proxy/features/logs/data/datasources/request_body_parser.dart';
import 'package:llm_proxy/features/logs/domain/services/sse_parser.dart';

/// 代理请求/响应解析器，可在 isolate 中执行。
/// 负责将原始 JSON/SSE 字符串解析为结构化 Map。
///
/// 请求体解析委托给 [RequestBodyParser]，响应体解析委托给 [SseParser]。
class LogResponseParser {
  /// 解析请求体 JSON，返回预解析的结构化 Map
  static Map<String, dynamic> parseRequestBody(String rawJson) {
    return RequestBodyParser.parseRequestBodyToMap(rawJson);
  }

  /// 解析响应体，返回预解析的结构化 Map
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
}
