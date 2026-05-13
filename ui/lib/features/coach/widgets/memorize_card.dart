import 'package:flutter/material.dart';

import 'coach_shell_card.dart';

class MemorizeCard extends StatelessWidget {
  const MemorizeCard({super.key});

  @override
  Widget build(BuildContext context) {
    return CoachShellCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('逻辑公式 · 填空回忆', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FC),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '假言命题 A → B 的逆否命题是\n\n_____ → _____',
              style: TextStyle(fontSize: 18, height: 1.6, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: FilledButton(onPressed: () {}, child: const Text('检查答案'))),
              const SizedBox(width: 12),
              Expanded(child: OutlinedButton(onPressed: () {}, child: const Text('看提示'))),
            ],
          ),
        ],
      ),
    );
  }
}
