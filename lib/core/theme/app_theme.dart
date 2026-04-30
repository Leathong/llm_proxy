import 'package:flutter/material.dart';

/// 应用主题配置
class AppTheme {
  AppTheme._();

  static ThemeData get light => ThemeData(
    primarySwatch: Colors.blue,
    useMaterial3: true,
  );
}
