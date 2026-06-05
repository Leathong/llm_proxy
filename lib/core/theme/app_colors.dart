import 'package:flutter/material.dart';

/// macOS 风格配色常量
///
/// 参考 macOS Human Interface Guidelines 中的系统颜色，
/// 提供统一、一致的视觉体验。
class AppColors {
  AppColors._();

  // ── 主色调 ──
  /// macOS 系统蓝
  static const Color primary = Color(0xFF007AFF);

  /// 主色调浅色变体（用于浅色背景上的文字/图标）
  static const Color primaryLight = Color(0xFF409CFF);

  // ── 语义色 ──
  /// 成功 / 运行中 - macOS 系统绿
  static const Color success = Color(0xFF34C759);

  /// 警告 / 进行中 - macOS 系统橙
  static const Color warning = Color(0xFFFF9500);

  /// 错误 / 停止 / 删除 - macOS 系统红
  static const Color error = Color(0xFFFF3B30);

  /// 信息 / 链接 - 与 primary 一致
  static const Color info = primary;

  // ── 辅助色 ──
  /// macOS 系统紫（用于 system prompt 等）
  static const Color purple = Color(0xFFAF52DE);

  /// macOS 系统青（用于缓存读取、速度等）
  static const Color cyan = Color(0xFF5AC8FA);

  /// macOS 系统靛蓝（用于总耗时等）
  static const Color indigo = Color(0xFF5856D6);

  /// macOS 系统粉（备用）
  static const Color pink = Color(0xFFFF2D55);

  // ── 中性色 ──
  /// 系统灰（次要文字、图标）
  static const Color grey = Color(0xFF8E8E93);

  /// 浅灰（分隔线、禁用态）
  static const Color greyLight = Color(0xFFC7C7CC);

  /// 极浅灰（背景色）
  static const Color greyUltraLight = Color(0xFFF2F2F7);

  /// 深灰（主要文字）
  static const Color greyDark = Color(0xFF3A3A3C);

  /// 蓝灰（统计标签等）
  static const Color blueGrey = Color(0xFF6E7A8A);

  /// 柔和白（用于深色背景上的前景文字/图标，比纯白更柔和）
  static const Color whiteSoft = Color(0xFFF0F0F0);

  // ── 背景色 ──
  /// 页面背景色（macOS 窗口背景）
  static const Color background = Color(0xFFF2F2F7);

  /// 卡片 / 容器背景色
  static const Color surface = Color(0xFFFFFFFF);

  /// 侧边栏背景色（macOS 侧边栏风格）
  static const Color sidebarBackground = Color(0xFFF2F2F7);

  // ── 角色色（对话消息） ──
  /// User 角色色
  static const Color roleUser = primary;

  /// Assistant 角色色
  static const Color roleAssistant = success;

  /// System 角色色
  static const Color roleSystem = purple;

  /// 默认角色色
  static const Color roleDefault = grey;

  // ── Token 用量色 ──
  /// 输入 token
  static const Color tokenInput = primary;

  /// 输出 token
  static const Color tokenOutput = warning;

  /// 缓存创建
  static const Color tokenCacheCreation = Color(0xFF5AC8FA);

  /// 缓存读取
  static const Color tokenCacheRead = cyan;

  // ── 工具调用色 ──
  /// 工具调用 / 工具定义
  static const Color toolCall = warning;

  /// 工具结果
  static const Color toolResult = Color(0xFF30B0C7);

  // ── 思考色 ──
  /// 思考/推理内容
  static const Color thinking = purple;

  // ── 统计指标色 ──
  /// 范围
  static const Color statRange = blueGrey;

  /// 总计
  static const Color statTotal = grey;

  /// 请求数
  static const Color statRequests = primary;

  /// 成功数
  static const Color statSuccess = success;

  /// 失败数
  static const Color statError = error;

  /// P90 耗时
  static const Color statP90 = warning;

  /// 总耗时
  static const Color statTotalDuration = indigo;

  /// TTFB
  static const Color statTTFB = Color(0xFF30B0C7);

  /// 速度
  static const Color statSpeed = Color.fromARGB(255, 34, 185, 255);

  /// Token 统计
  static const Color statTokens = purple;

  // ── Provider 格式色 ──
  /// OpenAI 格式
  static const Color formatOpenAI = success;

  /// Anthropic 格式
  static const Color formatAnthropic = warning;
}
