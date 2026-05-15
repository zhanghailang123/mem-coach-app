import 'package:flutter/material.dart';

import '../../../core/native/mem_coach_native_bridge.dart';
import 'coach_shell_card.dart';

/// 推理链数据
class ReasoningChainData {
  const ReasoningChainData({
    required this.questionId,
    required this.title,
    required this.steps,
    this.topic,
  });

  final String questionId;
  final String title;
  final List<String> steps;
  final String? topic;

  factory ReasoningChainData.fromMap(Map<String, dynamic> map) {
    return ReasoningChainData(
      questionId: map['question_id']?.toString() ?? '',
      title: map['title']?.toString() ?? '推理链',
      steps: (map['steps'] as List?)?.map((e) => e.toString()).toList() ?? [],
      topic: map['topic']?.toString(),
    );
  }
}

/// 回调：下一题
typedef OnNextQuestion = void Function();
/// 回调：查看变式
typedef OnViewVariations = void Function(String questionId);

class ReasoningChainCard extends StatelessWidget {
  const ReasoningChainCard({
    super.key,
    this.data,
    this.onNextQuestion,
    this.onViewVariations,
  });

  final ReasoningChainData? data;
  final OnNextQuestion? onNextQuestion;
  final OnViewVariations? onViewVariations;

  @override
  Widget build(BuildContext context) {
    final d = data ?? const ReasoningChainData(
      questionId: 'demo',
      title: '推理链',
      steps: [
        '物价上涨 → 央行加息（题干）',
        '央行没有加息（已知）',
        '否定后件：¬B ∴ ¬A',
        '所以：物价没有上涨',
      ],
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
          ...List.generate(d.steps.length, (index) {
            final isLast = index == d.steps.length - 1;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: isLast ? const Color(0xFF20B486) : Theme.of(context).colorScheme.primary,
                      child: Text('${index + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                    if (!isLast) Container(width: 2, height: 26, color: Colors.grey.shade300),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(d.steps[index], style: TextStyle(fontWeight: isLast ? FontWeight.w900 : FontWeight.w600)),
                  ),
                ),
              ],
            );
          }),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    onNextQuestion?.call();
                  },
                  child: const Text('下一题'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    onViewVariations?.call(d.questionId);
                  },
                  child: const Text('看变式'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
