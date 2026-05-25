import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:llm_proxy/features/logs/data/datasources/log_file_exporter.dart';
import 'package:llm_proxy/features/logs/data/datasources/log_file_parser.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_entry.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_stats.dart';
import 'package:llm_proxy/features/logs/domain/repositories/log_repository.dart';
import 'package:llm_proxy/features/proxy/presentation/providers/proxy_providers.dart';

/// 日志过滤条件
class LogFilter {
  final String keyword;
  final String? modelFilter;
  final String? endpointFilter;

  const LogFilter({
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

const int pageSizeConst = 20;

/// 显示列表中的条目，携带序号和展开状态
class DisplayEntry {
  final LogEntry entry;
  final int seq;
  final bool isExpanded;

  const DisplayEntry({
    required this.entry,
    required this.seq,
    this.isExpanded = false,
  });

  DisplayEntry copyWith({
    LogEntry? entry,
    int? seq,
    bool? isExpanded,
  }) {
    return DisplayEntry(
      entry: entry ?? this.entry,
      seq: seq ?? this.seq,
      isExpanded: isExpanded ?? this.isExpanded,
    );
  }
}

class LogState {
  final List<LogEntry> allEntries;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final LogFilter filter;
  final int? rangeStart;
  final int? rangeEnd;
  final bool reversed;
  final bool subtractFirstByte;
  final LogStats? stats;
  final int pageSize;

  /// 数据库中的总日志条数
  final int totalCount;

  /// 缓存当前过滤/排序后的显示列表，每个元素携带在 allEntries 中的真实序号和展开状态
  final List<DisplayEntry> displayEntries;

  const LogState({
    this.allEntries = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.filter = const LogFilter(),
    this.rangeStart,
    this.rangeEnd,
    this.reversed = false,
    this.subtractFirstByte = false,
    this.stats,
    this.pageSize = pageSizeConst,
    this.totalCount = 0,
    this.displayEntries = const [],
  });

  LogState copyWith({
    List<LogEntry>? allEntries,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    LogFilter? filter,
    int? rangeStart,
    int? rangeEnd,
    bool? reversed,
    bool? subtractFirstByte,
    LogStats? stats,
    int? pageSize,
    int? totalCount,
    List<DisplayEntry>? displayEntries,
    bool clearRange = false,
    bool clearError = false,
    bool clearStats = false,
  }) {
    return LogState(
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
      pageSize: pageSize ?? this.pageSize,
      totalCount: totalCount ?? this.totalCount,
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

class LogNotifier extends Notifier<LogState> {
  StreamSubscription<LogChangeEvent>? _changeSub;
  LogRepository get _repo => ref.read(logRepositoryProvider);

  @override
  LogState build() {
    _loadInitial();
    _changeSub = _repo.changeStream.listen(_handleChangeEvent);
    ref.onDispose(() => _changeSub?.cancel());
    return const LogState(isLoading: true);
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

  bool get _isFilterOrRangeActive =>
      !state.filter.isEmpty ||
      state.rangeStart != null ||
      state.rangeEnd != null;

  Future<void> _handleLogAdded(int newId) async {
    if (state.isLoading) {
      _reloadAll();
      return;
    }
    if (_isFilterOrRangeActive) return;
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
        clearError: true,
      );
      _rebuildDisplay();
      _computeStats();
      _loadTotalCount();
    } catch (_) {
      _reloadAll();
    }
  }

  Future<void> _handleLogUpdated(int updatedId) async {
    if (state.isLoading) {
      _reloadAll();
      return;
    }
    if (_isFilterOrRangeActive) return;
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
    if (_isFilterOrRangeActive) return;
    final s = state;
    final idsSet = deletedIds.toSet();
    final newEntries = s.allEntries.where((e) => !idsSet.contains(e.id)).toList();
    state = state.copyWith(allEntries: newEntries);
    _rebuildDisplay();
    _computeStats();
    _loadTotalCount();
  }

  /// 根据当前 allEntries / filter / range / reversed 重建 displayEntries 缓存
  void _rebuildDisplay() {
    final s = state;
    final rangeEntries = s.rangeEntries;
    final filtered = s.filter.isEmpty
        ? rangeEntries
        : rangeEntries.where(s.filter.matches).toList();
    final all = s.allEntries;
    final idToIndex = <int, int>{};
    for (var i = 0; i < all.length; i++) {
      idToIndex[all[i].id] = i;
    }
    final oldDisplay = s.displayEntries;
    final oldExpanded = {
      for (final d in oldDisplay) d.entry.id: d.isExpanded,
    };
    final display = (s.reversed ? filtered.reversed.toList() : filtered)
        .map((e) => DisplayEntry(
              entry: e,
              seq: idToIndex[e.id]! + 1,
              isExpanded: oldExpanded[e.id] ?? false,
            ))
        .toList();
    state = state.copyWith(displayEntries: display);
  }

  Future<void> _loadTotalCount() async {
    try {
      final count = await _repo.logCount;
      state = state.copyWith(totalCount: count);
    } catch (_) {}
  }

  Future<void> _loadInitial() async {
    try {
      final entries = await _repo.getLogs(limit: pageSizeConst, desc: true);
      state = state.copyWith(
        allEntries: entries,
        isLoading: false,
        hasMore: entries.length >= pageSizeConst,
        clearError: true,
      );
      _rebuildDisplay();
      _computeStats();
      _loadTotalCount();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '加载日志失败: $e');
    }
  }

  Future<void> loadMore() async {
    final s = state;
    if (s.isLoadingMore || !s.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final pageSize = s.pageSize;
      final lastId = s.allEntries.lastOrNull?.id;
      final more = await _repo.getLogs(
        limit: pageSize,
        desc: true,
        cursor: lastId,
      );
      state = state.copyWith(
        allEntries: [...s.allEntries, ...more],
        isLoadingMore: false,
        hasMore: more.length >= pageSize,
      );
      _rebuildDisplay();
      _computeStats();
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: '加载更多失败: $e');
    }
  }

  Future<void> _reloadAll() async {
    try {
      final entries = await _repo.getLogs(limit: pageSizeConst, desc: true);
      state = state.copyWith(
        allEntries: entries,
        isLoading: false,
        hasMore: entries.length >= pageSizeConst,
        clearError: true,
      );
      _rebuildDisplay();
      _computeStats();
      _loadTotalCount();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '加载日志失败: $e');
    }
  }

  void setPageSize(int pageSize) {
    if (pageSize < 1) return;
    state = state.copyWith(pageSize: pageSize);
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

  /// 切换指定日志条目的展开/收起状态
  void toggleExpanded(int entryId) {
    final newDisplay = state.displayEntries.map((d) {
      if (d.entry.id == entryId) {
        return d.copyWith(isExpanded: !d.isExpanded);
      }
      return d;
    }).toList();
    state = state.copyWith(displayEntries: newDisplay);
  }

  void setFilter(LogFilter filter) {
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
      totalCount: 0,
      clearRange: true,
      clearError: true,
    );
  }

  Future<void> deleteFilteredLogs() async {
    final ids = state.filteredEntries.map((e) => e.id).toList();
    if (ids.isEmpty) return;
    await _repo.deleteLogs(ids);
  }

  Future<void> clearAllLogs() async {
    await _repo.clearLogs();
  }

  Future<void> exportLogs(String filePath) async {
    await LogFileExporter.exportToFile(
      filePath: filePath,
      entries: state.filteredEntries,
    );
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

final logProvider =
    NotifierProvider<LogNotifier, LogState>(
  LogNotifier.new,
);
