import 'package:flutter/material.dart';

import 'coach_shell_card.dart';

class ReasoningChainCard extends StatelessWidget {
  const ReasoningChainCard({super.key});

  @override
  Widget build(BuildContext context) {
    final steps = [
      '物价上涨 → 央行加息（题干）',
      '央行没有加息（已知）',
      '否定后件：¬B ∴ ¬A',
      '所以：物价没有上涨',
    ];

    return CoachShellCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('推理链', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          ...List.generate(steps.length, (index) {
            final isLast = index == steps.length - 1;
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
                    child: Text(steps[index], style: TextStyle(fontWeight: isLast ? FontWeight.w900 : FontWeight.w600)),
                  ),
                ),
              ],
            );
          }),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: FilledButton(onPressed: () {}, child: const Text('下一题'))),
              const SizedBox(width: 12),
              Expanded(child: OutlinedButton(onPressed: () {}, child: const Text('看变式'))),
            ],
          ),
        ],
      ),
    );
  }
}
