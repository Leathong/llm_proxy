import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:llm_proxy/core/database/app_database.dart' as db;
import 'package:llm_proxy/features/rules/domain/entities/endpoint_config.dart';
import 'package:llm_proxy/features/rules/domain/entities/rule.dart' as entity;
import 'package:llm_proxy/features/rules/domain/repositories/rule_repository.dart';

class DriftRuleRepository implements RuleRepository {
  final db.AppDatabase _db;
  final SharedPreferences _prefs;

  DriftRuleRepository(this._db, this._prefs);

  @override
  Future<List<entity.Rule>> getRules() async {
    final rules = await _db.select(_db.rules).get();
    final result = <entity.Rule>[];

    for (final rule in rules) {
      final joins = await (_db.select(_db.ruleEndpoints)
            ..where((re) => re.ruleId.equals(rule.id))
            ..orderBy([(re) => OrderingTerm.asc(re.sortOrder)]))
          .get();

      final endpoints = <EndpointConfig>[];
      for (final join in joins) {
        final ep = await (_db.select(_db.endpoints)
              ..where((e) => e.id.equals(join.endpointId)))
            .getSingleOrNull();
        if (ep != null) {
          endpoints.add(EndpointConfig(
            id: ep.id,
            url: ep.url,
            apiKey: ep.apiKey,
            active: join.active,
          ));
        }
      }

      result.add(entity.Rule(
        id: rule.id,
        name: rule.name,
        groupName: rule.groupName,
        endpoints: endpoints,
        customModelId: rule.customModelId,
        targetModelId: rule.targetModelId,
        active: rule.active,
        thinkingMode: rule.thinkingMode,
        reasoningEffort: rule.reasoningEffort,
        convertThinkingToContent: rule.convertThinkingToContent,
      ));
    }

    return result;
  }

  @override
  Future<entity.Rule> addRule(
      entity.Rule rule, List<EndpointConfig> endpoints) async {
    return _db.transaction(() async {
      final ruleId = await _db.into(_db.rules).insert(db.RulesCompanion.insert(
            name: rule.name,
            groupName: Value(rule.groupName),
            customModelId: rule.customModelId,
            targetModelId: rule.targetModelId,
            active: Value(rule.active),
            thinkingMode: Value(rule.thinkingMode),
            reasoningEffort: Value(rule.reasoningEffort),
            convertThinkingToContent: Value(rule.convertThinkingToContent),
          ));

      final resolvedEndpoints = <EndpointConfig>[];
      for (var i = 0; i < endpoints.length; i++) {
        final ep = endpoints[i];
        int epId;

        if (ep.id > 0) {
          epId = ep.id;
          await (_db.update(_db.endpoints)
                ..where((e) => e.id.equals(epId)))
              .write(db.EndpointsCompanion(
            url: Value(ep.url),
            apiKey: Value(ep.apiKey),
          ));
        } else {
          epId = await _db
              .into(_db.endpoints)
              .insert(db.EndpointsCompanion.insert(
                url: ep.url,
                apiKey: Value(ep.apiKey),
              ));
        }

        await _db.into(_db.ruleEndpoints).insert(
              db.RuleEndpointsCompanion.insert(
                ruleId: ruleId,
                endpointId: epId,
                active: Value(ep.active),
                sortOrder: Value(i),
              ),
            );

        resolvedEndpoints.add(EndpointConfig(
          id: epId,
          url: ep.url,
          apiKey: ep.apiKey,
          active: ep.active,
        ));
      }

      return entity.Rule(
        id: ruleId,
        name: rule.name,
        groupName: rule.groupName,
        endpoints: resolvedEndpoints,
        customModelId: rule.customModelId,
        targetModelId: rule.targetModelId,
        active: rule.active,
        thinkingMode: rule.thinkingMode,
        reasoningEffort: rule.reasoningEffort,
        convertThinkingToContent: rule.convertThinkingToContent,
      );
    });
  }

  @override
  Future<void> updateRule(
      entity.Rule rule, List<EndpointConfig> endpoints) async {
    await _db.transaction(() async {
      await (_db.update(_db.rules)..where((r) => r.id.equals(rule.id))).write(
        db.RulesCompanion(
          name: Value(rule.name),
          groupName: Value(rule.groupName),
          customModelId: Value(rule.customModelId),
          targetModelId: Value(rule.targetModelId),
          active: Value(rule.active),
          thinkingMode: Value(rule.thinkingMode),
          reasoningEffort: Value(rule.reasoningEffort),
          convertThinkingToContent: Value(rule.convertThinkingToContent),
        ),
      );

      await (_db.delete(_db.ruleEndpoints)
            ..where((re) => re.ruleId.equals(rule.id)))
          .go();

      for (var i = 0; i < endpoints.length; i++) {
        final ep = endpoints[i];
        int epId;

        if (ep.id > 0) {
          epId = ep.id;
          await (_db.update(_db.endpoints)
                ..where((e) => e.id.equals(epId)))
              .write(db.EndpointsCompanion(
            url: Value(ep.url),
            apiKey: Value(ep.apiKey),
          ));
        } else {
          epId = await _db
              .into(_db.endpoints)
              .insert(db.EndpointsCompanion.insert(
                url: ep.url,
                apiKey: Value(ep.apiKey),
              ));
        }

        await _db.into(_db.ruleEndpoints).insert(
              db.RuleEndpointsCompanion.insert(
                ruleId: rule.id,
                endpointId: epId,
                active: Value(ep.active),
                sortOrder: Value(i),
              ),
            );
      }
    });
  }

  @override
  Future<void> deleteRule(int id) async {
    await (_db.delete(_db.rules)..where((r) => r.id.equals(id))).go();
  }

  @override
  Future<void> toggleRule(int id, bool active) async {
    await (_db.update(_db.rules)..where((r) => r.id.equals(id)))
        .write(db.RulesCompanion(active: Value(active)));
  }

  @override
  Future<List<EndpointConfig>> getAllEndpoints() async {
    final rows = await (_db.select(_db.endpoints)
          ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]))
        .get();
    return rows
        .map((e) => EndpointConfig(
              id: e.id,
              url: e.url,
              apiKey: e.apiKey,
            ))
        .toList();
  }

  @override
  Future<EndpointConfig> addEndpoint(EndpointConfig endpoint) async {
    final id =
        await _db.into(_db.endpoints).insert(db.EndpointsCompanion.insert(
              url: endpoint.url,
              apiKey: Value(endpoint.apiKey),
            ));
    return EndpointConfig(
      id: id,
      url: endpoint.url,
      apiKey: endpoint.apiKey,
    );
  }

  @override
  Future<void> updateEndpoint(EndpointConfig endpoint) async {
    await (_db.update(_db.endpoints)
          ..where((e) => e.id.equals(endpoint.id)))
        .write(db.EndpointsCompanion(
      url: Value(endpoint.url),
      apiKey: Value(endpoint.apiKey),
    ));
  }

  @override
  Future<void> deleteEndpoint(int id) async {
    await (_db.delete(_db.endpoints)..where((e) => e.id.equals(id))).go();
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

        final ruleId = await _db.into(_db.rules).insert(
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

        final endpointsList =
            json['endpoints'] as List<dynamic>? ?? <dynamic>[];
        final oldEndpoint = json['endpoint'] as String? ?? '';
        final oldApiKey = json['apiKey'] as String? ?? '';

        if (endpointsList.isNotEmpty) {
          for (var i = 0; i < endpointsList.length; i++) {
            final epJson = endpointsList[i] as Map<String, dynamic>;
            final epId = await _db.into(_db.endpoints).insert(
                  db.EndpointsCompanion.insert(
                    url: epJson['url'] as String? ?? '',
                    apiKey: Value(epJson['apiKey'] as String? ?? ''),
                  ),
                );
            await _db.into(_db.ruleEndpoints).insert(
                  db.RuleEndpointsCompanion.insert(
                    ruleId: ruleId,
                    endpointId: epId,
                    active: Value(epJson['active'] as bool? ?? true),
                    sortOrder: Value(i),
                  ),
                );
          }
        } else if (oldEndpoint.isNotEmpty) {
          final epId = await _db.into(_db.endpoints).insert(
                db.EndpointsCompanion.insert(
                  url: oldEndpoint,
                  apiKey: Value(oldApiKey),
                ),
              );
          await _db.into(_db.ruleEndpoints).insert(
                db.RuleEndpointsCompanion.insert(
                  ruleId: ruleId,
                  endpointId: epId,
                  active: const Value(true),
                  sortOrder: const Value(0),
                ),
              );
        }
      }
    });

    await _prefs.remove(key);
  }
}
