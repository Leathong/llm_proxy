import 'package:llm_proxy/features/rules/domain/entities/rule.dart';

/// 负责改写请求体：替换 model、注入 thinking/reasoning 参数、替换 system prompt
class RequestTransformer {
  /// 将请求体中的 model 替换为目标 model，并根据规则和 URL 参数注入 thinking 配置
  /// 如果提供了 [systemPromptContent]，会替换请求体中的 system prompt
  Map<String, dynamic> transform(
    Map<String, dynamic> bodyJson, {
    required Rule rule,
    required Uri requestUri,
    String? systemPromptContent,
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
        bodyJson['enable_thinking'] = true;
        onLog?.call('从 URL 参数注入 thinking: enabled, reasoning_effort: $thinkingValue');
        return bodyJson;
      }
    }

    // 使用规则中的 thinking 配置
    if (rule.thinkingMode.isNotEmpty) {
      bodyJson['thinking'] = {'type': rule.thinkingMode};
      final enableThinking = rule.thinkingMode == "enabled";
      bodyJson['extra_body'] = {'enable_thinking': enableThinking};
      bodyJson['enable_thinking'] = enableThinking;
      onLog?.call('注入 thinking: ${rule.thinkingMode}');
    }
    if (rule.thinkingMode == 'enabled' && rule.reasoningEffort.isNotEmpty) {
      bodyJson['reasoning_effort'] = rule.reasoningEffort;
      onLog?.call('注入 reasoning_effort: ${rule.reasoningEffort}');
    }

    // 替换 system prompt
    if (systemPromptContent != null && systemPromptContent.isNotEmpty) {
      _replaceSystemPrompt(bodyJson, systemPromptContent, onLog: onLog);
    }

    bodyJson['stream_options'] = {'include_usage': true};

    return bodyJson;
  }

  /// 替换请求体中的 system prompt，兼容 OpenAI 和 Anthropic 两种格式
  void _replaceSystemPrompt(
    Map<String, dynamic> bodyJson,
    String newContent, {
    void Function(String message)? onLog,
  }) {
    // Anthropic 格式: 顶层 system 字段
    if (bodyJson.containsKey('system')) {
      final system = bodyJson['system'];
      if (system is String) {
        bodyJson['system'] = newContent;
        onLog?.call('已替换 Anthropic 格式 system prompt (string)');
      } else if (system is List) {
        // content block 列表，替换第一个 text block 的内容
        bool replaced = false;
        for (final block in system) {
          if (block is Map<String, dynamic> && block['type'] == 'text') {
            block['text'] = newContent;
            replaced = true;
            break;
          }
        }
        if (!replaced) {
          // 没有 text block，插入一个
          system.insert(0, {'type': 'text', 'text': newContent});
        }
        onLog?.call('已替换 Anthropic 格式 system prompt (content blocks)');
      } else {
        // 未知格式，直接覆盖
        bodyJson['system'] = newContent;
        onLog?.call('已替换 system prompt (fallback)');
      }
      return;
    }


    // OpenAI 格式: messages 数组中 role 为 system 的 message
    final messages = bodyJson['messages'];
    if (messages is List) {
      for (final msg in messages) {
        if (msg is Map<String, dynamic> && msg['role'] == 'system') {
          msg['content'] = newContent;
          break;
        }
      }
      onLog?.call('已替换 OpenAI 格式 system prompt');
      return;
    }

    // 既没有 messages 也没有 system 字段，不做处理
    onLog?.call('请求体中没有 system prompt，跳过替换');
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
