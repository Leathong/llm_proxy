class LogStorageStats {
  final int totalCount;
  final DateTime? minTime;
  final DateTime? maxTime;
  final int logTableBytes;
  final int databaseFileBytes;
  final int? walFileBytes;

  const LogStorageStats({
    required this.totalCount,
    this.minTime,
    this.maxTime,
    required this.logTableBytes,
    required this.databaseFileBytes,
    this.walFileBytes,
  });

  String get timeSpanText {
    if (minTime == null || maxTime == null) return '无数据';
    return '${_formatDateTime(minTime!)} ~ ${_formatDateTime(maxTime!)}';
  }

  static String _formatDateTime(DateTime dt) {
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
        '${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
