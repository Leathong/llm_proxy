import 'package:llm_proxy/features/logs/domain/entities/log_output_entry.dart';

class LogStats {
  final int totalRequests;
  final int successCount;
  final int errorCount;
  final int totalInput;
  final int totalOutput;
  final int totalCacheCreation;
  final int totalCacheRead;
  final int entryWithUsage;
  final int totalDurationMs;
  final List<int> durations;
  final List<int> ttfbDurations;
  final List<double> outputSpeeds;
  final int totalOutputWithTime;
  final int totalGenerationMs;

  const LogStats({
    required this.totalRequests,
    required this.successCount,
    required this.errorCount,
    required this.totalInput,
    required this.totalOutput,
    required this.totalCacheCreation,
    required this.totalCacheRead,
    required this.entryWithUsage,
    required this.totalDurationMs,
    required this.durations,
    required this.ttfbDurations,
    required this.outputSpeeds,
    required this.totalOutputWithTime,
    required this.totalGenerationMs,
  });

  factory LogStats.compute(List<FileLogEntry> entries, {bool subtractFirstByte = false}) {
    int successCount = 0;
    int totalInput = 0, totalOutput = 0;
    int totalCacheCreation = 0, totalCacheRead = 0;
    int entryWithUsage = 0;
    int totalOutputWithTime = 0, totalGenerationMs = 0;
    int totalDurationMs = 0;
    final durations = <int>[];
    final ttfbDurations = <int>[];
    final outputSpeeds = <double>[];

    for (final entry in entries) {
      final statusCode = entry.statusCode;
      if (statusCode != null && statusCode >= 200 && statusCode < 300) successCount++;

      final duration = entry.durationMs;
      if (duration != null) {
        durations.add(duration);
        totalDurationMs += duration;
      }

      final ttfb = entry.firstByteMs;
      if (ttfb != null) ttfbDurations.add(ttfb);

      final usage = entry.response?.usage;
      if (usage != null) {
        totalInput += usage.totalInputTokens;
        totalOutput += usage.outputTokens ?? 0;
        totalCacheCreation += usage.cacheCreationInputTokens ?? 0;
        totalCacheRead += usage.cacheReadInputTokens ?? 0;
        entryWithUsage++;
      }

      final out = usage?.outputTokens;
      final dur = entry.durationMs;
      if (out != null && dur != null && dur > 0) {
        final baseMs = subtractFirstByte && entry.firstByteMs != null ? dur - entry.firstByteMs! : dur;
        if (baseMs > 0) {
          totalOutputWithTime += out;
          totalGenerationMs += baseMs;
        }
      }

      final speed = entry.outputTokensPerSecond(subtractFirstByte: subtractFirstByte);
      if (speed != null) outputSpeeds.add(speed);
    }

    final totalRequests = entries.length;
    final errorCount = totalRequests - successCount;
    durations.sort();
    ttfbDurations.sort();
    outputSpeeds.sort((a, b) => b.compareTo(a));

    return LogStats(
      totalRequests: totalRequests,
      successCount: successCount,
      errorCount: errorCount,
      totalInput: totalInput,
      totalOutput: totalOutput,
      totalCacheCreation: totalCacheCreation,
      totalCacheRead: totalCacheRead,
      entryWithUsage: entryWithUsage,
      totalDurationMs: totalDurationMs,
      durations: durations,
      ttfbDurations: ttfbDurations,
      outputSpeeds: outputSpeeds,
      totalOutputWithTime: totalOutputWithTime,
      totalGenerationMs: totalGenerationMs,
    );
  }

  num percentile(List<num> sorted, int p) {
    if (sorted.isEmpty) return 0;
    final idx = ((p / 100) * (sorted.length - 1)).round();
    return sorted[idx];
  }

  String formatDuration(int ms) {
    if (ms >= 60000) return '${(ms / 60000).toStringAsFixed(2)}min';
    if (ms >= 1000) return '${(ms / 1000).toStringAsFixed(2)}s';
    return '${ms}ms';
  }

  String formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  double? get avgSpeed {
    if (totalGenerationMs <= 0) return null;
    return totalOutputWithTime / (totalGenerationMs / 1000.0);
  }

  num get p90Duration => percentile(durations, 90);
  num get ttfbP90 => percentile(ttfbDurations, 90);
}
