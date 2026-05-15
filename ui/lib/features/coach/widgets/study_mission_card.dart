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
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '今日主线任务',
                  style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
              const Spacer(),
              Text('预计 ${m.estimatedMinutes} 分钟', style: const TextStyle(color: Colors.black54, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            m.title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5),
          ),
          const SizedBox(height: 10),
          Text(
            m.subtitle,
            style: const TextStyle(color: Colors.black54, fontSize: 14),
          ),
          const SizedBox(height: 22),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: m.progress,
              backgroundColor: Colors.black.withOpacity(0.05),
              color: color,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _startPractice,
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('开始练习'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loadingQuick ? null : _quickPractice,
                  icon: _loadingQuick
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.flash_on_rounded, size: 18),
                  label: const Text('极速 3 题'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: color.withOpacity(0.2)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
