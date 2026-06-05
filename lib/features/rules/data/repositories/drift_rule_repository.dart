import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:llm_proxy/core/database/app_database.dart' as db;
import 'package:llm_proxy/features/rules/domain/entities/model_provider.dart' as entity;
import 'package:llm_proxy/features/rules/domain/entities/provider_model.dart' as entity;
import 'package:llm_proxy/features/rules/domain/entities/rule.dart' as entity;
import 'package:llm_proxy/features/rules/domain/entities/system_prompt.dart';
import 'package:llm_proxy/features/rules/domain/repositories/rule_repository.dart';

class DriftRuleRepository implements RuleRepository {
  final db.AppDatabase _db;
  final SharedPreferences _prefs;

  /// 内存缓存，避免每次代理请求都查询数据库
  List<entity.Rule>? _cachedRules;

  DriftRuleRepository(this._db, this._prefs);

  /// 使缓存失效，在增删改操作后调用
  void _invalidateCache() {
    _cachedRules = null;
  }

  @override
  Future<List<entity.Rule>> getRules() async {
    if (_cachedRules != null) return _cachedRules!;

    final rules = await _db.select(_db.rules).get();
    if (rules.isEmpty) {
      _cachedRules = [];
      return _cachedRules!;
    }

    _cachedRules = rules.map((rule) {
      return entity.Rule(
        id: rule.id,
        name: rule.name,
        groupName: rule.groupName,
        customModelId: rule.customModelId,
        targetModelId: rule.targetModelId,
        providerModelId: rule.providerModelId,
        providerModelName: rule.providerModelName,
        active: rule.active,
        thinkingMode: entity.ThinkingMode.fromString(rule.thinkingMode),
        reasoningEffort: entity.ReasoningEffort.fromString(rule.reasoningEffort),
        convertThinkingToContent: rule.convertThinkingToContent,
        systemPromptId: rule.systemPromptId,
        stream: rule.stream,
        streamIncludeUsage: rule.streamIncludeUsage,
        customParams: rule.customParams,
      );
    }).toList();

    return _cachedRules!;
  }

  @override
  Future<entity.Rule> addRule(entity.Rule rule) async {
    _invalidateCache();
    final ruleId = await _db.into(_db.rules).insert(db.RulesCompanion.insert(
          name: rule.name,
          groupName: Value(rule.groupName),
          customModelId: rule.customModelId,
          targetModelId: rule.targetModelId,
          providerModelId: Value(rule.providerModelId),
          providerModelName: Value(rule.providerModelName),
          active: Value(rule.active),
          thinkingMode: Value(rule.thinkingMode.value),
          reasoningEffort: Value(rule.reasoningEffort.value),
          convertThinkingToContent: Value(rule.convertThinkingToContent),
          systemPromptId: Value(rule.systemPromptId),
          stream: Value(rule.stream),
          streamIncludeUsage: Value(rule.streamIncludeUsage),
          customParams: Value(rule.customParams),
        ));

    return entity.Rule(
      id: ruleId,
      name: rule.name,
      groupName: rule.groupName,
      customModelId: rule.customModelId,
      targetModelId: rule.targetModelId,
      providerModelId: rule.providerModelId,
      providerModelName: rule.providerModelName,
      active: rule.active,
      thinkingMode: rule.thinkingMode,
      reasoningEffort: rule.reasoningEffort,
      convertThinkingToContent: rule.convertThinkingToContent,
      systemPromptId: rule.systemPromptId,
      stream: rule.stream,
      streamIncludeUsage: rule.streamIncludeUsage,
      customParams: rule.customParams,
    );
  }

  @override
  Future<void> updateRule(entity.Rule rule) async {
    _invalidateCache();
    await (_db.update(_db.rules)..where((r) => r.id.equals(rule.id))).write(
      db.RulesCompanion(
        name: Value(rule.name),
        groupName: Value(rule.groupName),
        customModelId: Value(rule.customModelId),
        targetModelId: Value(rule.targetModelId),
        providerModelId: Value(rule.providerModelId),
        providerModelName: Value(rule.providerModelName),
        active: Value(rule.active),
        thinkingMode: Value(rule.thinkingMode.value),
        reasoningEffort: Value(rule.reasoningEffort.value),
        convertThinkingToContent: Value(rule.convertThinkingToContent),
        systemPromptId: Value(rule.systemPromptId),
        stream: Value(rule.stream),
        streamIncludeUsage: Value(rule.streamIncludeUsage),
        customParams: Value(rule.customParams),
      ),
    );
  }

  @override
  Future<void> deleteRule(int id) async {
    _invalidateCache();
    await (_db.delete(_db.rules)..where((r) => r.id.equals(id))).go();
  }

  @override
  Future<void> toggleRule(int id, bool active) async {
    _invalidateCache();
    await (_db.update(_db.rules)..where((r) => r.id.equals(id)))
        .write(db.RulesCompanion(active: Value(active)));
  }

  @override
  Future<List<SystemPrompt>> getSystemPrompts() async {
    final rows = await (_db.select(_db.systemPrompts)
          ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]))
        .get();
    return rows
        .map((e) => SystemPrompt(
              id: e.id,
              name: e.name,
              content: e.content,
            ))
        .toList();
  }

  @override
  Future<SystemPrompt> addSystemPrompt(SystemPrompt prompt) async {
    final id = await _db.into(_db.systemPrompts).insert(
          db.SystemPromptsCompanion.insert(
            name: prompt.name,
            content: prompt.content,
          ),
        );
    return SystemPrompt(
      id: id,
      name: prompt.name,
      content: prompt.content,
    );
  }

  @override
  Future<void> updateSystemPrompt(SystemPrompt prompt) async {
    await (_db.update(_db.systemPrompts)
          ..where((e) => e.id.equals(prompt.id)))
        .write(db.SystemPromptsCompanion(
      name: Value(prompt.name),
      content: Value(prompt.content),
    ));
  }

  @override
  Future<void> deleteSystemPrompt(int id) async {
    await (_db.delete(_db.systemPrompts)..where((e) => e.id.equals(id))).go();
  }

  // ──────────────────────────── ModelProvider CRUD ────────────────────────────

  @override
  Future<List<entity.ModelProvider>> getModelProviders() async {
    final rows = await (_db.select(_db.modelProviders)
          ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]))
        .get();
    return rows
        .map((e) => entity.ModelProvider(
              id: e.id,
              name: e.name,
              baseUrl: e.baseUrl,
              apiKey: e.apiKey,
              format: e.format,
            ))
        .toList();
  }

  @override
  Future<entity.ModelProvider> addModelProvider(
      entity.ModelProvider provider) async {
    final id = await _db.into(_db.modelProviders).insert(
          db.ModelProvidersCompanion.insert(
            name: provider.name,
            baseUrl: provider.baseUrl,
            apiKey: Value(provider.apiKey),
            format: Value(provider.format),
          ),
        );
    return entity.ModelProvider(
      id: id,
      name: provider.name,
      baseUrl: provider.baseUrl,
      apiKey: provider.apiKey,
      format: provider.format,
    );
  }

  @override
  Future<void> updateModelProvider(entity.ModelProvider provider) async {
    await (_db.update(_db.modelProviders)
          ..where((e) => e.id.equals(provider.id)))
        .write(db.ModelProvidersCompanion(
      name: Value(provider.name),
      baseUrl: Value(provider.baseUrl),
      apiKey: Value(provider.apiKey),
      format: Value(provider.format),
    ));
  }

  @override
  Future<void> deleteModelProvider(int id) async {
    await (_db.delete(_db.modelProviders)..where((e) => e.id.equals(id)))
        .go();
  }

  // ──────────────────────────── ProviderModel CRUD ────────────────────────────

  @override
  Future<List<entity.ProviderModel>> getProviderModels(int providerId) async {
    final rows = await (_db.select(_db.providerModels)
          ..where((e) => e.providerId.equals(providerId))
          ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]))
        .get();
    return rows
        .map((e) => entity.ProviderModel(
              id: e.id,
              providerId: e.providerId,
              modelId: e.modelId,
              displayName: e.displayName,
              enabled: e.enabled,
            ))
        .toList();
  }

  @override
  Future<List<entity.ProviderModel>> getAllProviderModels() async {
    final rows = await (_db.select(_db.providerModels)
          ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]))
        .get();
    return rows
        .map((e) => entity.ProviderModel(
              id: e.id,
              providerId: e.providerId,
              modelId: e.modelId,
              displayName: e.displayName,
              enabled: e.enabled,
            ))
        .toList();
  }

  @override
  Future<entity.ProviderModel> addProviderModel(
      entity.ProviderModel model) async {
    final id = await _db.into(_db.providerModels).insert(
          db.ProviderModelsCompanion.insert(
            providerId: model.providerId,
            modelId: model.modelId,
            displayName: Value(model.displayName),
            enabled: Value(model.enabled),
          ),
        );
    return entity.ProviderModel(
      id: id,
      providerId: model.providerId,
      modelId: model.modelId,
      displayName: model.displayName,
      enabled: model.enabled,
    );
  }

  @override
  Future<void> updateProviderModel(entity.ProviderModel model) async {
    await (_db.update(_db.providerModels)
          ..where((e) => e.id.equals(model.id)))
        .write(db.ProviderModelsCompanion(
      modelId: Value(model.modelId),
      displayName: Value(model.displayName),
      enabled: Value(model.enabled),
    ));
  }

  @override
  Future<void> deleteProviderModel(int id) async {
    await (_db.delete(_db.providerModels)..where((e) => e.id.equals(id)))
        .go();
  }

  @override
  Future<void> toggleProviderModel(int id, bool enabled) async {
    await (_db.update(_db.providerModels)..where((e) => e.id.equals(id)))
        .write(db.ProviderModelsCompanion(enabled: Value(enabled)));
  }

  @override
  Future<entity.ProviderModel?> getProviderModelById(int id) async {
    final rows = await (_db.select(_db.providerModels)
          ..where((e) => e.id.equals(id))
          ..limit(1))
        .get();
    if (rows.isEmpty) return null;
    final e = rows.first;
    return entity.ProviderModel(
      id: e.id,
      providerId: e.providerId,
      modelId: e.modelId,
      displayName: e.displayName,
      enabled: e.enabled,
    );
  }

  @override
  Future<entity.ModelProvider?> getModelProviderById(int id) async {
    final rows = await (_db.select(_db.modelProviders)
          ..where((e) => e.id.equals(id))
          ..limit(1))
        .get();
    if (rows.isEmpty) return null;
    final e = rows.first;
    return entity.ModelProvider(
      id: e.id,
      name: e.name,
      baseUrl: e.baseUrl,
      apiKey: e.apiKey,
      format: e.format,
    );
  }

  @override
  Future<void> migrateFromSharedPreferences() async {
    const key = 'proxyRules';
    final jsonList = _prefs.getStringList(key);
    if (jsonList == null || jsonList.isEmpty) return;

    final existingRules = await _db.select(_db.rules).get();
    if (existingRules.isNotEmpty) return;

    await _db.transaction(() async {
      for (final jsonStr in jsonList) {
        final Map<String, dynamic> json =
            jsonDecode(jsonStr) as Map<String, dynamic>;

        await _db.into(_db.rules).insert(
              db.RulesCompanion.insert(
                name: json['name'] as String? ?? '',
                customModelId: json['customModelId'] as String? ?? '',
                targetModelId: json['targetModelId'] as String? ?? '',
                active: Value(json['active'] as bool? ?? true),
                thinkingMode: Value(json['thinkingMode'] as String? ?? ''),
                reasoningEffort:
                    Value(json['reasoningEffort'] as String? ?? ''),
              ),
            );
      }
    });

    await _prefs.remove(key);
  }
}
