import 'package:llm_proxy/features/rules/domain/entities/rule.dart';

/// 规则匹配结果
class RuleMatchResult {
  final Rule rule;

  const RuleMatchResult({required this.rule});
}

/// 负责根据 modelId 匹配规则
class RuleMatcher {
  /// 根据请求的 modelId 从规则列表中匹配活跃规则
  /// 返回 null 表示未匹配到可用规则
  RuleMatchResult? match(List<Rule> rules, String modelId) {
    for (final r in rules) {
      if (r.active && r.customModelId == modelId) {
        return RuleMatchResult(rule: r);
      }
    }
    return null;
  }
}
