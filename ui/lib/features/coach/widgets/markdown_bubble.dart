import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

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
                    ? Theme.of(context).colorScheme.primary
                    : const Color(0xFFF4F6FA),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
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
      child: MarkdownBody(
        data: content,
        selectable: true,
        extensionSet: md.ExtensionSet.gitHubFlavored,
        builders: {
          'math': _MathBuilder(),
        },
        styleSheet: MarkdownStyleSheet(
          // 段落
          p: const TextStyle(
            color: Colors.black87,
            fontSize: 15,
            height: 1.55,
          ),
          // 标题
          h1: const TextStyle(
            color: Colors.black87,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.4,
          ),
          h2: const TextStyle(
            color: Colors.black87,
            fontSize: 19,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
          h3: const TextStyle(
            color: Colors.black87,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
          // 代码块
          code: TextStyle(
            color: Colors.red.shade700,
            fontSize: 13.5,
            fontFamily: 'monospace',
            backgroundColor: Colors.grey.withOpacity(0.1),
          ),
          codeblockDecoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
          ),
          codeblockPadding: const EdgeInsets.all(14),
          // 列表
          listBullet: const TextStyle(
            color: Colors.black87,
            fontSize: 15,
          ),
          // 引用块
          blockquote: const TextStyle(
            color: Colors.black54,
            fontSize: 15,
            fontStyle: FontStyle.italic,
          ),
          blockquoteDecoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: Colors.grey.withOpacity(0.4),
                width: 3,
              ),
            ),
          ),
          blockquotePadding: const EdgeInsets.only(left: 14, top: 8, bottom: 8),
          // 链接
          a: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
          // 水平线
          horizontalRuleDecoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Colors.grey.withOpacity(0.2),
                width: 1,
              ),
            ),
          ),
        ),
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
    final messageDate = DateTime(timestamp.year, timestamp.month, timestamp.day);
    
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

/// LaTeX 数学公式构建器
///
/// 支持行内公式 ($...$) 和块级公式 ($$...$$)
class _MathBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final String? formula = element.textContent;
    if (formula == null || formula.isEmpty) {
      return null;
    }

    // 检查是否是块级公式（以 $$ 开头和结尾）
    final isBlock = formula.startsWith('\$\$') && formula.endsWith('\$\$');
    final cleanFormula = isBlock
        ? formula.substring(2, formula.length - 2).trim()
        : formula.trim();

    if (cleanFormula.isEmpty) {
      return null;
    }

    try {
      return Math.tex(
        cleanFormula,
        textStyle: preferredStyle?.copyWith(
          color: Colors.black87,
          fontSize: isBlock ? 16 : 14,
        ),
        mathStyle: isBlock ? MathStyle.display : MathStyle.text,
        onErrorFallback: (error) {
          return Text(
            formula,
            style: preferredStyle?.copyWith(
              color: Colors.red.shade700,
              fontStyle: FontStyle.italic,
            ),
          );
        },
      );
    } catch (e) {
      // 如果公式解析失败，返回原始文本
      return Text(
        formula,
        style: preferredStyle?.copyWith(
          color: Colors.red.shade700,
          fontStyle: FontStyle.italic,
        ),
      );
    }
  }
}
