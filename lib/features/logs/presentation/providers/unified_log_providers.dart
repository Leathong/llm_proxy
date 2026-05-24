import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/features/logs/data/datasources/log_file_writer.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_entry.dart';
import 'package:llm_proxy/features/logs/domain/repositories/log_repository.dart';
import 'package:llm_proxy/features/proxy/presentation/providers/proxy_providers.dart';

/// 日志过滤条件
class UnifiedLogFilter {
  final String keyword;
  final String? modelFilter;
  final String? endpointFilter;

  const UnifiedLogFilter({
    this.keyword = '',
    this.modelFilter,
    this.endpointFilter,
  });

  bool get isEmpty =>
      keyword.isEmpty && modelFilter == null && endpointFilter == null;

  bool matches(LogEntry entry) {
    if (keyword.isNotEmpty) {
      final kw = keyword.toLowerCase();
      if (entry.model?.toLowerCase().contains(kw) != true &&
          entry.targetEndpoint?.toLowerCase().contains(kw) != true &&
          !entry.path.toLowerCase().contains(kw)) {
        return false;
      }
    }
    if (modelFilter != null && entry.model != modelFilter) return false;
    if (endpointFilter != null &&
        entry.targetEndpoint != endpointFilter) {
      return false;
    }
    return true;
  }

  static List<String> availableModels(List<LogEntry> entries) {
    return entries
        .map((e) => e.model)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
  }

  static List<String> availableEndpoints(List<LogEntry> entries) {
    return entries
        .map((e) => e.targetEndpoint)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
  }
}

class UnifiedLogState {
  final List<LogEntry> allEntries;
  final bool isLoading;
  final String? error;
  final UnifiedLogFilter filter;
  final int? rangeStart;
  final int? rangeEnd;
  final bool reversed;
  final bool subtractFirstByte;

  const UnifiedLogState({
    this.allEntries = const [],
    this.isLoading = false,
    this.error,
    this.filter = const UnifiedLogFilter(),
    this.rangeStart,
    this.rangeEnd,
    this.reversed = false,
    this.subtractFirstByte = false,
  });

  UnifiedLogState copyWith({
    List<LogEntry>? allEntries,
    bool? isLoading,
    String? error,
    UnifiedLogFilter? filter,
    int? rangeStart,
    int? rangeEnd,
    bool? reversed,
    bool? subtractFirstByte,
    bool clearRange = false,
    bool clearError = false,
  }) {
    return UnifiedLogState(
      allEntries: allEntries ?? this.allEntries,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      filter: filter ?? this.filter,
      rangeStart: clearRange ? null : (rangeStart ?? this.rangeStart),
      rangeEnd: clearRange ? null : (rangeEnd ?? this.rangeEnd),
      reversed: reversed ?? this.reversed,
      subtractFirstByte: subtractFirstByte ?? this.subtractFirstByte,
    );
  }

  List<LogEntry> get rangeEntries {
    if (rangeStart == null || rangeEnd == null) return allEntries;
    final start = rangeStart!.clamp(0, allEntries.length);
    final end = rangeEnd!.clamp(start, allEntries.length);
    if (start >= end) return allEntries;
    return allEntries.sublist(start, end);
  }

  List<LogEntry> get filteredEntries {
    final base = rangeEntries;
    if (filter.isEmpty) return base;
    return base.where(filter.matches).toList();
  }
}

class UnifiedLogNotifier extends Notifier<UnifiedLogState> {
  StreamSubscription<void>? _changeSub;
  LogRepository get _repo => ref.read(logRepositoryProvider);

  @override
  UnifiedLogState build() {
    _loadEntries();
    _changeSub = _repo.changeStream.listen((_) => _loadEntries());
    ref.onDispose(() => _changeSub?.cancel());
    return const UnifiedLogState(isLoading: true);
  }

  Future<void> _loadEntries() async {
    try {
      final entries = await _repo.getLogs(limit: 2000, desc: true);
      state = state.copyWith(
        allEntries: entries,
        isLoading: false,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '加载日志失败: $e');
    }
  }

  void setReversed(bool v) => state = state.copyWith(reversed: v);
  void setSubtractFirstByte(bool v) =>
      state = state.copyWith(subtractFirstByte: v);

  void setFilter(UnifiedLogFilter filter) {
    state = state.copyWith(filter: filter);
  }

  void setRange(int start, int end) {
    final len = state.allEntries.length;
    final clampedStart = start.clamp(0, len);
    final clampedEnd = end.clamp(clampedStart, len);
    state = state.copyWith(rangeStart: clampedStart, rangeEnd: clampedEnd);
  }

  void clearRange() {
    state = state.copyWith(clearRange: true);
  }

  Future<void> clearAllLogs() async {
    await _repo.clearLogs();
  }

  /// 将当前日志导出为 .log 文件
  Future<void> exportLogs(String dirPath) async {
    final writer = LogFileWriter();
    writer.setLogFileDir(dirPath);
    writer.setSplitByEndpoint(false);

    final entries = state.filteredEntries;
    for (final entry in entries) {
      writer.writeLog(
        time: entry.time,
        method: entry.method,
        path: entry.path,
        requestBody: entry.requestBody,
        statusCode: entry.statusCode ?? 0,
        responseBody: entry.responseBody,
        error: entry.error,
        model: entry.model,
        targetEndpoint: entry.targetEndpoint,
        requestDurationMs: entry.requestDurationMs,
        firstByteMs: entry.firstByteDurationMs,
      );
    }
  }
}

final unifiedLogProvider =
    NotifierProvider<UnifiedLogNotifier, UnifiedLogState>(
  UnifiedLogNotifier.new,
);
