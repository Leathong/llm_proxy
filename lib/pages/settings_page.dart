import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import '../providers/config_provider.dart';

/// 在 macOS 上使用 osascript 打开原生文件夹选择对话框
Future<String?> _pickDirectory() async {
  try {
    final result = await Process.run('osascript', [
      '-e',
      'set folderPath to choose folder with prompt "选择日志文件保存目录"',
      '-e',
      'return POSIX path of folderPath',
    ]);
    if (result.exitCode == 0) {
      final path = (result.stdout as String).trim();
      if (path.isNotEmpty) {
        // 默认文件名
        return '${path}llm_proxy_requests.log';
      }
    }
  } catch (_) {}
  return null;
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isGenerating = false;

  Future<void> _showCertDomainsDialog(BuildContext context, ConfigProvider configProvider) async {
    final controller = TextEditingController(text: configProvider.certDomains.join('\n'));
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('配置证书域名 (SAN)'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('每行一个域名或 IP。生成证书时会写入 subjectAltName。'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 8,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '例如:\napi.openai.com\nlocalhost\n127.0.0.1',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (saved == true) {
      final raw = controller.text;
      final parts = raw
          .split(RegExp(r'[\n,，\s]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final unique = <String>[];
      for (final p in parts) {
        if (!unique.contains(p)) unique.add(p);
      }
      await configProvider.setCertDomains(unique);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('证书域名已保存')),
        );
      }
    }
  }

  Future<void> _generateCertificate(BuildContext context, ConfigProvider configProvider) async {
    setState(() {
      _isGenerating = true;
    });

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final proxyDir = Directory('${docDir.path}/llm_proxy');
      if (!await proxyDir.exists()) {
        await proxyDir.create(recursive: true);
      }

      final keyPath = '${proxyDir.path}/key.pem';
      final certPath = '${proxyDir.path}/cert.pem';
      final confPath = '${proxyDir.path}/openssl.cnf';

      final domains = configProvider.certDomains.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      final effectiveDomains = domains.isNotEmpty ? domains : const ['localhost'];
      final cn = effectiveDomains.first;
      final san = effectiveDomains.map((d) {
        final ip = InternetAddress.tryParse(d);
        if (ip != null) return 'IP:$d';
        return 'DNS:$d';
      }).join(',');

      final conf = [
        '[req]',
        'distinguished_name=req_distinguished_name',
        'x509_extensions=v3_req',
        'prompt=no',
        '',
        '[req_distinguished_name]',
        'CN=$cn',
        '',
        '[v3_req]',
        'subjectAltName=$san',
        'keyUsage=digitalSignature,keyEncipherment',
        'extendedKeyUsage=serverAuth',
        '',
      ].join('\n');

      await File(confPath).writeAsString(conf);

      final result = await Process.run('/usr/bin/openssl', [
        'req', '-x509', '-newkey', 'rsa:2048',
        '-keyout', keyPath,
        '-out', certPath,
        '-days', '3650',
        '-nodes',
        '-sha256',
        '-config', confPath,
      ]);

      if (result.exitCode == 0) {
        await configProvider.setCertPaths(certPath, keyPath);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('证书生成成功并已保存配置')),
          );
        }
      } else {
        throw Exception(result.stderr);
      }
    } catch (e, stackTrace) {
      debugPrint('【证书生成错误】: $e\n$stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成证书失败: $e')),
        );
      }
    } finally {
      if (context.mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  void _showHostsGuide(BuildContext context, ConfigProvider configProvider) {
    final domains = configProvider.certDomains.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final effectiveDomains = domains.isNotEmpty ? domains : const ['api.openai.com'];
    final hostsLines = effectiveDomains.map((d) => '127.0.0.1 $d').join('\n');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('系统 Hosts 修改指引'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('要使代理生效，您需要修改系统的 hosts 文件，将请求指向本地代理。'),
              const SizedBox(height: 16),
              const Text('建议添加以下内容:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SelectableText(hostsLines),
              const SizedBox(height: 16),
              const Text('macOS:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SelectableText(
                '1. 打开终端\n2. 输入命令: sudo nano /etc/hosts\n3. 粘贴上面的 hosts 内容\n4. 保存并退出 (Ctrl+O, Enter, Ctrl+X)',
              ),
              const SizedBox(height: 16),
              const SelectableText(
                '证书信任（macOS）:\n1. 双击打开 cert.pem（或在“钥匙串访问”中导入）\n2. 导入到“系统”钥匙串\n3. 双击该证书，展开“信任”，将“使用此证书时”设置为“始终信任”\n4. 重新启动需要走代理的客户端/IDE',
              ),
              const SizedBox(height: 16),
              const Text('注意:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              const Text('使用 HTTPS 代理时，需将生成的 cert.pem 安装为受信任证书，否则客户端会因证书不受信任而报错。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('了解'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 获取 ConfigProvider 实例，通过 listen: false 在非重建的地方调用方法
    final configProvider = Provider.of<ConfigProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置与证书'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '全局设置',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            if (!configProvider.isInitialized)
              const Center(child: CircularProgressIndicator())
            else ...[
              // 代理端口设置
              Row(
                children: [
                  const Text('代理端口: ', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 150,
                    child: TextFormField(
                      initialValue: configProvider.proxyPort.toString(),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      ),
                      onChanged: (val) {
                        final port = int.tryParse(val);
                        if (port != null) {
                          configProvider.setProxyPort(port);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // 系统代理开关
              Row(
                children: [
                  const Text('开启系统代理: ', style: TextStyle(fontSize: 16)),
                  Switch(
                    value: configProvider.enableSystemProxy,
                    onChanged: (val) {
                      configProvider.setEnableSystemProxy(val);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // 日志文件路径配置
              Row(
                children: [
                  const Text('请求日志文件: ', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(text: configProvider.logFilePath)
                        ..selection = TextSelection.collapsed(offset: configProvider.logFilePath.length),
                      decoration: InputDecoration(
                        hintText: '留空则不记录请求日志',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.folder_open, size: 20),
                          tooltip: '选择日志文件路径',
                          onPressed: () async {
                            // macOS 上使用原生文件夹选择对话框
                            final result = await _pickDirectory();
                            if (result != null && context.mounted) {
                              configProvider.setLogFilePath(result);
                            }
                          },
                        ),
                      ),
                      onChanged: (val) {
                        configProvider.setLogFilePath(val);
                      },
                    ),
                  ),
                ],
              ),
              if (configProvider.logFilePath.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 110),
                  child: Text(
                    '日志将追加写入: ${configProvider.logFilePath}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
            ],
            const Divider(height: 40),
            const Text(
              '证书管理',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            if (configProvider.certPath != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('当前证书路径: ${configProvider.certPath}'),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.folder_open, size: 20),
                      tooltip: '打开证书所在文件夹',
                      onPressed: () {
                        final dir = File(configProvider.certPath!).parent.path;
                        Process.run('open', [dir]);
                      },
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Text('证书域名(SAN): ${configProvider.certDomains.join(', ')}'),
            ),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showCertDomainsDialog(context, configProvider),
                  icon: const Icon(Icons.domain_outlined),
                  label: const Text('配置证书域名'),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _isGenerating ? null : () => _generateCertificate(context, configProvider),
                  icon: _isGenerating 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.security),
                  label: const Text('生成自签名证书'),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: () => _showHostsGuide(context, configProvider),
                  icon: const Icon(Icons.help_outline),
                  label: const Text('Hosts 修改指引'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
