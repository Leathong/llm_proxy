import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:llm_proxy/features/rules/data/models/rule_dto.dart';

class RuleLocalDataSource {
  final SharedPreferences _prefs;
  static const String _key = 'proxyRules';

  RuleLocalDataSource(this._prefs);

  List<RuleDTO> loadRules() {
    final jsonList = _prefs.getStringList(_key);
    if (jsonList == null) return [];
    return jsonList
        .map((jsonStr) => RuleDTO.fromJson(json.decode(jsonStr) as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveRules(List<RuleDTO> rules) async {
    final jsonList = rules.map((r) => json.encode(r.toJson())).toList();
    await _prefs.setStringList(_key, jsonList);
  }
}
