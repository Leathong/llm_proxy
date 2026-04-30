import 'package:llm_proxy/features/rules/domain/entities/rule.dart';

abstract class RuleRepository {
  List<Rule> getRules();
  Future<void> addRule(Rule rule);
  Future<void> updateRule(Rule rule);
  Future<void> deleteRule(String id);
  Future<void> toggleRule(String id, bool active);
}
