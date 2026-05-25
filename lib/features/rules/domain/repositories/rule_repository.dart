import 'package:llm_proxy/features/rules/domain/entities/endpoint_config.dart';
import 'package:llm_proxy/features/rules/domain/entities/rule.dart';
import 'package:llm_proxy/features/rules/domain/entities/system_prompt.dart';

abstract class RuleRepository {
  Future<List<Rule>> getRules();
  Future<Rule> addRule(Rule rule, List<EndpointConfig> endpoints);
  Future<void> updateRule(Rule rule, List<EndpointConfig> endpoints);
  Future<void> deleteRule(int id);
  Future<void> toggleRule(int id, bool active);

  Future<List<EndpointConfig>> getAllEndpoints();
  Future<EndpointConfig> addEndpoint(EndpointConfig endpoint);
  Future<void> updateEndpoint(EndpointConfig endpoint);
  Future<void> deleteEndpoint(int id);

  Future<List<SystemPrompt>> getSystemPrompts();
  Future<SystemPrompt> addSystemPrompt(SystemPrompt prompt);
  Future<void> updateSystemPrompt(SystemPrompt prompt);
  Future<void> deleteSystemPrompt(int id);

  Future<void> migrateFromSharedPreferences();
}
