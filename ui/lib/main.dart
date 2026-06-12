import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/widgets/global_agent_button.dart';
import 'core/state/theme_provider.dart';
import 'features/app_shell/presentation/app_shell_page.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: MemCoachApp()));
}

class MemCoachApp extends ConsumerWidget {
  const MemCoachApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    
    return MaterialApp(
      title: 'MEM 搭子',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: const AppShellPage(),
      // 全局注入 AI Agent 悬浮按钮，覆盖所有路由
      builder: (context, child) {
        return GlobalAgentButton(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
