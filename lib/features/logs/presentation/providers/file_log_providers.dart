import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/features/logs/data/datasources/log_file_parser.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';

/// 日志过滤条件
class FileLogFilter {
  final String keyword;           // 关键词搜索（匹配模型、转发目标、路径）
  final String? modelFilter;      // 按模型筛选（null=全部）
  final String? forwardToFilter;  // 按转发目标筛选（null=全部）

  const FileLogFilter({
    this.keyword = '',
    this.modelFilter,
    this.forwardToFilter,
  });

  bool get isEmpty => keyword.isEmpty && modelFilter == null && forwardToFilter == null;

  FileLogFilter copyWith({
    String? keyword,
    String? modelFilter,
    String? forwardToFilter,
    bool clearModelFilter = false,
    bool clearForwardToFilter = false,
  }) {
    return FileLogFilter(
      keyword: keyword ?? this.keyword,
      modelFilter: clearModelFilter ? null : (modelFilter ?? this.modelFilter),
      forwardToFilter: clearForwardToFilter ? null : (forwardToFilter ?? this.forwardToFilter),
    );
  }

  /// 判断 entry 是否符合过滤条件
  bool matches(FileLogEntry entry) {
    if (keyword.isNotEmpty) {
      final kw = keyword.toLowerCase();
      final matchModel = entry.model?.toLowerCase().contains(kw) == true;
      final matchForward = entry.forwardTo?.toLowerCase().contains(kw) == true;
      final matchPath = entry.path.toLowerCase().contains(kw);
      if (!matchModel && !matchForward && !matchPath) return false;
    }
    if (modelFilter != null && entry.model != modelFilter) return false;
    if (forwardToFilter != null && entry.forwardTo != forwardToFilter) return false;
    return true;
  }

  /// 从所有 entries 中提取可用的模型列表（去重）
  static List<String> availableModels(List<FileLogEntry> entries) {
    return entries.map((e) => e.model).whereType<String>().toSet().toList()..sort();
  }

  /// 从所有 entries 中提取可用的转发目标列表（去重）
  static List<String> availableForwardTos(List<FileLogEntry> entries) {
    return entries.map((e) => e.forwardTo).whereType<String>().toSet().toList()..sort();
  }
}

/// 日志输出文件的加载状态
class FileLogState {
  final List<FileLogEntry> entries;
  final String? filePath;
  final String? error;
  final bool isLoading;
  final FileLogFilter filter;       // 当前过滤条件

  const FileLogState({
    this.entries = const [],
    this.filePath,
    this.error,
    this.isLoading = false,
    this.filter = const FileLogFilter(),
  });

  FileLogState copyWith({
    List<FileLogEntry>? entries,
    String? filePath,
    String? error,
    bool? isLoading,
    FileLogFilter? filter,
  }) {
    return FileLogState(
      entries: entries ?? this.entries,
      filePath: filePath ?? this.filePath,
      error: error,
      isLoading: isLoading ?? this.isLoading,
      filter: filter ?? this.filter,
    );
  }

  /// 应用过滤条件后的条目列表
  List<FileLogEntry> get filteredEntries {
    if (filter.isEmpty) return entries;
    return entries.where(filter.matches).toList();
  }
}

/// 管理日志输出文件的加载、解析
class FileLogNotifier extends Notifier<FileLogState> {
  @override
  FileLogState build() => const FileLogState();

  /// 从指定路径加载日志文件（自动识别 .log 和 .json 格式）
  Future<void> loadFile(String path) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final file = File(path);
      if (!await file.exists()) {
        state = state.copyWith(isLoading: false, error: '文件不存在: $path');
        return;
      }

      final List<FileLogEntry> entries;

      if (path.endsWith('.log')) {
        entries = await LogFileParser.parseFile(path);
      } else {
        final content = await file.readAsString();
        final list = jsonDecode(content) as List<dynamic>;
        entries = [
          for (var i = 0; i < list.length; i++)
            FileLogEntry.fromJson(list[i] as Map<String, dynamic>, i),
        ];
      }

      state = FileLogState(
        entries: entries,
        filePath: path,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '解析失败: $e');
    }
  }

  /// 加载日志目录下所有 .log 文件，合并解析
  Future<void> loadDirectory(String dir) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final directory = Directory(dir);
      if (!await directory.exists()) {
        state = state.copyWith(isLoading: false, error: '目录不存在: $dir');
        return;
      }

      final allEntries = <FileLogEntry>[];
      var offset = 0;

      await for (final entity in directory.list()) {
        if (entity is File && entity.path.endsWith('.log')) {
          try {
            final entries = await LogFileParser.parseFile(entity.path);
            for (final e in entries) {
              allEntries.add(FileLogEntry(
                timestamp: e.timestamp,
                method: e.method,
                path: e.path,
                model: e.model,
                forwardTo: e.forwardTo,
                durationMs: e.durationMs,
                firstByteMs: e.firstByteMs,
                statusCode: e.statusCode,
                request: e.request,
                response: e.response,
                index: offset++,
              ));
            }
          } catch (_) {
            // 单个文件解析失败不影响其他文件
          }
        }
      }

      state = FileLogState(
        entries: allEntries,
        filePath: dir,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '加载目录失败: $e');
    }
  }

  /// 设置过滤条件
  void setFilter(FileLogFilter filter) {
    state = state.copyWith(filter: filter);
  }

  /// 清空已加载的日志
  void clear() {
    state = const FileLogState();
  }
}

final logOutputProvider =
    NotifierProvider<FileLogNotifier, FileLogState>(FileLogNotifier.new);
