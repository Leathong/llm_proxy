import 'dart:convert';

/// 思考模式枚举
enum ThinkingMode {
  /// 不注入 thinking 参数
  none(''),

  /// 开启思考
  enabled('enabled'),

  /// 关闭思考
  disabled('disabled');

  final String value;
  const ThinkingMode(this.value);

  /// 从字符串解析，非法值回退到 none
  static ThinkingMode fromString(String s) {
    return ThinkingMode.values.firstWhere(
      (e) => e.value == s,
      orElse: () => ThinkingMode.none,
    );
  }
}

/// 思考强度枚举
enum ReasoningEffort {
  /// 不注入 reasoning_effort 参数
  none(''),

  /// 高强度
  high('high'),

  /// 最高强度
  max('max');

  final String value;
  const ReasoningEffort(this.value);

  /// 从字符串解析，非法值回退到 none
  static ReasoningEffort fromString(String s) {
    return ReasoningEffort.values.firstWhere(
      (e) => e.value == s,
      orElse: () => ReasoningEffort.none,
    );
  }
}

/// 思考深度合并枚举（thinkingMode + reasoningEffort）
enum ReasoningLevel {
  /// 不注入任何 thinking 参数
  none,

  /// 显式关闭思考
  off,

  /// 开启，高强度
  high,

  /// 开启，最高强度
  max;

  /// 显示标签
  String get label => name;

  /// 从 Rule 的 thinkingMode + reasoningEffort 计算合并级别
  static ReasoningLevel fromRule(Rule? rule) {
    if (rule == null) return none;
    if (rule.thinkingMode == ThinkingMode.enabled) {
      if (rule.reasoningEffort == ReasoningEffort.high) return high;
      if (rule.reasoningEffort == ReasoningEffort.max) return max;
    }
    if (rule.thinkingMode == ThinkingMode.disabled) return off;
    return none;
  }

  /// 拆分为 thinkingMode
  ThinkingMode get thinkingMode => switch (this) {
        ReasoningLevel.high || ReasoningLevel.max => ThinkingMode.enabled,
        ReasoningLevel.off => ThinkingMode.disabled,
        _ => ThinkingMode.none,
      };

  /// 拆分为 reasoningEffort
  ReasoningEffort get reasoningEffort => switch (this) {
        ReasoningLevel.high => ReasoningEffort.high,
        ReasoningLevel.max => ReasoningEffort.max,
        _ => ReasoningEffort.none,
      };
}

class Rule {
  final int id;
  final String name;
  final String groupName;
  final String customModelId;
  final String targetModelId;
  final int? providerModelId;
  final String providerModelName;
  final bool active;
  final ThinkingMode thinkingMode;
  final ReasoningEffort reasoningEffort;
  final bool convertThinkingToContent;
  final int? systemPromptId;
  final bool? stream; // 是否启用流式响应，null 表示不覆盖请求体中的 stream
  final bool streamIncludeUsage; // 流式响应中是否包含 usage 信息
  final String customParams; // 自定义参数 JSON 字符串，请求时合并到请求体中

  /// 自定义参数解析缓存，避免每次请求都 decode
  Map<String, dynamic>? _cachedCustomParams;
  bool _customParamsParsed = false;

  Rule({
    required this.id,
    required this.name,
    this.groupName = '',
    required this.customModelId,
    required this.targetModelId,
    this.providerModelId,
    this.providerModelName = '',
    this.active = true,
    this.thinkingMode = ThinkingMode.none,
    this.reasoningEffort = ReasoningEffort.none,
    this.convertThinkingToContent = false,
    this.systemPromptId,
    this.stream,
    this.streamIncludeUsage = true,
    this.customParams = '',
  });

  /// 获取解析后的自定义参数，带缓存
  Map<String, dynamic> get parsedCustomParams {
    if (_customParamsParsed) return _cachedCustomParams ?? {};
    _customParamsParsed = true;
    if (customParams.isEmpty) {
      _cachedCustomParams = {};
      return {};
    }
    try {
      _cachedCustomParams = jsonDecode(customParams) as Map<String, dynamic>;
    } catch (_) {
      _cachedCustomParams = {};
    }
    return _cachedCustomParams!;
  }

  Rule copyWith({
    int? id,
    String? name,
    String? groupName,
    String? customModelId,
    String? targetModelId,
    int? providerModelId,
    String? providerModelName,
    bool? active,
    ThinkingMode? thinkingMode,
    ReasoningEffort? reasoningEffort,
    bool? convertThinkingToContent,
    int? systemPromptId,
    bool? stream,
    bool? streamIncludeUsage,
    String? customParams,
  }) {
    return Rule(
      id: id ?? this.id,
      name: name ?? this.name,
      groupName: groupName ?? this.groupName,
      customModelId: customModelId ?? this.customModelId,
      targetModelId: targetModelId ?? this.targetModelId,
      providerModelId: providerModelId ?? this.providerModelId,
      providerModelName: providerModelName ?? this.providerModelName,
      active: active ?? this.active,
      thinkingMode: thinkingMode ?? this.thinkingMode,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      convertThinkingToContent: convertThinkingToContent ?? this.convertThinkingToContent,
      systemPromptId: systemPromptId ?? this.systemPromptId,
      stream: stream ?? this.stream,
      streamIncludeUsage: streamIncludeUsage ?? this.streamIncludeUsage,
      customParams: customParams ?? this.customParams,
    );
  }
}
