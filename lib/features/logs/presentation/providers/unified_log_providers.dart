import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:llm_proxy/features/logs/data/datasources/log_file_parser.dart';
import 'package:llm_proxy/features/logs/data/datasources/log_file_writer.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_entry.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_stats.dart';
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
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final UnifiedLogFilter filter;
  final int? rangeStart;
  final int? rangeEnd;
  final bool reversed;
  final bool subtractFirstByte;
  final LogStats? stats;

  /// 缓存当前过滤/排序后的显示列表，每个元素携带在 allEntries 中的真实序号
  final List<({LogEntry entry, int seq})> displayEntries;

  const UnifiedLogState({
    this.allEntries = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.filter = const UnifiedLogFilter(),
    this.rangeStart,
    this.rangeEnd,
    this.reversed = false,
    this.subtractFirstByte = false,
    this.stats,
    this.displayEntries = const [],
  });

  UnifiedLogState copyWith({
    List<LogEntry>? allEntries,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    UnifiedLogFilter? filter,
    int? rangeStart,
    int? rangeEnd,
    bool? reversed,
    bool? subtractFirstByte,
    LogStats? stats,
    List<({LogEntry entry, int seq})>? displayEntries,
    bool clearRange = false,
    bool clearError = false,
    bool clearStats = false,
  }) {
    return UnifiedLogState(
      allEntries: allEntries ?? this.allEntries,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
      filter: filter ?? this.filter,
      rangeStart: clearRange ? null : (rangeStart ?? this.rangeStart),
      rangeEnd: clearRange ? null : (rangeEnd ?? this.rangeEnd),
      reversed: reversed ?? this.reversed,
      subtractFirstByte: subtractFirstByte ?? this.subtractFirstByte,
      stats: clearStats ? null : (stats ?? this.stats),
      displayEntries: displayEntries ?? this.displayEntries,
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
  StreamSubscription<LogChangeEvent>? _changeSub;
  LogRepository get _repo => ref.read(logRepositoryProvider);

  static const int _pageSize = 100;

  @override
  UnifiedLogState build() {
    _loadInitial();
    _changeSub = _repo.changeStream.listen(_handleChangeEvent);
    ref.onDispose(() => _changeSub?.cancel());
    return const UnifiedLogState(isLoading: true);
  }

  void _handleChangeEvent(LogChangeEvent event) {
    switch (event) {
      case LogAddedEvent e:
        _handleLogAdded(e.id);
      case LogUpdatedEvent e:
        _handleLogUpdated(e.id);
      case LogDeletedEvent e:
        _handleLogDeleted(e.ids);
      case LogClearedEvent():
        _reloadAll();
    }
  }

  Future<void> _handleLogAdded(int newId) async {
    if (state.isLoading) {
      _reloadAll();
      return;
    }
    try {
      final newLog = await _repo.getLog(newId);
      if (newLog == null) {
        _reloadAll();
        return;
      }
      final s = state;
      final entries = s.allEntries;
      if (entries.any((e) => e.id == newId)) {
        _handleLogUpdated(newId);
        return;
      }
      state = state.copyWith(
        allEntries: [newLog, ...entries],
        hasMore: true,
        clearError: true,
      );
      _rebuildDisplay();
      _computeStats();
    } catch (_) {
      _reloadAll();
    }
  }

  Future<void> _handleLogUpdated(int updatedId) async {
    if (state.isLoading) {
      _reloadAll();
      return;
    }
    try {
      final updatedLog = await _repo.getLog(updatedId);
      if (updatedLog == null) {
        _handleLogDeleted([updatedId]);
        return;
      }
      final s = state;
      final entries = s.allEntries;
      final idx = entries.indexWhere((e) => e.id == updatedId);
      if (idx == -1) {
        _handleLogAdded(updatedId);
        return;
      }
      final newEntries = [...entries];
      newEntries[idx] = updatedLog;
      state = state.copyWith(allEntries: newEntries);
      _rebuildDisplay();
      _computeStats();
    } catch (_) {
      _reloadAll();
    }
  }

  void _handleLogDeleted(List<int> deletedIds) {
    if (state.isLoading) return;
    final s = state;
    final idsSet = deletedIds.toSet();
    final newEntries = s.allEntries.where((e) => !idsSet.contains(e.id)).toList();
    state = state.copyWith(allEntries: newEntries);
    _rebuildDisplay();
    _computeStats();
  }

  /// 根据当前 allEntries / filter / range / reversed 重建 displayEntries 缓存
  void _rebuildDisplay() {
    final s = state;
    final rangeEntries = s.rangeEntries;
    final filtered = s.filter.isEmpty
        ? rangeEntries
        : rangeEntries.where(s.filter.matches).toList();
    final all = s.allEntries;
    final display = (s.reversed ? filtered.reversed.toList() : filtered)
        .map((e) => (entry: e, seq: all.indexOf(e) + 1))
        .toList();
    state = state.copyWith(displayEntries: display);
  }

  Future<void> _loadInitial() async {
    try {
      final entries = await _repo.getLogs(limit: _pageSize, desc: true);
      state = state.copyWith(
        allEntries: entries,
        isLoading: false,
        hasMore: entries.length >= _pageSize,
        clearError: true,
      );
      _rebuildDisplay();
      _computeStats();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '加载日志失败: $e');
    }
  }

  Future<void> loadMore() async {
    final s = state;
    if (s.isLoadingMore || !s.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final lastId = s.allEntries.last.id;
      final more = await _repo.getLogs(
        limit: _pageSize,
        desc: true,
        cursor: lastId,
      );
      state = state.copyWith(
        allEntries: [...s.allEntries, ...more],
        isLoadingMore: false,
        hasMore: more.length >= _pageSize,
      );
      _rebuildDisplay();
      _computeStats();
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: '加载更多失败: $e');
    }
  }

  Future<void> _reloadAll() async {
    try {
      final entries = await _repo.getLogs(limit: _pageSize, desc: true);
      state = state.copyWith(
        allEntries: entries,
        isLoading: false,
        hasMore: entries.length >= _pageSize,
        clearError: true,
      );
      _rebuildDisplay();
      _computeStats();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '加载日志失败: $e');
    }
  }

  void _computeStats() {
    final s = state;
    final entries = _toFileLogEntries(s.filteredEntries);
    final stats = LogStats.compute(entries, subtractFirstByte: s.subtractFirstByte);
    state = state.copyWith(stats: stats);
  }

  List<FileLogEntry> _toFileLogEntries(List<LogEntry> entries) {
    return entries.asMap().entries.map((e) {
      final log = e.value;
      return FileLogEntry(
        timestamp: DateFormat('HH:mm:ss.SSS').format(log.time),
        method: log.method,
        path: log.path,
        model: log.model,
        forwardTo: log.targetEndpoint,
        durationMs: log.requestDurationMs,
        firstByteMs: log.firstByteDurationMs,
        statusCode: log.statusCode,
        request: log.parsedRequest,
        response: log.parsedResponse,
        index: e.key,
      );
    }).toList();
  }

  void setReversed(bool v) {
    state = state.copyWith(reversed: v);
    _rebuildDisplay();
    _computeStats();
  }

  void setSubtractFirstByte(bool v) {
    state = state.copyWith(subtractFirstByte: v);
    _computeStats();
  }

  void setFilter(UnifiedLogFilter filter) {
    state = state.copyWith(filter: filter);
    _rebuildDisplay();
    _computeStats();
  }

  void setRange(int start, int end) {
    final len = state.allEntries.length;
    final clampedStart = start.clamp(0, len);
    final clampedEnd = end.clamp(clampedStart, len);
    state = state.copyWith(rangeStart: clampedStart, rangeEnd: clampedEnd);
    _rebuildDisplay();
    _computeStats();
  }

  void clearRange() {
    state = state.copyWith(clearRange: true);
    _rebuildDisplay();
    _computeStats();
  }

  void clearMemory() {
    state = state.copyWith(
      allEntries: const [],
      displayEntries: const [],
      stats: null,
      hasMore: true,
      clearRange: true,
      clearError: true,
    );
  }

  Future<void> deleteFilteredLogs() async {
    final ids = state.filteredEntries.map((e) => e.id).toList();
    if (ids.isEmpty) return;
    await _repo.deleteLogs(ids);
  }

  Future<void> exportLogs(String dirPath) async {
    final writer = LogFileWriter();
    writer.setLogFileDir(dirPath);
    writer.setSplitByEndpoint(false);

    final entries = state.filteredEntries;
    for (final entry in entries) {
      await writer.writeLog(
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

  Future<int> importLogs(String filePath) async {
    final parsedEntries = await LogFileParser.parseFile(filePath);
    if (parsedEntries.isEmpty) return 0;

    var importedCount = 0;
    for (final entry in parsedEntries) {
      try {
        final logEntry = _fileLogEntryToLogEntry(entry);
        await _repo.addLog(logEntry);
        importedCount++;
      } catch (e) {
        continue;
      }
    }
    return importedCount;
  }

  LogEntry _fileLogEntryToLogEntry(FileLogEntry entry) {
    DateTime time;
    try {
      time = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').parse(entry.timestamp);
    } catch (_) {
      try {
        time = DateFormat('yyyy-MM-dd HH:mm:ss').parse(entry.timestamp);
      } catch (_) {
        time = DateTime.now();
      }
    }

    return LogEntry(
      id: 0,
      time: time,
      method: entry.method,
      path: entry.path,
      model: entry.model,
      targetEndpoint: entry.forwardTo,
      statusCode: entry.statusCode,
      requestDurationMs: entry.durationMs ?? 0,
      firstByteDurationMs: entry.firstByteMs,
      status: entry.statusCode != null && entry.statusCode! >= 400
          ? LogStatus.error
          : LogStatus.completed,
      parsedRequest: entry.request,
      parsedResponse: entry.response,
    );
  }
}

final unifiedLogProvider =
    NotifierProvider<UnifiedLogNotifier, UnifiedLogState>(
  UnifiedLogNotifier.new,
);
