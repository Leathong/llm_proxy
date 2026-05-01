import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/core/database/app_database.dart' hide Rule, Endpoint;
import 'package:llm_proxy/features/rules/domain/entities/endpoint_config.dart';
import 'package:llm_proxy/features/rules/domain/entities/rule.dart';
import 'package:llm_proxy/features/rules/domain/repositories/rule_repository.dart';
import 'package:llm_proxy/features/rules/data/repositories/drift_rule_repository.dart';
import 'package:llm_proxy/features/settings/presentation/providers/settings_providers.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('必须先在 main 中 override appDatabaseProvider');
});

final ruleRepositoryProvider = Provider<RuleRepository>((ref) {
  final db = ref.read(appDatabaseProvider);
  final prefs = ref.read(sharedPreferencesProvider);
  return DriftRuleRepository(db, prefs);
});

class RulesNotifier extends AsyncNotifier<List<Rule>> {
  @override
  Future<List<Rule>> build() async {
    final repo = ref.watch(ruleRepositoryProvider);
    return repo.getRules();
  }

  Future<void> add(Rule rule, List<EndpointConfig> endpoints) async {
    final repo = ref.read(ruleRepositoryProvider);
    await repo.addRule(rule, endpoints);
    ref.invalidateSelf();
  }

  Future<void> updateRule(Rule rule, List<EndpointConfig> endpoints) async {
    final repo = ref.read(ruleRepositoryProvider);
    await repo.updateRule(rule, endpoints);
    ref.invalidateSelf();
  }

  Future<void> delete(int id) async {
    final repo = ref.read(ruleRepositoryProvider);
    await repo.deleteRule(id);
    ref.invalidateSelf();
  }

  Future<void> toggle(int id, bool active) async {
    final repo = ref.read(ruleRepositoryProvider);
    await repo.toggleRule(id, active);
    ref.invalidateSelf();
  }
}

final rulesProvider = AsyncNotifierProvider<RulesNotifier, List<Rule>>(
  RulesNotifier.new,
);

final allEndpointsProvider = FutureProvider<List<EndpointConfig>>((ref) {
  final repo = ref.watch(ruleRepositoryProvider);
  return repo.getAllEndpoints();
});
