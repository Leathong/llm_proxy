import 'package:flutter/material.dart';
import '../models/proxy_log.dart';

class LogProvider extends ChangeNotifier {
  final List<ProxyLog> _logs = [];

  List<ProxyLog> get logs => List.unmodifiable(_logs);

  void addLog(ProxyLog log) {
    _logs.insert(0, log); // 最新日志放在最前面
    if (_logs.length > 500) {
      _logs.removeLast(); // 限制最多保留 500 条日志
    }
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }
}
