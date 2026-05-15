import 'package:flutter/material.dart';

import '../../../core/native/mem_coach_native_bridge.dart';
import '../widgets/chat_sheet.dart';
import '../widgets/coach_shell_card.dart';
import '../widgets/quick_action_grid.dart';
import '../widgets/study_mission_card.dart';

/// 首页数据模型
class HomeData {
  const HomeData({
    this.streak = 0,
    this.daysUntilExam = 0,
    this.todayTotal = 0,
    this.todayCorrect = 0,
    this.todayAccuracy = -1.0,
    this.overallAccuracy = -1.0,
    this.dueReviewCount = 0,
    this.masteredCount = 0,
    this.totalKnowledgeCount = 0,
    this.weakPoints = const [],
    this.briefing = '',
  });

  final int streak;
  final int daysUntilExam;
  final int todayTotal;
  final int todayCorrect;
  final double todayAccuracy;
  final double overallAccuracy;
  final int dueReviewCount;
  final int masteredCount;
  final int totalKnowledgeCount;
  final List<Map<String, dynamic>> weakPoints;
  final String briefing;

  factory HomeData.fromMap(Map<String, dynamic> map) {
    return HomeData(
      streak: (map['streak'] as num?)?.toInt() ?? 0,
      daysUntilExam: (map['days_until_exam'] as num?)?.toInt() ?? 0,
      todayTotal: (map['today_total'] as num?)?.toInt() ?? 0,
      todayCorrect: (map['today_correct'] as num?)?.toInt() ?? 0,
      todayAccuracy: (map['today_accuracy'] as num?)?.toDouble() ?? -1.0,
      overallAccuracy: (map['overall_accuracy'] as num?)?.toDouble() ?? -1.0,
      dueReviewCount: (map['due_review_count'] as num?)?.toInt() ?? 0,
      masteredCount: (map['mastered_count'] as num?)?.toInt() ?? 0,
      totalKnowledgeCount: (map['total_knowledge_count'] as num?)?.toInt() ?? 0,
      weakPoints: (map['weak_points'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      briefing: map['briefing'] as String? ?? '',
    );
  }

  bool get hasData => todayTotal > 0 || streak > 0 || masteredCount > 0;
}

class CoachHomePage extends StatefulWidget {
  const CoachHomePage({super.key});

  @override
  State<CoachHomePage> createState() => _CoachHomePageState();
}

class _CoachHomePageState extends State<CoachHomePage> {
  Future<HomeData>? _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  Future<HomeData> _loadData() async {
    try {
      final map = await MemCoachNativeBridge.getHomeData();
      return HomeData.fromMap(map);
    } catch (e) {
      debugPrint('加载首页数据失败: $e');
      return const HomeData();
    }
  }

  Future<void> _onRefresh() async {
    setState(() {
      _dataFuture = _loadData();
    });
    await _dataFuture;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HomeData>(
      future: _dataFuture,
      builder: (context, snapshot) {
        final data = snapshot.data ?? const HomeData();
        final isLoading = snapshot.connectionState == ConnectionState.waiting;

        return Scaffold(
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: _Header(data: data),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: _CoachBriefing(data: data, isLoading: isLoading),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: StudyMissionCard(),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: QuickActionGrid(),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: _InsightStrip(data: data),
                    ),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                        child: _ChatTriggerBar(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context) {
    final streakText = data.streak > 0 ? '连续学习 ${data.streak} 天' : '开始你的学习之旅';
    final examText = data.daysUntilExam > 0 ? '距考试 ${data.daysUntilExam} 天' : '';

    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF5B5FEF), Color(0xFF20B486)],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('MEM Coach', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(
                [if (examText.isNotEmpty) examText, streakText].join(' · '),
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('通知中心'),
                content: const Text('暂无新通知。\n\n通知功能将在后续版本中完善，包括：\n• 学习提醒\n• 复习提醒\n• 成就通知'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('知道了'),
                  ),
                ],
              ),
            );
          },
          icon: const Icon(Icons.notifications_none_rounded),
        ),
      ],
    );
  }
}

class _CoachBriefing extends StatelessWidget {
  const _CoachBriefing({required this.data, required this.isLoading});

  final HomeData data;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final briefingText = isLoading
        ? '正在分析你的学习数据...'
        : data.briefing.isNotEmpty
            ? data.briefing
            : '欢迎回来！点击下方开始你的学习之旅。';

    return CoachShellCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.smart_toy_rounded, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _getGreeting(),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            briefingText,
            style: const TextStyle(fontSize: 15.5, height: 1.55, color: Colors.black87),
          ),
          if (!isLoading && data.dueReviewCount > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.schedule_rounded, size: 16, color: Color(0xFFE65100)),
                  const SizedBox(width: 6),
                  Text(
                    '${data.dueReviewCount} 个知识点待复习',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFFE65100),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) return '夜深了，注意休息。';
    if (hour < 12) return '上午好，准备好学习了吗？';
    if (hour < 14) return '中午好，适当休息一下。';
    if (hour < 18) return '下午好，继续加油！';
    if (hour < 22) return '晚上好，复习好时机。';
    return '夜深了，注意休息。';
  }
}

class _InsightStrip extends StatelessWidget {
  const _InsightStrip({required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context) {
    // 预估分：基于正确率和练习量的简单估算，基准 130 + 加分
    final estimatedScore = data.overallAccuracy >= 0
        ? (130 + data.overallAccuracy * 40 + (data.todayTotal > 0 ? 6 : 0)).toInt()
        : '--';

    // 正确率
    final accuracyText = data.todayAccuracy >= 0
        ? '${(data.todayAccuracy * 100).toInt()}%'
        : data.overallAccuracy >= 0
            ? '${(data.overallAccuracy * 100).toInt()}%'
            : '--';

    // 正确率变化（相对全局来说今日的变化）
    final accuracyDelta = data.todayAccuracy >= 0 && data.overallAccuracy >= 0
        ? '${((data.todayAccuracy - data.overallAccuracy) * 100).toInt()}%'
        : '今日';

    // 待背
    final reviewText = data.dueReviewCount > 0 ? '${data.dueReviewCount}' : '0';
    final reviewDelta = data.dueReviewCount > 0 ? '待复习' : '已完成';

    return Row(
      children: [
        Expanded(child: _MetricCard(title: '预估分', value: '$estimatedScore', delta: estimatedScore is int ? '+${(estimatedScore - 130).clamp(0, 99)}' : '--')),
        const SizedBox(width: 12),
        Expanded(child: _MetricCard(title: '正确率', value: accuracyText, delta: accuracyDelta)),
        const SizedBox(width: 12),
        Expanded(child: _MetricCard(title: '待复习', value: reviewText, delta: reviewDelta)),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value, required this.delta});

  final String title;
  final String value;
  final String delta;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(delta, style: const TextStyle(color: Color(0xFF20B486), fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }
}

/// 聊天触发条 - 点击后打开全屏聊天 Sheet
class _ChatTriggerBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => ChatSheet.show(context),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 22,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                '问我：今天该怎么学？',
                style: TextStyle(
                  color: Colors.black38,
                  fontSize: 15,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_upward_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
