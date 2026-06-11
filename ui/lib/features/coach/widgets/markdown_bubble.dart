import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/markdown_math.dart';

/// Markdown 渲染气泡组件
/// 支持富文本、代码块、列表等 Markdown 语法
class MarkdownBubble extends StatelessWidget {
  const MarkdownBubble({super.key, required this.message});

  final dynamic message; // _ChatMessage from chat_sheet.dart

  @override
  Widget build(BuildContext context) {
    final isUser = message.role.toString().contains('user');
    final isSystem = message.role.toString().contains('system');
    final content = message.content as String;

    // 系统消息使用不同的样式
    if (isSystem) {
      return _buildSystemMessage(content, context);
    }

    return GestureDetector(
      onLongPress: () => _showMessageMenu(context, isUser),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 4),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.82,
              ),
              decoration: BoxDecoration(
                color: isUser
                    ? const Color(0xFF5B5FEF)
                    : const Color(0xFFF0F2F5),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 6),
                  bottomRight: Radius.circular(isUser ? 6 : 20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: isUser
                  ? _buildUserBubble(content, context)
                  : _buildAssistantBubble(content, context),
            ),
          ),
          // 时间戳显示
          if (message.timestamp != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
              child: Text(
                _formatTimestamp(message.timestamp!),
                style: TextStyle(
                  color: Colors.black38,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 用户消息：纯文本
  Widget _buildUserBubble(String content, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Text(
        content.isEmpty ? '...' : content,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          height: 1.45,
        ),
      ),
    );
  }

  /// 系统消息：居中显示，使用特殊样式
  Widget _buildSystemMessage(String content, BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFE3F2FD),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFBBDEFB),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.info_outline,
              size: 16,
              color: const Color(0xFF1976D2),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                content,
                style: const TextStyle(
                  color: Color(0xFF1976D2),
                  fontSize: 13,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Agent 消息：Markdown 渲染
  Widget _buildAssistantBubble(String content, BuildContext context) {
    if (content.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '思考中...',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: MarkdownMathView(
        data: content,
        baseFontSize: 15,
        mathColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  /// 显示消息操作菜单（长按触发）
  void _showMessageMenu(BuildContext context, bool isUser) {
    final content = message.content as String;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 复制选项
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: content));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已复制到剪贴板'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
            // 重新生成选项（仅对 AI 消息显示）
            if (!isUser)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('重新生成'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: 触发重新生成回调（需要与 chat_sheet.dart 交互）
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('重新生成功能开发中...'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  /// 格式化时间戳为可读字符串
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate =
        DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (messageDate == today) {
      // 今天：显示 HH:mm
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      // 昨天：显示 昨天 HH:mm
      return '昨天 ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else {
      // 更早：显示 MM-dd HH:mm
      return '${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }
}
