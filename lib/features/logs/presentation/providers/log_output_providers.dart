import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';

/// 日志输出文件的加载状态
class LogOutputState {
  final List<LogOutputEntry> entries;
  final String? filePath;
  final String? error;
  final bool isLoading;

  const LogOutputState({
    this.entries = const [],
    this.filePath,
    this.error,
    this.isLoading = false,
  });

  LogOutputState copyWith({
    List<LogOutputEntry>? entries,
    String? filePath,
    String? error,
    bool? isLoading,
  }) {
    return LogOutputState(
      entries: entries ?? this.entries,
      filePath: filePath ?? this.filePath,
      error: error,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// 管理日志输出文件的加载、解析
class LogOutputNotifier extends Notifier<LogOutputState> {
  @override
  LogOutputState build() => const LogOutputState();

  /// 从指定路径加载 JSON 日志文件
  Future<void> loadFile(String path) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final file = File(path);
      if (!await file.exists()) {
        state = state.copyWith(isLoading: false, error: '文件不存在: $path');
        return;
      }

      final content = await file.readAsString();
      final list = jsonDecode(content) as List<dynamic>;
      final entries = <LogOutputEntry>[];
      for (var i = 0; i < list.length; i++) {
        entries.add(
          LogOutputEntry.fromJson(list[i] as Map<String, dynamic>, i),
        );
      }

      state = LogOutputState(
        entries: entries,
        filePath: path,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '解析失败: $e');
    }
  }

  /// 清空已加载的日志
  void clear() {
    state = const LogOutputState();
  }
}

final logOutputProvider =
    NotifierProvider<LogOutputNotifier, LogOutputState>(LogOutputNotifier.new);
