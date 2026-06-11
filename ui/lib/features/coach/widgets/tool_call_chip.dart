import 'package:flutter/material.dart';

/// 工具调用胶囊组件（仿 Minis 风格）
class ToolCallChip extends StatelessWidget {
  const ToolCallChip({
    super.key,
    required this.toolName,
    this.duration,
    this.isRunning = false,
  });

  final String toolName;
  final Duration? duration;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF3A3A3C),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 16,
                  color: const Color(0xFF34C759),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatToolName(toolName),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                ),
                if (duration != null || isRunning) ...[
                  const SizedBox(width: 8),
                  Text(
                    isRunning ? '...' : '${(duration!.inMilliseconds / 1000).toStringAsFixed(1)}s',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatToolName(String name) {
    // 简化工具名显示
    final Map<String, String> nameMap = {
      'exam_question_search': '查看考题搜索',
      'exam_question_explain': '查看消息气泡解析',
      'exam_similar_find': '查看消息气泡相似题',
      'knowledge_search': '查看知识点',
      'pdf_query': '查看PDF',
    };
    return nameMap[name] ?? name.replaceAll('_', ' ');
  }
}
