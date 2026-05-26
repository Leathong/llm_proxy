import 'package:llm_proxy/features/rules/domain/entities/model_provider.dart';
import 'package:llm_proxy/features/rules/domain/entities/provider_model.dart';
import 'package:llm_proxy/features/rules/domain/entities/rule.dart';
import 'package:llm_proxy/features/rules/domain/entities/system_prompt.dart';

abstract class RuleRepository {
  Future<List<Rule>> getRules();
  Future<Rule> addRule(Rule rule);
  Future<void> updateRule(Rule rule);
  Future<void> deleteRule(int id);
  Future<void> toggleRule(int id, bool active);

  Future<List<SystemPrompt>> getSystemPrompts();
  Future<SystemPrompt> addSystemPrompt(SystemPrompt prompt);
  Future<void> updateSystemPrompt(SystemPrompt prompt);
  Future<void> deleteSystemPrompt(int id);

  // ModelProvider CRUD
  Future<List<ModelProvider>> getModelProviders();
  Future<ModelProvider> addModelProvider(ModelProvider provider);
  Future<void> updateModelProvider(ModelProvider provider);
  Future<void> deleteModelProvider(int id);

  // ProviderModel CRUD
  Future<List<ProviderModel>> getProviderModels(int providerId);
  Future<List<ProviderModel>> getAllProviderModels();
  Future<ProviderModel> addProviderModel(ProviderModel model);
  Future<void> updateProviderModel(ProviderModel model);
  Future<void> deleteProviderModel(int id);
  Future<void> toggleProviderModel(int id, bool enabled);

  // 根据 ID 获取完整信息
  Future<ProviderModel?> getProviderModelById(int id);
  Future<ModelProvider?> getModelProviderById(int id);

  Future<void> migrateFromSharedPreferences();
}
