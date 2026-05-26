import 'dart:convert';
import 'dart:io';

import 'package:llm_proxy/features/rules/domain/entities/model_provider.dart';

class RemoteModel {
  final String id;
  final String? displayName;
  final int? created;

  const RemoteModel({required this.id, this.displayName, this.created});
}

class ModelListService {
  final Map<String, HttpClient> _clientPool = {};

  HttpClient _getClient(String host) {
    if (_clientPool.containsKey(host)) {
      return _clientPool[host]!;
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    _clientPool[host] = client;
    return client;
  }

  void dispose() {
    for (final client in _clientPool.values) {
      client.close(force: true);
    }
    _clientPool.clear();
  }

  Future<List<RemoteModel>> fetchModels(ModelProvider provider) async {
    var baseUrl = provider.baseUrl;
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    final url = '$baseUrl/v1/models';
    final uri = Uri.parse(url);
    final client = _getClient(uri.host);

    final request = await client.getUrl(uri);
    request.headers.contentType = ContentType.json;

    if (provider.apiKey.isNotEmpty) {
      request.headers.add('Authorization', 'Bearer ${provider.apiKey}');
    }

    final response = await request.close();
    if (response.statusCode != 200) {
      final body = await response.transform(utf8.decoder).join();
      throw HttpException(
        '获取模型列表失败 (${response.statusCode}): $body',
      );
    }

    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final data = json['data'] as List<dynamic>? ?? [];

    return data.map((item) {
      final map = item as Map<String, dynamic>;
      return RemoteModel(
        id: map['id'] as String,
        displayName: map['display_name'] as String?,
        created: map['created'] as int?,
      );
    }).toList();
  }
}
