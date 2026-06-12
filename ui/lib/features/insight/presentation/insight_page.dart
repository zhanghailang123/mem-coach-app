import 'package:flutter/material.dart';
import '../../../core/native/mem_coach_native_bridge.dart';
import '../../../core/state/page_context_manager.dart';
import '../../coach/presentation/practice_page.dart';
import '../../knowledge/presentation/knowledge_page.dart';

List<Map<dynamic, dynamic>> _readMapList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<dynamic, dynamic>.from(item))
      .toList();
}

int _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _readDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}

double _clamp01(double value) => value.clamp(0.0, 1.0).toDouble();

String _subjectLabel(String? subject) {
  return switch (subject) {
    'math' => '数学',
    'logic' => '逻辑',
    'writing' => '写作',
    'english' => '英语',
    'management_comprehensive' => '管综',
    _ => '综合',
  };
}

String _modeLabel(String? mode) {
  return switch (mode) {
    'review' => '复习',
    'mock' => '模考',
    'memorize' => '背诵',
    _ => '练习',
  };
}

String _dateKey(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

String _weekdayLabel(DateTime date) {
  const labels = ['一', '二', '三', '四', '五', '六', '日'];
  return labels[date.weekday - 1];
}

Color _heatColor(BuildContext context, int count) {
  final colorScheme = Theme.of(context).colorScheme;
  if (count <= 0) {
    return colorScheme.onSurface.withValues(alpha: 0.12);
  }
  if (count < 3) return const Color(0xFF9AD9B5);
  if (count < 6) return const Color(0xFF33B276);
  return const Color(0xFF0B7A4A);
}

class InsightPage extends StatefulWidget {
  const InsightPage({super.key});

  @override
  State<InsightPage> createState() => _InsightPageState();
}

class _InsightPageState extends State<InsightPage> {
  late Future<Map<String, dynamic>> _insightFuture;
  int _lastRefreshRequestCount = 0;

  @override
  void initState() {
    super.initState();
    _insightFuture = MemCoachNativeBridge.getInsightSummary();
    _lastRefreshRequestCount = PageContextManager().refreshRequestCount;
    PageContextManager().addListener(_onContextManagerChanged);
  }

  void _refreshInsight() {
    setState(() {
      _insightFuture = MemCoachNativeBridge.getInsightSummary();
    });
  }

  void _onContextManagerChanged() {
    final currentCount = PageContextManager().refreshRequestCount;
    if (currentCount != _lastRefreshRequestCount) {
      _lastRefreshRequestCount = currentCount;
      _refreshInsight();
    }
  }

  @override
  void dispose() {
    PageContextManager().removeListener(_onContextManagerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的学情'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _refreshInsight,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _insightFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('加载失败: ${snapshot.error}'));
          }

          final data = snapshot.data ?? {};
          final totalStudyTimeSeconds =
              _readInt(data['total_study_time_seconds']);
          final totalQuestions = _readInt(data['total_questions']);
          final overallAccuracy =
              _clamp01(_readDouble(data['overall_accuracy']));
          final weakPoints = _readMapList(data['weak_points']);
          final dailyStats = _readMapList(data['daily_stats']);
          final subjectProgress = _readMapList(data['subject_progress']);
          final modeCounts = _readMapList(data['mode_counts']);

          return ListView(
            padding: const EdgeInsets.only(
                left: 20, right: 20, top: 20, bottom: 100),
            children: [
              _ScoreCard(
                totalQuestions: totalQuestions,
                overallAccuracy: overallAccuracy,
                totalStudyTimeSeconds: totalStudyTimeSeconds,
              ),
              const SizedBox(height: 16),
              _SubjectProgressCard(subjectProgress: subjectProgress),
              const SizedBox(height: 16),
              _WeakPointList(weakPoints: weakPoints),
              const SizedBox(height: 16),
              _ModeBreakdownCard(modeCounts: modeCounts),
              const SizedBox(height: 16),
              const _KnowledgeGraphCard(),
              const SizedBox(height: 16),
              _HeatmapCard(dailyStats: dailyStats),
            ],
          );
        },
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({
    required this.totalQuestions,
    required this.overallAccuracy,
    required this.totalStudyTimeSeconds,
  });

  final int totalQuestions;
  final double overallAccuracy;
  final int totalStudyTimeSeconds;

  @override
  Widget build(BuildContext context) {
    final accuracyPercent = (overallAccuracy * 100).toInt();
    final studyHours = (totalStudyTimeSeconds / 3600).toStringAsFixed(1);

    return _InsightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('学习概况',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$totalQuestions',
                  style: const TextStyle(
                      fontSize: 42, fontWeight: FontWeight.w900)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('题',
                    style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5))),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('正确率 $accuracyPercent%',
                      style: const TextStyle(
                          color: Color(0xFF20B486),
                          fontWeight: FontWeight.w900)),
                  Text(
                    '累计学习 $studyHours 小时',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child:
                LinearProgressIndicator(value: overallAccuracy, minHeight: 10),
          ),
        ],
      ),
    );
  }
}

class _SubjectProgressCard extends StatelessWidget {
  const _SubjectProgressCard({required this.subjectProgress});

  final List<Map<dynamic, dynamic>> subjectProgress;

  @override
  Widget build(BuildContext context) {
    final visibleItems = subjectProgress.where((item) {
      return _readInt(item['total']) > 0 || _readInt(item['learned']) > 0;
    }).toList();

    if (visibleItems.isEmpty) {
      return _InsightCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('科目掌握进度',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            Text(
              '暂无知识点掌握记录，完成练习后会自动更新。',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5)),
            ),
          ],
        ),
      );
    }

    return _InsightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('科目掌握进度',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          ...visibleItems.map((item) {
            final label = item['label']?.toString() ??
                _subjectLabel(item['subject']?.toString());
            final total = _readInt(item['total']);
            final learned = _readInt(item['learned']);
            final mastered = _readInt(item['mastered']);
            final progress = _clamp01(_readDouble(item['progress']));

            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        '$mastered/$total 已掌握',
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child:
                        LinearProgressIndicator(value: progress, minHeight: 8),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '已练过 $learned 个考点',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.45),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _WeakPointList extends StatelessWidget {
  const _WeakPointList({required this.weakPoints});

  final List<Map<dynamic, dynamic>> weakPoints;

  @override
  Widget build(BuildContext context) {
    if (weakPoints.isEmpty) {
      return _InsightCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('薄弱点 TOP 3',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            Text(
              '暂无薄弱点数据，去多做几道题吧！',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5)),
            ),
          ],
        ),
      );
    }

    return _InsightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('薄弱点 TOP 3',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          ...weakPoints.map((e) {
            final name = e['name']?.toString() ?? '未知考点';
            final subject = _subjectLabel(e['subject']?.toString());
            final reviewCount = _readInt(e['review_count']);
            final mastery = _clamp01(_readDouble(e['mastery']));
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          reviewCount > 0
                              ? '$subject · 已练 $reviewCount 次'
                              : subject,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.45),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                      width: 120,
                      child: LinearProgressIndicator(value: mastery)),
                  const SizedBox(width: 10),
                  SizedBox(
                      width: 40, child: Text('${(mastery * 100).toInt()}%')),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              // 获取最薄弱的知识点进行专项练习
              final weakest = weakPoints.isNotEmpty ? weakPoints[0] : null;
              final weakestTopic = weakest?['knowledge_id']?.toString() ??
                  weakest?['name']?.toString();
              final weakestSubject = weakest?['subject']?.toString();
              PracticePage.navigate(
                context,
                title: '薄弱点专项突破',
                subject: weakestSubject?.isNotEmpty == true
                    ? weakestSubject!
                    : 'logic',
                count: 5,
                topic: weakestTopic,
              );
            },
            child: const Text('让 AI 帮我逐个突破'),
          ),
        ],
      ),
    );
  }
}

class _ModeBreakdownCard extends StatelessWidget {
  const _ModeBreakdownCard({required this.modeCounts});

  final List<Map<dynamic, dynamic>> modeCounts;

  @override
  Widget build(BuildContext context) {
    final total =
        modeCounts.fold<int>(0, (sum, item) => sum + _readInt(item['count']));

    if (total == 0) {
      return _InsightCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('近 7 天练习类型',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            Text(
              '本周还没有练习记录。',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5)),
            ),
          ],
        ),
      );
    }

    return _InsightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('近 7 天练习类型',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          ...modeCounts.map((item) {
            final label = item['label']?.toString() ??
                _modeLabel(item['mode']?.toString());
            final count = _readInt(item['count']);
            final ratio = total > 0 ? count / total : 0.0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    child: Text(label,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child:
                          LinearProgressIndicator(value: ratio, minHeight: 8),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '$count 题',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _HeatmapCard extends StatelessWidget {
  const _HeatmapCard({required this.dailyStats});

  final List<Map<dynamic, dynamic>> dailyStats;

  @override
  Widget build(BuildContext context) {
    final statsByDate = {
      for (final item in dailyStats) item['date']?.toString(): item,
    }..remove(null);
    final days = List.generate(
        7, (index) => DateTime.now().subtract(Duration(days: 6 - index)));
    final weeklyTotal = days.fold<int>(0, (sum, day) {
      final item = statsByDate[_dateKey(day)];
      return sum + _readInt(item?['count']);
    });
    final weeklyCorrect = days.fold<int>(0, (sum, day) {
      final item = statsByDate[_dateKey(day)];
      return sum + _readInt(item?['correct']);
    });
    final weeklyAccuracy =
        weeklyTotal > 0 ? (weeklyCorrect / weeklyTotal * 100).toInt() : 0;

    return _InsightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('近 7 天练习热力图',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          Row(
            children: days.map((day) {
              final item = statsByDate[_dateKey(day)];
              final count = _readInt(item?['count']);
              final accuracy = _readDouble(item?['accuracy']);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Column(
                    children: [
                      Text(
                        _weekdayLabel(day),
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.45),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Tooltip(
                        message:
                            '${_dateKey(day)} · $count 题 · 正确率 ${(accuracy * 100).toInt()}%',
                        child: Container(
                          height: 34,
                          decoration: BoxDecoration(
                            color: _heatColor(context, count),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            count > 0 ? '$count' : '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Text(
            weeklyTotal > 0
                ? '本周 $weeklyTotal 题 · 正确率 $weeklyAccuracy%'
                : '本周还没有练习记录',
            style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1D1D26) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.04),
        ),
      ),
      child: child,
    );
  }
}

// 备考知识图谱入口卡片
class _KnowledgeGraphCard extends StatelessWidget {
  const _KnowledgeGraphCard();

  @override
  Widget build(BuildContext context) {
    return _InsightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('备考知识图谱',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(
            '精细化追踪数学、逻辑、写作与英语考点关联脉络。',
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const KnowledgePage()),
                );
              },
              icon: const Icon(Icons.hub_outlined, size: 18),
              label: const Text('查看考点知识网'),
            ),
          ),
        ],
      ),
    );
  }
}
