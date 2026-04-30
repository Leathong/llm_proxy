import 'package:llm_proxy/features/rules/domain/entities/rule.dart';
import 'package:llm_proxy/features/rules/domain/repositories/rule_repository.dart';
import 'package:llm_proxy/features/rules/data/datasources/rule_local_datasource.dart';
import 'package:llm_proxy/features/rules/data/models/rule_dto.dart';

class RuleRepositoryImpl implements RuleRepository {
  final RuleLocalDataSource _dataSource;
  List<Rule> _cache = [];

  RuleRepositoryImpl(this._dataSource) {
    _cache = _dataSource.loadRules().map((dto) => dto.toEntity()).toList();
  }

  @override
  List<Rule> getRules() => List.unmodifiable(_cache);

  @override
  Future<void> addRule(Rule rule) async {
    _cache.add(rule);
    await _sync();
  }

  @override
  Future<void> updateRule(Rule rule) async {
    final index = _cache.indexWhere((r) => r.id == rule.id);
    if (index == -1) return;
    _cache[index] = rule;
    await _sync();
  }

  @override
  Future<void> deleteRule(String id) async {
    _cache.removeWhere((r) => r.id == id);
    await _sync();
  }

  @override
  Future<void> toggleRule(String id, bool active) async {
    final index = _cache.indexWhere((r) => r.id == id);
    if (index == -1) return;
    _cache[index] = _cache[index].copyWith(active: active);
    await _sync();
  }

  Future<void> _sync() async {
    final dtos = _cache.map((r) => RuleDTO.fromEntity(r)).toList();
    await _dataSource.saveRules(dtos);
  }
}
