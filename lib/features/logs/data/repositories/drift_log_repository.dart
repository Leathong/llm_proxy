import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:llm_proxy/core/database/app_database.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_entry.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';
import 'package:llm_proxy/features/logs/domain/repositories/log_repository.dart';

class DriftLogRepository implements LogRepository {
  final AppDatabase _db;
  final StreamController<void> _changeController =
      StreamController<void>.broadcast();

  DriftLogRepository(this._db);

  @override
  Stream<void> get changeStream => _changeController.stream;

  @override
  Future<int> get logCount async =>
      (await _db.select(_db.proxyLogs).get()).length;

  ProxyLogsCompanion _entryToRow(LogEntry e) {
    return ProxyLogsCompanion(
      method: drift.Value(e.method),
      path: drift.Value(e.path),
      time: drift.Value(e.time),
      model: drift.Value(e.model),
      targetEndpoint: drift.Value(e.targetEndpoint),
      statusCode: drift.Value(e.statusCode),
      error: drift.Value(e.error),
      requestDurationMs: drift.Value(e.requestDurationMs),
      firstByteMs: drift.Value(e.firstByteDurationMs),
      status: drift.Value(logStatusToInt(e.status)),
      requestBody: drift.Value(e.requestBody),
      responseBody: drift.Value(e.responseBody),
      requestModel: drift.Value(e.parsedRequest?.model),
      requestStream: e.parsedRequest?.stream != null
          ? drift.Value(e.parsedRequest!.stream! ? 1 : 0)
          : const drift.Value.absent(),
      requestMessagesJson: e.parsedRequest?.messages.isNotEmpty == true
          ? drift.Value(jsonEncode(
              e.parsedRequest!.messages.map((m) => m.toJson()).toList()))
          : const drift.Value.absent(),
      requestSystemPrompt: drift.Value(e.parsedRequest?.systemFull),
      requestToolsJson: e.parsedRequest?.tools?.isNotEmpty == true
          ? drift.Value(jsonEncode(
              e.parsedRequest!.tools!.map((t) => t.toJson()).toList()))
          : const drift.Value.absent(),
      requestOtherParamsJson: e.parsedRequest?.otherParams != null
          ? drift.Value(jsonEncode(e.parsedRequest!.otherParams))
          : const drift.Value.absent(),
      responseModel: drift.Value(e.parsedResponse?.model),
      responseType: drift.Value(e.parsedResponse?.type),
      stopReason: drift.Value(e.parsedResponse?.stopReason),
      responseUsageJson: e.parsedResponse?.usage != null
          ? drift.Value(jsonEncode({
              if (e.parsedResponse!.usage!.cacheCreationInputTokens != null)
                'cache_creation_input_tokens':
                    e.parsedResponse!.usage!.cacheCreationInputTokens,
              if (e.parsedResponse!.usage!.cacheReadInputTokens != null)
                'cache_read_input_tokens':
                    e.parsedResponse!.usage!.cacheReadInputTokens,
              if (e.parsedResponse!.usage!.inputTokens != null)
                'input_tokens': e.parsedResponse!.usage!.inputTokens,
              if (e.parsedResponse!.usage!.outputTokens != null)
                'output_tokens': e.parsedResponse!.usage!.outputTokens,
              if (e.parsedResponse!.usage!.serviceTier != null)
                'service_tier': e.parsedResponse!.usage!.serviceTier,
            }))
          : const drift.Value.absent(),
      responseContentJson: e.parsedResponse?.content?.isNotEmpty == true
          ? drift.Value(jsonEncode(
              e.parsedResponse!.content!.map((c) => c.toJson()).toList()))
          : const drift.Value.absent(),
      responseId: drift.Value(e.parsedResponse?.id),
    );
  }

  LogEntry _rowToEntry(ProxyLog r) {
    FileLogRequest? parsedReq;
    if (r.requestMessagesJson != null || r.requestSystemPrompt != null) {
      List<FileLogMessage> messages = [];
      if (r.requestMessagesJson != null) {
        try {
          final list = jsonDecode(r.requestMessagesJson!) as List;
          messages = list
              .map((m) => FileLogMessage.fromJson(m as Map<String, dynamic>))
              .toList();
        } catch (_) {}
      }

      List<FileLogToolDef>? tools;
      if (r.requestToolsJson != null) {
        try {
          final list = jsonDecode(r.requestToolsJson!) as List;
          tools = list
              .map((t) => FileLogToolDef.fromJson(t as Map<String, dynamic>))
              .toList();
        } catch (_) {}
      }

      Map<String, dynamic>? otherParams;
      if (r.requestOtherParamsJson != null) {
        try {
          otherParams =
              jsonDecode(r.requestOtherParamsJson!) as Map<String, dynamic>;
        } catch (_) {}
      }

      parsedReq = FileLogRequest(
        model: r.requestModel,
        stream: r.requestStream == 1,
        messages: messages,
        systemPreview: r.requestSystemPrompt != null &&
                r.requestSystemPrompt!.length > 500
            ? '${r.requestSystemPrompt!.substring(0, 500)}... '
                '(${r.requestSystemPrompt!.length} chars total)'
            : r.requestSystemPrompt,
        systemFull: r.requestSystemPrompt,
        tools: tools,
        otherParams: otherParams,
      );
    }

    FileLogResponse? parsedResp;
    if (r.responseType != null ||
        r.responseUsageJson != null ||
        r.responseContentJson != null) {
      FileLogUsage? usage;
      if (r.responseUsageJson != null) {
        try {
          final map = jsonDecode(r.responseUsageJson!) as Map<String, dynamic>;
          usage = FileLogUsage.fromJson(map);
        } catch (_) {}
      }

      List<FileLogContentBlock>? content;
      if (r.responseContentJson != null) {
        try {
          final list = jsonDecode(r.responseContentJson!) as List;
          content = list
              .map((c) =>
                  FileLogContentBlock.fromJson(c as Map<String, dynamic>))
              .toList();
        } catch (_) {}
      }

      parsedResp = FileLogResponse(
        type: r.responseType,
        model: r.responseModel,
        stopReason: r.stopReason,
        usage: usage,
        content: content,
        id: r.responseId,
      );
    }

    return LogEntry(
      id: r.id,
      time: r.time,
      method: r.method,
      path: r.path,
      model: r.model,
      targetEndpoint: r.targetEndpoint,
      statusCode: r.statusCode,
      error: r.error,
      requestDurationMs: r.requestDurationMs ?? 0,
      firstByteDurationMs: r.firstByteMs,
      status: logStatusFromInt(r.status),
      requestBody: r.requestBody,
      responseBody: r.responseBody,
      parsedRequest: parsedReq,
      parsedResponse: parsedResp,
    );
  }

  @override
  Future<LogEntry?> getLog(int id) async {
    final rows = await (_db.select(_db.proxyLogs)
          ..where((t) => t.id.equals(id)))
        .get();
    if (rows.isEmpty) return null;
    return _rowToEntry(rows.first);
  }

  @override
  Future<List<LogEntry>> getLogs({
    int? offset,
    int? limit,
    bool desc = true,
  }) async {
    final query = _db.select(_db.proxyLogs)
      ..orderBy([
        (t) => drift.OrderingTerm(
              expression: t.id,
              mode: desc ? drift.OrderingMode.desc : drift.OrderingMode.asc,
            ),
      ])
      ..limit(limit ?? 1000, offset: offset ?? 0);
    final rows = await query.get();
    return rows.map(_rowToEntry).toList();
  }

  @override
  Future<List<LogEntry>> searchLogs({
    String? keyword,
    String? modelFilter,
    String? endpointFilter,
    int? offset,
    int? limit,
    bool desc = true,
  }) async {
    var query = _db.select(_db.proxyLogs)
      ..orderBy([
        (t) => drift.OrderingTerm(
              expression: t.id,
              mode: desc ? drift.OrderingMode.desc : drift.OrderingMode.asc,
            ),
      ])
      ..limit(limit ?? 1000, offset: offset ?? 0);

    if (keyword != null && keyword.isNotEmpty) {
      final kw = '%$keyword%';
      query = query..where((t) => t.model.like(kw) | t.targetEndpoint.like(kw) | t.path.like(kw));
    }
    if (modelFilter != null && modelFilter.isNotEmpty) {
      query = query..where((t) => t.model.equals(modelFilter));
    }
    if (endpointFilter != null && endpointFilter.isNotEmpty) {
      query = query..where((t) => t.targetEndpoint.equals(endpointFilter));
    }

    final rows = await query.get();
    return rows.map(_rowToEntry).toList();
  }

  @override
  Future<List<LogEntry>> getRange(int start, int end) async {
    final rows = await (_db.select(_db.proxyLogs)
          ..where((t) => t.id.isBetween(drift.Constant(start), drift.Constant(end)))
          ..orderBy([(t) => drift.OrderingTerm(expression: t.id)]))
        .get();
    return rows.map(_rowToEntry).toList();
  }

  @override
  Future<int> addLog(LogEntry log) async {
    final id = await _db.into(_db.proxyLogs).insert(_entryToRow(log));
    _changeController.add(null);
    return id;
  }

  @override
  Future<void> updateLog(LogEntry updatedLog) async {
    await (_db.update(_db.proxyLogs)
          ..where((t) => t.id.equals(updatedLog.id)))
        .write(_entryToRow(updatedLog));
    _changeController.add(null);
  }

  @override
  Future<void> clearLogs() async {
    await _db.delete(_db.proxyLogs).go();
    _changeController.add(null);
  }

  @override
  Future<void> deleteLog(int id) async {
    await (_db.delete(_db.proxyLogs)..where((t) => t.id.equals(id))).go();
    _changeController.add(null);
  }
}
