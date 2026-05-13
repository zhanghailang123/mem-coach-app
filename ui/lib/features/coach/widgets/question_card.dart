import 'package:flutter/material.dart';

import 'coach_shell_card.dart';

class QuestionCard extends StatefulWidget {
  const QuestionCard({super.key});

  @override
  State<QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<QuestionCard> {
  String? selected;

  @override
  Widget build(BuildContext context) {
    final options = {
      'A': '物价上涨',
      'B': '物价没有上涨',
      'C': '央行会加息',
      'D': '无法确定',
    };

    return CoachShellCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('第 1/5 题 · 逻辑 · ⭐⭐', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          const Text(
            '如果物价上涨，则央行会加息。央行没有加息。由此可以推出：',
            style: TextStyle(fontSize: 17, height: 1.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          ...options.entries.map((entry) {
            final active = selected == entry.key;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => setState(() => selected = entry.key),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: active ? Theme.of(context).colorScheme.primary.withOpacity(0.08) : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: active ? Theme.of(context).colorScheme.primary : Colors.transparent),
                  ),
                  child: Row(
                    children: [
                      Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(width: 12),
                      Expanded(child: Text(entry.value)),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: FilledButton(onPressed: selected == null ? null : () {}, child: const Text('提交'))),
              const SizedBox(width: 12),
              Expanded(child: OutlinedButton(onPressed: () {}, child: const Text('不确定'))),
            ],
          ),
        ],
      ),
    );
  }
}
