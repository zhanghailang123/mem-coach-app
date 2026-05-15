import 'package:flutter/material.dart';
import '../../../core/native/mem_coach_native_bridge.dart';
import '../../coach/presentation/practice_page.dart';

class InsightPage extends StatefulWidget {
  const InsightPage({super.key});

  @override
  State<InsightPage> createState() => _InsightPageState();
}

class _InsightPageState extends State<InsightPage> {
  late Future<Map<String, dynamic>> _insightFuture;

  @override
  void initState() {
    super.initState();
    _insightFuture = MemCoachNativeBridge.getInsightSummary();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的学情')),
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
          final totalStudyTimeSeconds = data['total_study_time_seconds'] as int? ?? 0;
          final totalQuestions = data['total_questions'] as int? ?? 0;
          final overallAccuracy = data['overall_accuracy'] as double? ?? 0.0;
          final weakPoints = (data['weak_points'] as List?)?.cast<Map<dynamic, dynamic>>() ?? [];
          final dailyStats = (data['daily_stats'] as List?)?.cast<Map<dynamic, dynamic>>() ?? [];

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _ScoreCard(
                totalQuestions: totalQuestions,
                overallAccuracy: overallAccuracy,
                totalStudyTimeSeconds: totalStudyTimeSeconds,
              ),
              const SizedBox(height: 16),
              const _SubjectRadarMock(),
              const SizedBox(height: 16),
              _WeakPointList(weakPoints: weakPoints),
              const SizedBox(height: 16),
              _HeatmapCard(
                dailyStats: dailyStats,
                totalStudyTimeSeconds: totalStudyTimeSeconds,
              ),
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
          const Text('学习概况', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$totalQuestions', style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900)),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('题', style: TextStyle(color: Colors.black54)),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('正确率 $accuracyPercent%', style: const TextStyle(color: Color(0xFF20B486), fontWeight: FontWeight.w900)),
                  Text('累计学习 $studyHours 小时', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(value: overallAccuracy, minHeight: 10),
          ),
        ],
      ),
    );
  }
}

class _SubjectRadarMock extends StatelessWidget {
  const _SubjectRadarMock();

  @override
  Widget build(BuildContext context) {
    return _InsightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('科目能力雷达', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: Center(
              child: CustomPaint(
                size: const Size(180, 160),
                painter: _RadarPainter(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = Colors.grey.shade300;
    for (final r in [40.0, 65.0, 85.0]) {
      canvas.drawCircle(center, r, paint);
    }
    final area = Paint()..style = PaintingStyle.fill..color = const Color(0xFF5B5FEF).withOpacity(0.18);
    final line = Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = const Color(0xFF5B5FEF);
    final path = Path()
      ..moveTo(center.dx, center.dy - 70)
      ..lineTo(center.dx + 68, center.dy - 6)
      ..lineTo(center.dx + 30, center.dy + 64)
      ..lineTo(center.dx - 58, center.dy + 30)
      ..lineTo(center.dx - 46, center.dy - 38)
      ..close();
    canvas.drawPath(path, area);
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
          children: const [
            Text('薄弱点 TOP 3', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            SizedBox(height: 14),
            Text('暂无薄弱点数据，去多做几道题吧！', style: TextStyle(color: Colors.black54)),
          ],
        ),
      );
    }

    return _InsightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('薄弱点 TOP 3', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          ...weakPoints.map((e) {
            final name = e['name']?.toString() ?? '未知考点';
            final mastery = (e['mastery'] as num?)?.toDouble() ?? 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  SizedBox(width: 120, child: LinearProgressIndicator(value: mastery)),
                  const SizedBox(width: 10),
                  SizedBox(width: 40, child: Text('${(mastery * 100).toInt()}%')),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              // 获取最薄弱的知识点进行专项练习
              final weakestTopic = weakPoints.isNotEmpty ? weakPoints[0]['name']?.toString() : null;
              PracticePage.navigate(
                context,
                title: '薄弱点专项突破',
                subject: 'logic',
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

class _HeatmapCard extends StatelessWidget {
  const _HeatmapCard({
    required this.dailyStats,
    required this.totalStudyTimeSeconds,
  });

  final List<Map<dynamic, dynamic>> dailyStats;
  final int totalStudyTimeSeconds;

  @override
  Widget build(BuildContext context) {
    final studyHours = (totalStudyTimeSeconds / 3600).toStringAsFixed(1);
    final dailyAvg = dailyStats.isNotEmpty ? (totalStudyTimeSeconds / 3600 / 7).toStringAsFixed(1) : '0.0';
    
    // 简单模拟热力图块，实际应该根据 dailyStats 渲染
    final hasData = dailyStats.isNotEmpty;

    return _InsightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('本周学习热力图', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          const Text('一  二  三  四  五  六  日', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 8),
          Text(hasData ? '🟩 🟩 🟨 🟩 🟩 🟩 ⬜' : '⬜ ⬜ ⬜ ⬜ ⬜ ⬜ ⬜', style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 8),
          Text('累计 $studyHours h · 日均 $dailyAvg h', style: const TextStyle(color: Colors.black54)),
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
      ),
      child: child,
    );
  }
}
