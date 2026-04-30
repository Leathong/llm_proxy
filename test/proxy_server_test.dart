import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_proxy/models/proxy_rule.dart';
import 'package:llm_proxy/services/proxy_server.dart';

void main() {
  group('ProxyServer', () {
    late ProxyServer proxyServer;
    late HttpServer mockTargetServer;
    late List<ProxyRule> rules;
    int proxyPort = 8081;
    int targetPort = 8082;

    setUp(() async {
      rules = [
        ProxyRule(
          id: '1',
          name: 'Test Rule',
          endpoint: 'http://127.0.0.1:$targetPort/api',
          apiKey: 'test_api_key',
          customModelId: 'gpt-4-custom',
          targetModelId: 'gpt-4-target',
          active: true,
        ),
      ];

      proxyServer = ProxyServer(
        getRules: () => rules,
        onLog: (msg) => debugPrint(msg),
      );
      await proxyServer.start(port: proxyPort);

      mockTargetServer = await HttpServer.bind(InternetAddress.loopbackIPv4, targetPort);
      mockTargetServer.listen((request) async {
        if (request.uri.path == '/api/v1/chat/completions') {
          // Verify auth header
          final auth = request.headers.value('authorization');
          if (auth != 'Bearer test_api_key') {
            request.response.statusCode = HttpStatus.unauthorized;
            await request.response.close();
            return;
          }

          // Verify body
          final bodyString = await utf8.decoder.bind(request).join();
          final bodyJson = jsonDecode(bodyString);
          if (bodyJson['model'] != 'gpt-4-target') {
            request.response.statusCode = HttpStatus.badRequest;
            await request.response.close();
            return;
          }

          // Return mock response
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'result': 'success'}));
          await request.response.close();
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      });
    });

    tearDown(() async {
      await proxyServer.stop();
      await mockTargetServer.close(force: true);
    });

    test('should return models list on /v1/models', () async {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:$proxyPort/v1/models'));
      final response = await request.close();
      
      expect(response.statusCode, HttpStatus.ok);
      
      final bodyString = await response.transform(utf8.decoder).join();
      final bodyJson = jsonDecode(bodyString);
      
      expect(bodyJson['object'], 'list');
      expect(bodyJson['data'].length, 1);
      expect(bodyJson['data'][0]['id'], 'gpt-4-custom');
      
      client.close();
    });

    test('should forward chat completions request and replace model ID', () async {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('http://127.0.0.1:$proxyPort/v1/chat/completions'));
      
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'model': 'gpt-4-custom',
        'messages': [{'role': 'user', 'content': 'Hello'}]
      }));
      
      final response = await request.close();
      expect(response.statusCode, HttpStatus.ok);
      
      final bodyString = await response.transform(utf8.decoder).join();
      final bodyJson = jsonDecode(bodyString);
      expect(bodyJson['result'], 'success');
      
      client.close();
    });
  });
}
