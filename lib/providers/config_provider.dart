import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:llm_proxy/models/proxy_rule.dart';
import 'package:llm_proxy/models/proxy_log.dart';
import 'package:llm_proxy/services/proxy_server.dart';
import 'package:llm_proxy/providers/log_provider.dart';

/// 配置管理状态提供者，用于持久化存储数据骨架
class ConfigProvider extends ChangeNotifier {
  // SharedPreferences 实例
  SharedPreferences? _prefs;
  
  final LogProvider? logProvider;

  // 示例配置项：代理端口
  int _proxyPort = 8080;
  // 示例配置项：是否开启系统代理
  bool _enableSystemProxy = false;
  
  // 证书路径
  String? _certPath;
  String? _keyPath;
  List<String> _certDomains = const ['localhost', 'api.openai.com'];

  /// 获取证书路径
  String? get certPath => _certPath;
  String? get keyPath => _keyPath;
  List<String> get certDomains => _certDomains;

  // 日志文件路径
  String _logFilePath = '';

  /// 获取日志文件路径
  String get logFilePath => _logFilePath;

  // 代理规则列表
  List<ProxyRule> _proxyRules = [];
  
  // 标志位，表示是否已经初始化完成
  bool _isInitialized = false;

  // 代理服务器实例
  late ProxyServer _proxyServer;

  // 代理服务器是否运行中
  bool get isProxyRunning => _proxyServer.isRunning;

  /// 获取代理端口
  int get proxyPort => _proxyPort;
  
  /// 获取是否开启系统代理
  bool get enableSystemProxy => _enableSystemProxy;

  /// 获取代理规则列表
  List<ProxyRule> get proxyRules => _proxyRules;

  /// 获取初始化状态
  bool get isInitialized => _isInitialized;

  /// 构造函数中启动初始化
  ConfigProvider({this.logProvider}) {
    _proxyServer = ProxyServer(
      getRules: () => _proxyRules,
      onLog: (msg) {
        debugPrint('[ProxyServer] $msg');
        // 可以扩展为通知 LogProvider
      },
      onProxyLog: (proxyLog) {
        logProvider?.addLog(proxyLog);
      },
      onProxyLogUpdate: (proxyLog) {
        // 中间状态（仍为 pending）静默更新，不触发 UI 重建
        final silent = proxyLog.status == LogStatus.pending;
        logProvider?.updateLog(proxyLog, silent: silent);
      },
    );
    _init();
  }

  /// 初始化 SharedPreferences 并加载保存的配置
  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadConfig();
    // 将日志文件路径同步到代理服务器
    _proxyServer.setLogFilePath(_logFilePath);
    _isInitialized = true;
    notifyListeners(); // 通知 UI 更新
  }

  /// 从 SharedPreferences 加载配置数据
  Future<void> _loadConfig() async {
    if (_prefs == null) return;
    
    // 加载配置，如果没有保存过则使用默认值
    _proxyPort = _prefs!.getInt('proxyPort') ?? 8080;
    _enableSystemProxy = _prefs!.getBool('enableSystemProxy') ?? false;
    _certPath = _prefs!.getString('certPath');
    _keyPath = _prefs!.getString('keyPath');
    final savedCertDomains = _prefs!.getStringList('certDomains');
    if (savedCertDomains != null && savedCertDomains.isNotEmpty) {
      _certDomains = savedCertDomains;
    }
    
    // 加载日志文件路径
    _logFilePath = _prefs!.getString('logFilePath') ?? '';
    
    // 加载代理规则
    final rulesJson = _prefs!.getStringList('proxyRules');
    if (rulesJson != null) {
      _proxyRules = rulesJson.map((jsonStr) => ProxyRule.fromJson(jsonStr)).toList();
    }
  }

  /// 保存代理规则列表
  Future<void> _saveProxyRules() async {
    if (_prefs != null) {
      final rulesJson = _proxyRules.map((rule) => rule.toJson()).toList();
      await _prefs!.setStringList('proxyRules', rulesJson);
    }
  }

  /// 添加代理规则
  Future<void> addProxyRule(ProxyRule rule) async {
    _proxyRules.add(rule);
    await _saveProxyRules();
    notifyListeners();
  }

  /// 更新代理规则
  Future<void> updateProxyRule(ProxyRule rule) async {
    final index = _proxyRules.indexWhere((r) => r.id == rule.id);
    if (index != -1) {
      _proxyRules[index] = rule;
      await _saveProxyRules();
      notifyListeners();
    }
  }

  /// 删除代理规则
  Future<void> deleteProxyRule(String id) async {
    _proxyRules.removeWhere((r) => r.id == id);
    await _saveProxyRules();
    notifyListeners();
  }

  /// 切换代理规则激活状态
  Future<void> toggleProxyRule(String id, bool active) async {
    final index = _proxyRules.indexWhere((r) => r.id == id);
    if (index != -1) {
      _proxyRules[index] = _proxyRules[index].copyWith(active: active);
      await _saveProxyRules();
      notifyListeners();
    }
  }

  /// 启动/停止代理服务器
  Future<void> toggleProxyServer() async {
    if (_proxyServer.isRunning) {
      await _proxyServer.stop();
    } else {
      try {
        await _proxyServer.start(
          port: _proxyPort,
          certPath: _certPath,
          keyPath: _keyPath,
        );
      } catch (e, stackTrace) {
        debugPrint('启动代理服务器失败: $e');
        debugPrint('【启动代理服务器失败】: $e\n$stackTrace');
      }
    }
    notifyListeners();
  }

  /// 设置并保存代理端口
  Future<void> setProxyPort(int port) async {
    _proxyPort = port;
    if (_prefs != null) {
      await _prefs!.setInt('proxyPort', port);
    }
    notifyListeners(); // 通知所有监听者数据已更改
  }

  /// 设置并保存系统代理开关状态
  Future<void> setEnableSystemProxy(bool enable) async {
    _enableSystemProxy = enable;
    if (_prefs != null) {
      await _prefs!.setBool('enableSystemProxy', enable);
    }
    notifyListeners();
  }

  /// 设置并保存证书路径
  Future<void> setCertPaths(String certPath, String keyPath) async {
    _certPath = certPath;
    _keyPath = keyPath;
    if (_prefs != null) {
      await _prefs!.setString('certPath', certPath);
      await _prefs!.setString('keyPath', keyPath);
    }
    notifyListeners();
  }

  Future<void> setCertDomains(List<String> domains) async {
    final normalized = domains.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    _certDomains = normalized.isNotEmpty ? normalized : const ['localhost'];
    if (_prefs != null) {
      await _prefs!.setStringList('certDomains', _certDomains);
    }
    notifyListeners();
  }

  /// 设置并保存日志文件路径
  Future<void> setLogFilePath(String path) async {
    _logFilePath = path;
    if (_prefs != null) {
      await _prefs!.setString('logFilePath', path);
    }
    // 同步到代理服务器
    _proxyServer.setLogFilePath(path);
    notifyListeners();
  }
}
