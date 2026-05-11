import 'package:llm_proxy/features/rules/domain/entities/rule.dart';

/// 负责改写请求体：替换 model、注入 thinking/reasoning 参数
class RequestTransformer {
  /// 将请求体中的 model 替换为目标 model，并根据规则和 URL 参数注入 thinking 配置
  Map<String, dynamic> transform(
    Map<String, dynamic> bodyJson, {
    required Rule rule,
    required Uri requestUri,
    void Function(String message)? onLog,
  }) {
    // 替换为目标 model
    bodyJson['model'] = rule.targetModelId;

    // URL 参数优先级高于规则配置
    final queryParams = requestUri.queryParameters;
    final thinkingValue = queryParams['thinking'];
    if (thinkingValue != null && thinkingValue.isNotEmpty) {
      if (thinkingValue == 'high' || thinkingValue == 'max') {
        bodyJson['thinking'] = {'type': 'enabled'};
        bodyJson['reasoning_effort'] = thinkingValue;
        bodyJson['extra_body'] = {'enable_thinking': true};
        onLog?.call('从 URL 参数注入 thinking: enabled, reasoning_effort: $thinkingValue');
        return bodyJson;
      }
    }

    // 使用规则中的 thinking 配置
    if (rule.thinkingMode.isNotEmpty) {
      bodyJson['thinking'] = {'type': rule.thinkingMode};
      bodyJson['extra_body'] = {'enable_thinking': rule.thinkingMode == "enabled" ? true : false};
      onLog?.call('注入 thinking: ${rule.thinkingMode}');
    }
    if (rule.thinkingMode == 'enabled' && rule.reasoningEffort.isNotEmpty) {
      bodyJson['reasoning_effort'] = rule.reasoningEffort;
      onLog?.call('注入 reasoning_effort: ${rule.reasoningEffort}');
    }

    return bodyJson;
  }

  /// 构建目标 URL：endpoint URL + 请求路径
  String buildTargetUrl(String endpointUrl, String path) {
    var targetUrl = endpointUrl;
    if (!targetUrl.endsWith(path)) {
      if (targetUrl.endsWith('/')) {
        targetUrl = targetUrl.substring(0, targetUrl.length - 1);
      }
      targetUrl += path;
    }
    return targetUrl;
  }
}
