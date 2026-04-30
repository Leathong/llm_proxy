import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/features/rules/domain/entities/rule.dart';
import 'package:llm_proxy/features/rules/domain/repositories/rule_repository.dart';
import 'package:llm_proxy/features/rules/data/datasources/rule_local_datasource.dart';
import 'package:llm_proxy/features/rules/data/repositories/rule_repository_impl.dart';
import 'package:llm_proxy/features/settings/presentation/providers/settings_providers.dart';

final ruleLocalDataSourceProvider = Provider<RuleLocalDataSource>((ref) {
  final prefs = ref.read(sharedPreferencesProvider);
  return RuleLocalDataSource(prefs);
});

final ruleRepositoryProvider = Provider<RuleRepository>((ref) {
  final dataSource = ref.read(ruleLocalDataSourceProvider);
  return RuleRepositoryImpl(dataSource);
});

class RulesNotifier extends Notifier<List<Rule>> {
  @override
  List<Rule> build() {
    final repo = ref.watch(ruleRepositoryProvider);
    return repo.getRules();
  }

  Future<void> add(Rule rule) async {
    final repo = ref.read(ruleRepositoryProvider);
    await repo.addRule(rule);
    ref.invalidateSelf();
  }

  Future<void> update(Rule rule) async {
    final repo = ref.read(ruleRepositoryProvider);
    await repo.updateRule(rule);
    ref.invalidateSelf();
  }

  Future<void> delete(String id) async {
    final repo = ref.read(ruleRepositoryProvider);
    await repo.deleteRule(id);
    ref.invalidateSelf();
  }

  Future<void> toggle(String id, bool active) async {
    final repo = ref.read(ruleRepositoryProvider);
    await repo.toggleRule(id, active);
    ref.invalidateSelf();
  }
}

final rulesProvider = NotifierProvider<RulesNotifier, List<Rule>>(
  RulesNotifier.new,
);
