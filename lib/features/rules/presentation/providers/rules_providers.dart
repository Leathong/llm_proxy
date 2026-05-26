import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/core/database/app_database.dart'
    hide Rule, Endpoint, SystemPrompt, ModelProvider, ProviderModel;
import 'package:llm_proxy/features/rules/domain/entities/model_provider.dart';
import 'package:llm_proxy/features/rules/domain/entities/provider_model.dart';
import 'package:llm_proxy/features/rules/domain/entities/rule.dart';
import 'package:llm_proxy/features/rules/domain/entities/system_prompt.dart';
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

  Future<void> add(Rule rule) async {
    final repo = ref.read(ruleRepositoryProvider);
    await repo.addRule(rule);
    ref.invalidateSelf();
  }

  Future<void> updateRule(Rule rule) async {
    final repo = ref.read(ruleRepositoryProvider);
    await repo.updateRule(rule);
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

class SystemPromptsNotifier extends AsyncNotifier<List<SystemPrompt>> {
  @override
  Future<List<SystemPrompt>> build() async {
    final repo = ref.watch(ruleRepositoryProvider);
    return repo.getSystemPrompts();
  }

  Future<void> add(SystemPrompt prompt) async {
    final repo = ref.read(ruleRepositoryProvider);
    await repo.addSystemPrompt(prompt);
    ref.invalidateSelf();
  }

  Future<void> updatePrompt(SystemPrompt prompt) async {
    final repo = ref.read(ruleRepositoryProvider);
    await repo.updateSystemPrompt(prompt);
    ref.invalidateSelf();
  }

  Future<void> delete(int id) async {
    final repo = ref.read(ruleRepositoryProvider);
    await repo.deleteSystemPrompt(id);
    ref.invalidateSelf();
  }
}

final systemPromptsProvider =
    AsyncNotifierProvider<SystemPromptsNotifier, List<SystemPrompt>>(
  SystemPromptsNotifier.new,
);

// ──────────────────────────── ModelProvider ────────────────────────────

class ModelProvidersNotifier extends AsyncNotifier<List<ModelProvider>> {
  @override
  Future<List<ModelProvider>> build() async {
    final repo = ref.watch(ruleRepositoryProvider);
    return repo.getModelProviders();
  }

  Future<ModelProvider> add(ModelProvider provider) async {
    final repo = ref.read(ruleRepositoryProvider);
    final result = await repo.addModelProvider(provider);
    ref.invalidateSelf();
    return result;
  }

  Future<void> updateProvider(ModelProvider provider) async {
    final repo = ref.read(ruleRepositoryProvider);
    await repo.updateModelProvider(provider);
    ref.invalidateSelf();
  }

  Future<void> delete(int id) async {
    final repo = ref.read(ruleRepositoryProvider);
    await repo.deleteModelProvider(id);
    ref.invalidateSelf();
  }
}

final modelProvidersProvider =
    AsyncNotifierProvider<ModelProvidersNotifier, List<ModelProvider>>(
  ModelProvidersNotifier.new,
);

// ──────────────────────────── ProviderModel ────────────────────────────

final allProviderModelsProvider = FutureProvider<List<ProviderModel>>((ref) {
  final repo = ref.watch(ruleRepositoryProvider);
  return repo.getAllProviderModels();
});

final providerModelsProvider =
    FutureProvider.family<List<ProviderModel>, int>((ref, providerId) {
  final repo = ref.watch(ruleRepositoryProvider);
  return repo.getProviderModels(providerId);
});
