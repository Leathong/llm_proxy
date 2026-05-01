import 'package:llm_proxy/features/rules/domain/entities/endpoint_config.dart';
import 'package:llm_proxy/features/rules/domain/entities/rule.dart';

/// 规则匹配结果
class RuleMatchResult {
  final Rule rule;
  final EndpointConfig endpoint;

  const RuleMatchResult({required this.rule, required this.endpoint});
}

/// 负责根据 modelId 匹配规则，并通过 Round-Robin 选择 endpoint
class RuleMatcher {
  // Round-Robin 计数器，key 为 rule.id
  final Map<int, int> _rrCounters = {};

  /// 根据请求的 modelId 从规则列表中匹配活跃规则，并选取 endpoint
  /// 返回 null 表示未匹配到可用规则或无可用 endpoint
  RuleMatchResult? match(List<Rule> rules, String modelId) {
    Rule? matched;
    for (final r in rules) {
      if (r.active && r.customModelId == modelId) {
        matched = r;
        break;
      }
    }
    if (matched == null) return null;

    final active = matched.activeEndpoints;
    if (active.isEmpty) return null;

    final endpoint = _pickEndpoint(matched, active);
    return RuleMatchResult(rule: matched, endpoint: endpoint);
  }

  /// Round-Robin 选择一个活跃的 endpoint
  EndpointConfig _pickEndpoint(Rule rule, List<EndpointConfig> active) {
    if (active.length == 1) return active.first;
    final counter = _rrCounters[rule.id] ?? 0;
    final picked = active[counter % active.length];
    _rrCounters[rule.id] = counter + 1;
    return picked;
  }

  /// 重置计数器（服务器停止时调用）
  void reset() => _rrCounters.clear();
}
