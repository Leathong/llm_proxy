import 'package:llm_proxy/features/rules/domain/entities/endpoint_config.dart';
import 'package:llm_proxy/features/rules/domain/entities/rule.dart';

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

  Future<void> migrateFromSharedPreferences();
}
