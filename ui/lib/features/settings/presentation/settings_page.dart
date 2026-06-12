import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/state/theme_provider.dart';
import '../../skill/presentation/skill_management_page.dart';
import 'mcp_management_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          const _SectionHeader(title: '外观'),
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: const Text('深色模式'),
            subtitle: Text(_themeLabel(themeMode)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showThemeSelector(context, ref, themeMode),
          ),
          const Divider(),
          const _SectionHeader(title: 'AI 能力'),
          ListTile(
            leading: const Icon(Icons.hub),
            title: const Text('MCP 服务管理'),
            subtitle: const Text('管理外部工具和模型上下文协议服务器'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const McpManagementPage(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.extension),
            title: const Text('学习策略管理'),
            subtitle: const Text('管理 AI 教练的解题和辅导策略'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SkillManagementPage(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.model_training),
            title: const Text('模型配置'),
            subtitle: const Text('配置底层大模型参数'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('模型配置功能即将推出')),
              );
            },
          ),
          const Divider(),
          const _SectionHeader(title: '个人设置'),
          ListTile(
            leading: const Icon(Icons.account_circle),
            title: const Text('账号与同步'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('账号功能即将推出')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('学习偏好'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('学习偏好设置即将推出')),
              );
            },
          ),
          const Divider(),
          const _SectionHeader(title: '关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于 MEM Coach'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('关于 MEM Coach'),
                  content: const Text('MEM Coach v0.1.0\n\n你的专属 AI 考研教练。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('确定'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

String _themeLabel(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return '浅色';
    case ThemeMode.dark:
      return '深色';
    case ThemeMode.system:
      return '跟随系统';
  }
}

void _showThemeSelector(BuildContext context, WidgetRef ref, ThemeMode current) {
  showModalBottomSheet(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.brightness_auto),
            title: Text('跟随系统'),
            trailing: current == ThemeMode.system ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
            onTap: () {
              ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.system);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.light_mode),
            title: Text('浅色模式'),
            trailing: current == ThemeMode.light ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
            onTap: () {
              ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.light);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.dark_mode),
            title: Text('深色模式'),
            trailing: current == ThemeMode.dark ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
            onTap: () {
              ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    ),
  );
}
