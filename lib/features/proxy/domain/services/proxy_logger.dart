import 'dart:developer' as developer;

/// 代理服务器日志辅助类，仅用于输出文本日志。
/// 日志条目存储已迁移到 [LogRepository]/Drift。
class ProxyLogger {
  final void Function(String message)? onLog;

  ProxyLogger({this.onLog});

  /// 输出文本日志
  void log(String message) {
    if (onLog != null) {
      onLog!(message);
    } else {
      developer.log(message, name: 'ProxyServer');
    }
  }
}
