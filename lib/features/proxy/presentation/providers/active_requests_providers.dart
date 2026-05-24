import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/features/proxy/domain/entities/active_request_info.dart';

class ActiveRequestsNotifier extends Notifier<List<ActiveRequestInfo>> {
  @override
  List<ActiveRequestInfo> build() => [];

  void register(ActiveRequestInfo info) {
    state = [...state, info];
  }

  void unregister(int logId) {
    state = state.where((r) => r.logId != logId).toList();
  }

  Future<void> disconnect(int logId) async {
    final info = state.where((r) => r.logId == logId).firstOrNull;
    if (info == null) return;
    try {
      info.clientRequest.response.statusCode = HttpStatus.clientClosedRequest;
      info.clientRequest.response.write('Request cancelled by user');
      await info.clientRequest.response.close();
    } catch (_) {}
    unregister(logId);
  }

  void clearAll() {
    for (final info in state) {
      try {
        info.clientRequest.response.statusCode = HttpStatus.serviceUnavailable;
        info.clientRequest.response.write('Proxy server stopped');
        info.clientRequest.response.close();
      } catch (_) {}
    }
    state = [];
  }
}

final activeRequestsProvider =
    NotifierProvider<ActiveRequestsNotifier, List<ActiveRequestInfo>>(
  ActiveRequestsNotifier.new,
);
