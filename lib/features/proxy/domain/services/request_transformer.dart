import 'package:llm_proxy/features/proxy/domain/services/provider_format.dart';
import 'package:llm_proxy/features/rules/domain/entities/rule.dart';
import 'package:llm_proxy/features/rules/domain/entities/system_prompt.dart';

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
    SystemPromptMode systemPromptMode = SystemPromptMode.replace,
    void Function(String message)? onLog,
  }) {
    bodyJson['model'] = targetModelId;

    switch (format) {
      case ProviderFormat.openai:
        _transformOpenAI(bodyJson, rule, systemPromptContent, systemPromptMode, onLog);
      case ProviderFormat.anthropic:
        _transformAnthropic(bodyJson, rule, systemPromptContent, systemPromptMode, onLog);
    }

    // 合并自定义参数到请求体中（自定义参数优先级最高，覆盖已存在参数）
    _mergeCustomParams(bodyJson, rule, onLog);

    // 根据规则配置决定是否注入 stream 参数（null 表示不覆盖请求体中的原始值）
    if (rule.stream != null) {
      bodyJson['stream'] = rule.stream;
      if (rule.stream! && rule.streamIncludeUsage) {
        bodyJson['stream_options'] = {'include_usage': true};
      }
    }
    return bodyJson;
  }

  /// OpenAI 格式专用改写
  void _transformOpenAI(
    Map<String, dynamic> bodyJson,
    Rule rule,
    String? systemPromptContent,
    SystemPromptMode systemPromptMode,
    void Function(String message)? onLog,
  ) {
    // thinking 注入
    _injectThinking(bodyJson, rule, onLog);

    // system prompt 处理（OpenAI 方式：messages[role=system]）
    if (systemPromptContent != null && systemPromptContent.isNotEmpty) {
      final messages = bodyJson['messages'];
      if (messages is List) {
        final isAppend = systemPromptMode == SystemPromptMode.append;
        for (final msg in messages) {
          if (msg is Map<String, dynamic> && msg['role'] == 'system') {
            if (isAppend) {
              msg['content'] = '${msg['content']}\n\n$systemPromptContent';
              onLog?.call('已追加 OpenAI 格式 system prompt');
            } else {
              msg['content'] = systemPromptContent;
              onLog?.call('已替换 OpenAI 格式 system prompt');
            }
            return;
          }
        }
        // 无 system 消息时，新增一条
        messages.insert(0, {'role': 'system', 'content': systemPromptContent});
        onLog?.call('已插入 OpenAI 格式 system prompt');
      }
    }
  }

  /// Anthropic 格式专用改写
  void _transformAnthropic(
    Map<String, dynamic> bodyJson,
    Rule rule,
    String? systemPromptContent,
    SystemPromptMode systemPromptMode,
    void Function(String message)? onLog,
  ) {
    // thinking 注入
    _injectThinking(bodyJson, rule, onLog);

    // system prompt 处理（Anthropic 方式：顶层 system 字段）
    if (systemPromptContent != null && systemPromptContent.isNotEmpty) {
      final isAppend = systemPromptMode == SystemPromptMode.append;
      final system = bodyJson['system'];
      if (system is String) {
        if (isAppend) {
          bodyJson['system'] = '$system\n\n$systemPromptContent';
          onLog?.call('已追加 Anthropic 格式 system prompt (string)');
        } else {
          bodyJson['system'] = systemPromptContent;
          onLog?.call('已替换 Anthropic 格式 system prompt (string)');
        }
      } else if (system is List) {
        bool foundText = false;
        for (final block in system) {
          if (block is Map<String, dynamic> && block['type'] == 'text') {
            if (isAppend) {
              block['text'] = '${block['text']}\n\n$systemPromptContent';
              onLog?.call('已追加 Anthropic 格式 system prompt (content blocks)');
            } else {
              block['text'] = systemPromptContent;
              onLog?.call('已替换 Anthropic 格式 system prompt (content blocks)');
            }
            foundText = true;
            break;
          }
        }
        if (!foundText) {
          system.insert(0, {'type': 'text', 'text': systemPromptContent});
          onLog?.call('已插入 Anthropic 格式 system prompt (content blocks)');
        }
      } else {
        // 无 system 字段，直接设置
        bodyJson['system'] = systemPromptContent;
        onLog?.call('已设置 Anthropic 格式 system prompt');
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
  if (rule.thinkingMode != ThinkingMode.none) {
    bodyJson['thinking'] = {'type': rule.thinkingMode.value};
    final enableThinking = rule.thinkingMode == ThinkingMode.enabled;
    bodyJson['extra_body'] = {'enable_thinking': enableThinking};
    bodyJson['enable_thinking'] = enableThinking;
    onLog?.call('注入 thinking: ${rule.thinkingMode.value}');
  }

  if (rule.thinkingMode == ThinkingMode.enabled &&
      rule.reasoningEffort != ReasoningEffort.none) {
    bodyJson['reasoning_effort'] = rule.reasoningEffort.value;
    onLog?.call('注入 reasoning_effort: ${rule.reasoningEffort.value}');
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
