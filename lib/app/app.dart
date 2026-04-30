import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llm_proxy/app/router.dart';
import 'package:llm_proxy/core/theme/app_theme.dart';

class LLMProxyApp extends ConsumerWidget {
  const LLMProxyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'LLM Proxy',
      theme: AppTheme.light,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
