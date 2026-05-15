import 'package:flutter/material.dart';

import '../../../core/native/mem_coach_native_bridge.dart';
import '../presentation/practice_page.dart';
import 'coach_shell_card.dart';

/// 学习任务数据
class StudyMissionData {
  const StudyMissionData({
    required this.title,
    required this.subtitle,
    required this.estimatedMinutes,
    required this.questionCount,
    this.progress = 0.0,
    this.subject = 'logic',
    this.topic,
  });

  final String title;
  final String subtitle;
  final int estimatedMinutes;
  final int questionCount;
  final double progress;
  final String subject;
  final String? topic;
}

class StudyMissionCard extends StatefulWidget {
  const StudyMissionCard({
    super.key,
    this.mission,
  });

  final StudyMissionData? mission;

  @override
  State<StudyMissionCard> createState() => _StudyMissionCardState();
}

class _StudyMissionCardState extends State<StudyMissionCard> {
  bool _loadingQuick = false;

  StudyMissionData get _mission => widget.mission ?? const StudyMissionData(
    title: '否定后件式 · 真题专项突破',
    subtitle: '来源：2020-2024 管综逻辑真题 · 5 道题',
    estimatedMinutes: 18,
    questionCount: 5,
  );

  void _startPractice() {
    PracticePage.navigate(
      context,
      title: _mission.title,
      subject: _mission.subject,
      count: _mission.questionCount,
      topic: _mission.topic,
    );
  }

  Future<void> _quickPractice() async {
    if (_loadingQuick) return;

    setState(() => _loadingQuick = true);
    try {
      PracticePage.navigate(
        context,
        title: '极速 3 题',
        subject: _mission.subject,
        count: 3,
      );
    } finally {
      if (mounted) {
        setState(() => _loadingQuick = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final m = _mission;

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
              Text('预计 ${m.estimatedMinutes} 分钟', style: const TextStyle(color: Colors.black54)),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            m.title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            m.subtitle,
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 9,
              value: m.progress,
              backgroundColor: Colors.grey.shade200,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _startPractice,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('开始练习'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loadingQuick ? null : _quickPractice,
                  icon: _loadingQuick
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.flash_on_rounded),
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
