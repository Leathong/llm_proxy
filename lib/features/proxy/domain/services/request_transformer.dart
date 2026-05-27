import 'package:llm_proxy/features/proxy/domain/services/provider_format.dart';
import 'package:llm_proxy/features/rules/domain/entities/rule.dart';

/// 负责改写请求体：替换 model、注入 thinking/reasoning 参数、替换 system prompt
class RequestTransformer {
  /// 根据 format 构建目标 URL
  String buildTargetUrl({
    required String baseUrl,
    required ProviderFormat format,
  }) {
    final path = format.path;
    var url = baseUrl;
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return '$url$path';
  }

  /// 根据 format 改写请求体
  /// - OpenAI 格式：替换 model、注入 thinking/reasoning_effort、替换 messages 中的 system prompt
  /// - Anthropic 格式：替换 model、注入 thinking、替换顶层 system 字段
  Map<String, dynamic> transform(
    Map<String, dynamic> bodyJson, {
    required Rule rule,
    required String targetModelId,
    required ProviderFormat format,
    String? systemPromptContent,
    void Function(String message)? onLog,
  }) {
    bodyJson['model'] = targetModelId;

    switch (format) {
      case ProviderFormat.openai:
        _transformOpenAI(bodyJson, rule, systemPromptContent, onLog);
      case ProviderFormat.anthropic:
        _transformAnthropic(bodyJson, rule, systemPromptContent, onLog);
    }

    // 合并自定义参数到请求体中（自定义参数优先级最高，覆盖已存在参数）
    _mergeCustomParams(bodyJson, rule, onLog);

    // 根据规则配置决定是否注入 stream 参数
    bodyJson['stream'] = rule.stream;
    if (rule.stream && rule.streamIncludeUsage) {
      bodyJson['stream_options'] = {'include_usage': true};
    }
    return bodyJson;
  }

  /// OpenAI 格式专用改写
  void _transformOpenAI(
    Map<String, dynamic> bodyJson,
    Rule rule,
    String? systemPromptContent,
    void Function(String message)? onLog,
  ) {
    // thinking 注入
    _injectThinking(bodyJson, rule, onLog);

    // system prompt 替换（OpenAI 方式：messages[role=system]）
    if (systemPromptContent != null && systemPromptContent.isNotEmpty) {
      final messages = bodyJson['messages'];
      if (messages is List) {
        for (final msg in messages) {
          if (msg is Map<String, dynamic> && msg['role'] == 'system') {
            msg['content'] = systemPromptContent;
            onLog?.call('已替换 OpenAI 格式 system prompt');
            break;
          }
        }
      }
    }
  }

  /// Anthropic 格式专用改写
  void _transformAnthropic(
    Map<String, dynamic> bodyJson,
    Rule rule,
    String? systemPromptContent,
    void Function(String message)? onLog,
  ) {
    // thinking 注入
    _injectThinking(bodyJson, rule, onLog);

    // system prompt 替换（Anthropic 方式：顶层 system 字段）
    if (systemPromptContent != null && systemPromptContent.isNotEmpty) {
      final system = bodyJson['system'];
      if (system is String) {
        bodyJson['system'] = systemPromptContent;
        onLog?.call('已替换 Anthropic 格式 system prompt (string)');
      } else if (system is List) {
        bool replaced = false;
        for (final block in system) {
          if (block is Map<String, dynamic> && block['type'] == 'text') {
            block['text'] = systemPromptContent;
            replaced = true;
            break;
          }
        }
        if (!replaced) {
          system.insert(0, {'type': 'text', 'text': systemPromptContent});
        }
        onLog?.call('已替换 Anthropic 格式 system prompt (content blocks)');
      }
    }
  }
}

void _injectThinking(
  Map<String, dynamic> bodyJson,
  Rule rule,
  void Function(String message)? onLog,
) {
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
}

/// 将规则中配置的自定义参数合并到请求体中
void _mergeCustomParams(
  Map<String, dynamic> bodyJson,
  Rule rule,
  void Function(String message)? onLog,
) {
  final customParams = rule.parsedCustomParams;
  if (customParams.isEmpty) return;

  // 自定义参数优先级最高，直接覆盖已存在的 key
  bodyJson.addAll(customParams);
  onLog?.call('已合并自定义参数: ${customParams.keys.join(", ")}');
}
