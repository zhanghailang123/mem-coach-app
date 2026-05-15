import 'package:flutter/material.dart';

/// 斜杠命令类型
enum SlashCommandType {
  /// 上下文压缩
  compact,
  
  /// 思考强度
  effort,
  
  /// 帮助
  help,
  
  /// 清空对话
  clear,
  
  /// 导出对话
  export,
}

/// 斜杠命令数据
class SlashCommand {
  const SlashCommand({
    required this.type,
    required this.name,
    required this.description,
    required this.icon,
    this.aliases = const [],
  });

  final SlashCommandType type;
  final String name;
  final String description;
  final IconData icon;
  final List<String> aliases;

  /// 检查输入是否匹配此命令
  bool matches(String input) {
    final normalized = input.toLowerCase().trim();
    if (normalized == '/$name') return true;
    for (final alias in aliases) {
      if (normalized == '/$alias') return true;
    }
    return false;
  }
}

/// 预定义的斜杠命令
const List<SlashCommand> kSlashCommands = [
  SlashCommand(
    type: SlashCommandType.compact,
    name: 'compact',
    description: '压缩上下文，优化对话质量',
    icon: Icons.compress,
    aliases: ['压缩'],
  ),
  SlashCommand(
    type: SlashCommandType.effort,
    name: 'effort',
    description: '设置思考强度（低/中/高）',
    icon: Icons.speed,
    aliases: ['强度', '思考'],
  ),
  SlashCommand(
    type: SlashCommandType.help,
    name: 'help',
    description: '查看可用命令列表',
    icon: Icons.help_outline,
    aliases: ['帮助'],
  ),
  SlashCommand(
    type: SlashCommandType.clear,
    name: 'clear',
    description: '清空当前对话历史',
    icon: Icons.clear_all,
    aliases: ['清空'],
  ),
  SlashCommand(
    type: SlashCommandType.export,
    name: 'export',
    description: '导出对话记录',
    icon: Icons.download,
    aliases: ['导出'],
  ),
];

/// 斜杠命令面板组件
///
/// 当用户在输入框中输入 / 开头的文本时，显示命令列表。
/// 支持命令自动补全和执行。
class SlashCommandPanel extends StatefulWidget {
  const SlashCommandPanel({
    super.key,
    required this.inputText,
    required this.onCommandSelected,
    this.visible = false,
  });

  /// 当前输入文本
  final String inputText;

  /// 命令选择回调
  final ValueChanged<SlashCommand> onCommandSelected;

  /// 是否可见
  final bool visible;

  @override
  State<SlashCommandPanel> createState() => _SlashCommandPanelState();
}

class _SlashCommandPanelState extends State<SlashCommandPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _heightFactor;
  late Animation<double> _opacity;
  List<SlashCommand> _filteredCommands = [];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _heightFactor = _controller.drive(CurveTween(curve: Curves.easeOut));
    _opacity = _controller.drive(CurveTween(curve: Curves.easeOut));
    _updateFilteredCommands();
  }

  @override
  void didUpdateWidget(SlashCommandPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateFilteredCommands();
    
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  void _updateFilteredCommands() {
    final input = widget.inputText.trim();
    
    if (!input.startsWith('/')) {
      _filteredCommands = [];
      return;
    }

    final query = input.substring(1).toLowerCase();
    
    if (query.isEmpty) {
      _filteredCommands = List.from(kSlashCommands);
    } else {
      _filteredCommands = kSlashCommands.where((cmd) {
        return cmd.name.contains(query) ||
            cmd.description.contains(query) ||
            cmd.aliases.any((alias) => alias.contains(query));
      }).toList();
    }
    
    // 重置选中索引
    if (_selectedIndex >= _filteredCommands.length) {
      _selectedIndex = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_filteredCommands.isEmpty) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizeTransition(
          axisAlignment: 1.0,
          sizeFactor: _heightFactor,
          child: FadeTransition(
            opacity: _opacity,
            child: child,
          ),
        );
      },
      child: Container(
        constraints: const BoxConstraints(maxHeight: 250),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _filteredCommands.length,
            itemBuilder: (context, index) {
              final command = _filteredCommands[index];
              final isSelected = index == _selectedIndex;
              
              return _CommandItem(
                command: command,
                isSelected: isSelected,
                onTap: () {
                  widget.onCommandSelected(command);
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 命令列表项
class _CommandItem extends StatelessWidget {
  const _CommandItem({
    required this.command,
    required this.isSelected,
    required this.onTap,
  });

  final SlashCommand command;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: isSelected ? const Color(0xFFF5F5F5) : null,
        child: Row(
          children: [
            // 命令图标
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF2196F3).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                command.icon,
                size: 18,
                color: const Color(0xFF2196F3),
              ),
            ),
            const SizedBox(width: 12),
            // 命令信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '/${command.name}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF212121),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    command.description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF757575),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // 快捷键提示
            if (isSelected)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF2196F3).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Enter',
                  style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFF2196F3),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 斜杠命令解析结果
class SlashCommandResult {
  const SlashCommandResult({
    required this.type,
    this.value,
    this.isCommand = true,
  });

  final SlashCommandType type;
  final String? value;
  final bool isCommand;

  /// 不是命令（普通文本）
  factory SlashCommandResult.none() {
    return const SlashCommandResult(
      type: SlashCommandType.help,
      isCommand: false,
    );
  }
}

/// 解析斜杠命令
SlashCommandResult parseSlashCommand(String input) {
  final trimmed = input.trim();
  if (!trimmed.startsWith('/')) {
    return SlashCommandResult.none();
  }

  final normalized = trimmed.toLowerCase();
  
  // /compact - 上下文压缩
  if (normalized == '/compact' || normalized == '/压缩') {
    return const SlashCommandResult(type: SlashCommandType.compact);
  }
  
  // /effort [level] - 思考强度
  if (normalized.startsWith('/effort') || normalized.startsWith('/强度') || normalized.startsWith('/思考')) {
    final parts = trimmed.split(' ');
    String? level;
    if (parts.length > 1) {
      level = parts.sublist(1).join(' ');
    }
    return SlashCommandResult(
      type: SlashCommandType.effort,
      value: level,
    );
  }
  
  // /help - 帮助
  if (normalized == '/help' || normalized == '/帮助') {
    return const SlashCommandResult(type: SlashCommandType.help);
  }
  
  // /clear - 清空对话
  if (normalized == '/clear' || normalized == '/清空') {
    return const SlashCommandResult(type: SlashCommandType.clear);
  }
  
  // /export - 导出对话
  if (normalized == '/export' || normalized == '/导出') {
    return const SlashCommandResult(type: SlashCommandType.export);
  }
  
  return SlashCommandResult.none();
}