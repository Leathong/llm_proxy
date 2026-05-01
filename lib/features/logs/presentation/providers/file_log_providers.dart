import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/features/logs/data/datasources/log_file_parser.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';

/// 日志输出文件的加载状态
class FileLogState {
  final List<FileLogEntry> entries;
  final String? filePath;
  final String? error;
  final bool isLoading;

  const FileLogState({
    this.entries = const [],
    this.filePath,
    this.error,
    this.isLoading = false,
  });

  FileLogState copyWith({
    List<FileLogEntry>? entries,
    String? filePath,
    String? error,
    bool? isLoading,
  }) {
    return FileLogState(
      entries: entries ?? this.entries,
      filePath: filePath ?? this.filePath,
      error: error,
      isLoading: isLoading ?? this.isLoading,
    );
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
        // .log 文本文件：使用内置解析器（Isolate 中执行）
        entries = await LogFileParser.parseFile(path);
      } else {
        // .json 文件：直接解析
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

  /// 清空已加载的日志
  void clear() {
    state = const FileLogState();
  }
}

final logOutputProvider =
    NotifierProvider<FileLogNotifier, FileLogState>(FileLogNotifier.new);
