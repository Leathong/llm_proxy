import 'dart:io';

import 'package:llm_proxy/features/logs/data/datasources/log_file_exporter.dart';
import 'package:llm_proxy/features/logs/domain/repositories/log_repository.dart';
import 'package:llm_proxy/features/proxy/domain/services/proxy_logger.dart';
import 'package:llm_proxy/features/proxy/domain/services/request_forwarder.dart';
import 'package:llm_proxy/features/proxy/domain/services/request_router.dart';
import 'package:llm_proxy/features/proxy/domain/services/request_transformer.dart';
import 'package:llm_proxy/features/proxy/domain/services/rule_matcher.dart';
import 'package:llm_proxy/features/rules/domain/repositories/rule_repository.dart';

class ProxyServerDataSource {
  HttpServer? _server;
  bool get isRunning => _server != null;
  int _port = 8080;

  final RuleMatcher _ruleMatcher;
  final RequestTransformer _transformer;
  final RequestForwarder _forwarder;
  final LogFileExporter _logWriter;
  final LogRepository _logRepository;
  late final ProxyLogger _logger;
  late final RequestRouter _router;

  ProxyServerDataSource({
    required RuleMatcher ruleMatcher,
    required RequestTransformer transformer,
    required RequestForwarder forwarder,
    required LogFileExporter logWriter,
    required LogRepository logRepository,
    required RuleRepository ruleRepository,
    void Function(String message)? onLog,
  })  : _ruleMatcher = ruleMatcher,
        _transformer = transformer,
        _forwarder = forwarder,
        _logWriter = logWriter,
        _logRepository = logRepository {
    _logger = ProxyLogger(onLog: onLog);
    _router = RequestRouter(
      ruleRepository: ruleRepository,
      logger: _logger,
      ruleMatcher: _ruleMatcher,
      transformer: _transformer,
      forwarder: _forwarder,
      logRepository: _logRepository,
    );
  }

  void setLogFileDir(String dir) {
    _logWriter.setLogFileDir(dir);
  }

  LogFileExporter get logWriter => _logWriter;

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
