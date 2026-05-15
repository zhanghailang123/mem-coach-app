import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'coach_shell_card.dart';

/// 知识笔记数据
class KnowledgeNoteData {
  const KnowledgeNoteData({
    required this.id,
    required this.title,
    required this.definition,
    required this.errorPoints,
    this.relatedQuestions,
    this.topic,
  });

  final String id;
  final String title;
  final String definition;
  final String errorPoints;
  final String? relatedQuestions;
  final String? topic;

  factory KnowledgeNoteData.fromMap(Map<String, dynamic> map) {
    return KnowledgeNoteData(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      definition: map['definition']?.toString() ?? '',
      errorPoints: map['error_points']?.toString() ?? '',
      relatedQuestions: map['related_questions']?.toString(),
      topic: map['topic']?.toString(),
    );
  }
}

/// 回调：保存笔记
typedef OnSaveNote = void Function(KnowledgeNoteData data);
/// 回调：查看变式
typedef OnViewVariations = void Function(String noteId);

class KnowledgeNoteCard extends StatelessWidget {
  const KnowledgeNoteCard({
    super.key,
    this.data,
    this.onSave,
    this.onViewVariations,
  });

  final KnowledgeNoteData? data;
  final OnSaveNote? onSave;
  final OnViewVariations? onViewVariations;

  @override
  Widget build(BuildContext context) {
    final d = data ?? const KnowledgeNoteData(
      id: 'demo',
      title: '否定后件式 · 知识笔记',
      definition: 'A → B，¬B，因此 ¬A。',
      errorPoints: '容易把「否定后件」和「否定前件」混淆。否定前件不能推出确定结论。',
      relatedQuestions: '2023 年第 12 题 · 2021 年第 8 题（你做错过）',
    );

    return CoachShellCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(d.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          if (d.topic != null && d.topic!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(d.topic!, style: const TextStyle(color: Colors.black54, fontSize: 13)),
          ],
          const SizedBox(height: 14),
          _Section(title: '定义', content: d.definition),
          const SizedBox(height: 12),
          _Section(title: '你的易错点', content: d.errorPoints),
          if (d.relatedQuestions != null && d.relatedQuestions!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Section(title: '相关真题', content: d.relatedQuestions!),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    onSave?.call(d);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('笔记已保存'),
                        backgroundColor: Color(0xFF20B486),
                      ),
                    );
                  },
                  child: const Text('保存'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    // 导出为 Markdown 格式并复制到剪贴板
                    final markdown = _toMarkdown(d);
                    Clipboard.setData(ClipboardData(text: markdown));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已复制到剪贴板'),
                        backgroundColor: Color(0xFF5B5FEF),
                      ),
                    );
                  },
                  child: const Text('导出MD'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    onViewVariations?.call(d.id);
                  },
                  child: const Text('变式'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _toMarkdown(KnowledgeNoteData d) {
    final buffer = StringBuffer();
    buffer.writeln('# ${d.title}');
    buffer.writeln();
    buffer.writeln('## 定义');
    buffer.writeln(d.definition);
    buffer.writeln();
    buffer.writeln('## 易错点');
    buffer.writeln(d.errorPoints);
    if (d.relatedQuestions != null && d.relatedQuestions!.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('## 相关真题');
      buffer.writeln(d.relatedQuestions!);
    }
    return buffer.toString();
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(content, style: const TextStyle(height: 1.45, color: Colors.black87)),
        ],
      ),
    );
  }
}
