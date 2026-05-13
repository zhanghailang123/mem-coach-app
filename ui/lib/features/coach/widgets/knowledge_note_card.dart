import 'package:flutter/material.dart';

import 'coach_shell_card.dart';

class KnowledgeNoteCard extends StatelessWidget {
  const KnowledgeNoteCard({super.key});

  @override
  Widget build(BuildContext context) {
    return CoachShellCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('否定后件式 · 知识笔记', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          _Section(title: '定义', content: 'A → B，¬B，因此 ¬A。'),
          const SizedBox(height: 12),
          _Section(title: '你的易错点', content: '容易把「否定后件」和「否定前件」混淆。否定前件不能推出确定结论。'),
          const SizedBox(height: 12),
          _Section(title: '相关真题', content: '2023 年第 12 题 · 2021 年第 8 题（你做错过）'),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: FilledButton(onPressed: () {}, child: const Text('保存'))),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton(onPressed: () {}, child: const Text('导出MD'))),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton(onPressed: () {}, child: const Text('变式'))),
            ],
          ),
        ],
      ),
    );
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
