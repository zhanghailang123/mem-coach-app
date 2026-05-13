import 'package:flutter/material.dart';

import 'coach_shell_card.dart';

class StudyMissionCard extends StatelessWidget {
  const StudyMissionCard({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;

    return CoachShellCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '今日主线任务',
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
              ),
              const Spacer(),
              const Text('预计 18 分钟', style: TextStyle(color: Colors.black54)),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            '否定后件式 · 真题专项突破',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            '来源：2020-2024 管综逻辑真题 · 5 道题',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 9,
              value: 0.0,
              backgroundColor: Colors.grey.shade200,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('开始练习'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.flash_on_rounded),
                  label: const Text('极速 3 题'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
