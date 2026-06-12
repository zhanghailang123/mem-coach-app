import 'dart:convert';

import 'package:flutter/material.dart';

/// 工具调用胶囊组件（仿 Minis 风格）
class ToolCallChip extends StatelessWidget {
  const ToolCallChip({
    super.key,
    required this.toolName,
    this.arguments,
    this.result,
    this.error,
    this.duration,
    this.isRunning = false,
  });

  final String toolName;
  final String? arguments;
  final String? result;
  final String? error;
  final Duration? duration;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    final hasError = error != null && error!.trim().isNotEmpty;
    final isSkill = toolName.startsWith('skill:');
    final accentColor = hasError
        ? const Color(0xFFFF453A)
        : isSkill
            ? const Color(0xFF7C5CFF)
            : isRunning
                ? const Color(0xFF0A84FF)
                : const Color(0xFF34C759);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _showToolDetails(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF3A3A3C),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    hasError
                        ? Icons.error_outline_rounded
                        : isSkill
                            ? Icons.psychology_alt_rounded
                            : Icons.description_outlined,
                    size: 16,
                    color: accentColor,
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
                      isRunning ? '...' : _formatDuration(duration!),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showToolDetails(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final formattedArguments = _formatPayload(arguments);
    final formattedResult = _formatPayload(error ?? result);
    final hasError = error != null && error!.trim().isNotEmpty;
    final isSkill = toolName.startsWith('skill:');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.82,
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1D1D26) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      hasError
                          ? Icons.error_outline_rounded
                          : isSkill
                              ? Icons.psychology_alt_rounded
                              : Icons.description_outlined,
                      color: hasError
                          ? const Color(0xFFFF453A)
                          : isSkill
                              ? const Color(0xFF7C5CFF)
                              : const Color(0xFF34C759),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _formatToolName(toolName),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildMetaLine(context, hasError),
                if (formattedArguments != null) ...[
                  const SizedBox(height: 16),
                  _buildPayloadSection(context, '输入参数', formattedArguments),
                ],
                if (formattedResult != null) ...[
                  const SizedBox(height: 16),
                  _buildPayloadSection(
                      context, hasError ? '错误信息' : '输出结果', formattedResult),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetaLine(BuildContext context, bool hasError) {
    final color = hasError
        ? const Color(0xFFFF453A)
        : toolName.startsWith('skill:')
            ? const Color(0xFF7C5CFF)
            : isRunning
                ? const Color(0xFF0A84FF)
                : const Color(0xFF34C759);
    final status = hasError
        ? '失败'
        : toolName.startsWith('skill:')
            ? '已激活'
            : isRunning
                ? '执行中'
                : '已完成';
    final durationText = duration == null ? null : _formatDuration(duration!);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildMetaChip(context, status, color),
        if (durationText != null)
          _buildMetaChip(context, '耗时 $durationText',
              Theme.of(context).colorScheme.primary),
      ],
    );
  }

  Widget _buildMetaChip(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildPayloadSection(
      BuildContext context, String title, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72),
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF252530) : const Color(0xFFF5F7FB),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  Theme.of(context).colorScheme.outline.withValues(alpha: 0.12),
            ),
          ),
          child: SelectableText(
            value,
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.86),
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    return '${(duration.inMilliseconds / 1000).toStringAsFixed(1)}s';
  }

  String? _formatPayload(String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty || text == 'null') return null;
    try {
      final decoded = jsonDecode(text);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return text;
    }
  }

  String _formatToolName(String name) {
    if (name.startsWith('skill:')) {
      final skillName = name.substring('skill:'.length).trim();
      return skillName.isEmpty ? '学习策略' : '学习策略 · $skillName';
    }

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
