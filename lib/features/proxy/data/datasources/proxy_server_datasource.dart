import 'dart:io';

import 'package:llm_proxy/features/logs/data/datasources/log_file_writer.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_entry.dart';
import 'package:llm_proxy/features/proxy/domain/services/proxy_logger.dart';
import 'package:llm_proxy/features/proxy/domain/services/request_forwarder.dart';
import 'package:llm_proxy/features/proxy/domain/services/request_router.dart';
import 'package:llm_proxy/features/proxy/domain/services/request_transformer.dart';
import 'package:llm_proxy/features/proxy/domain/services/rule_matcher.dart';
import 'package:llm_proxy/features/rules/domain/entities/rule.dart';

/// 代理服务器数据源：仅负责 HttpServer 生命周期管理（启动/停止/监听）
class ProxyServerDataSource {
  HttpServer? _server;
  bool get isRunning => _server != null;
  int _port = 8080;

  final RuleMatcher _ruleMatcher = RuleMatcher();
  final RequestTransformer _transformer = RequestTransformer();
  final RequestForwarder _forwarder = RequestForwarder();
  final LogFileWriter _logWriter = LogFileWriter();
  late final ProxyLogger _logger;
  late final RequestRouter _router;

  ProxyServerDataSource({
    required Future<List<Rule>> Function() getRules,
    void Function(String message)? onLog,
    void Function(LogEntry logEntry)? onLogEntry,
    void Function(LogEntry logEntry)? onLogEntryUpdate,
  }) {
    _logger = ProxyLogger(
      onLog: onLog,
      onLogEntry: onLogEntry,
      onLogEntryUpdate: onLogEntryUpdate,
    );
    _router = RequestRouter(
      getRules: getRules,
      logger: _logger,
      ruleMatcher: _ruleMatcher,
      transformer: _transformer,
      forwarder: _forwarder,
      logWriter: _logWriter,
    );
  }

  void setLogFileDir(String dir) {
    _logWriter.setLogFileDir(dir);
  }

  Future<void> start({int port = 8080, String? certPath, String? keyPath}) async {
    if (isRunning) return;
    _port = port;
    try {
      if (certPath != null && keyPath != null && certPath.isNotEmpty && keyPath.isNotEmpty) {
        final certFile = File(certPath);
        final keyFile = File(keyPath);

        if (await certFile.exists() && await keyFile.exists()) {
          final securityContext = SecurityContext();
          securityContext.useCertificateChain(certPath);
          securityContext.usePrivateKey(keyPath);
          _server = await HttpServer.bindSecure(InternetAddress.anyIPv4, _port, securityContext);
          _logger.log('代理服务器已启动(HTTPS)，监听端口: $_port');
        } else {
          _logger.log('证书文件不存在，降级为 HTTP 启动，监听端口: $_port');
          _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
        }
      } else {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
        _logger.log('代理服务器已启动(HTTP)，监听端口: $_port');
      }
      _server!.listen(
        _router.handle,
        onError: (error) => _logger.log('服务器监听出错: $error'),
        onDone: () => _logger.log('服务器监听结束'),
      );
    } catch (e) {
      _logger.log('代理服务器启动失败: $e');
      rethrow;
    }
  }

  Future<void> stop() async {
    if (!isRunning) return;
    await _server!.close(force: true);
    _server = null;
    _ruleMatcher.reset();
    _logger.log('代理服务器已停止');
  }
}
