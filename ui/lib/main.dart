import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/widgets/global_agent_button.dart';
import 'features/app_shell/presentation/app_shell_page.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: MemCoachApp()));
}

class MemCoachApp extends StatelessWidget {
  const MemCoachApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MEM Coach',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const AppShellPage(),
      // 全局注入 AI Agent 悬浮按钮，覆盖所有路由
      builder: (context, child) {
        return GlobalAgentButton(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
