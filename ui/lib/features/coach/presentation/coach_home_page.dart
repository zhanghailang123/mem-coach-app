import 'package:flutter/material.dart';

import '../../../core/native/mem_coach_native_bridge.dart';
import '../../settings/presentation/settings_page.dart';
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
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                      child: _Header(data: data),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: _ChatHeroCard(data: data, isLoading: isLoading),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
                      child: _ContextSectionTitle(),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: StudyMissionCard(),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                      child: _KnowledgeOverviewCard(data: data),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                      child: _InsightStrip(data: data),
                    ),
                  ),

                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 28, 20, 40),
                      child: QuickActionGrid(),
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
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF5B5FEF), Color(0xFF20B486)],
            ),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 21),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('MEM Coach', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 1),
              Text(
                [if (examText.isNotEmpty) examText, streakText].join(' · '),
                style: const TextStyle(color: Colors.black54, fontSize: 12.5),
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
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const SettingsPage(),
              ),
            );
          },
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    );
  }
}

class _ChatHeroCard extends StatelessWidget {
  const _ChatHeroCard({required this.data, required this.isLoading});

  final HomeData data;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final briefingText = isLoading
        ? '正在分析你的学习数据...'
        : data.briefing.isNotEmpty
            ? data.briefing
            : '告诉我你的目标，我会把真题、知识点和复习节奏串起来。';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFF),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFFE9ECFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.auto_awesome_rounded, color: Theme.of(context).colorScheme.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_getGreeting(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black54)),
                    const SizedBox(height: 1),
                    Text(
                      briefingText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.black38, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: () => ChatSheet.show(context),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 26, 16, 26),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.12)),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                    blurRadius: 36,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.06),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.chat_bubble_outline_rounded, color: Theme.of(context).colorScheme.primary, size: 22),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('从一次对话开始', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87, letterSpacing: -0.5)),
                        SizedBox(height: 4),
                        Text('问我：今天该怎么学？', style: TextStyle(color: Colors.black38, fontSize: 13.5)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF5B5FEF), Color(0xFF20B486)],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Color(0x405B5FEF), blurRadius: 10, offset: Offset(0, 4)),
                      ],
                    ),
                    child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 22),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('你可以这样问', style: TextStyle(fontSize: 11, color: Colors.black26, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: const [
              _PromptChip(label: '我今天只有 20 分钟', prompt: '帮我安排今天 20 分钟 MEM 学习计划'),
              _PromptChip(label: '帮我复盘错题', prompt: '根据我的错题和学习记录，帮我复盘当前最需要补的知识点'),
              _PromptChip(label: '出 3 道逻辑题', prompt: '给我 3 道逻辑题练习，并在我答完后讲解思路'),
            ],
          ),
        ],
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) return '夜深了，先轻量复盘。';
    if (hour < 12) return '上午好，开启一次高效学习。';
    if (hour < 14) return '中午好，适合做 3 道微练习。';
    if (hour < 18) return '下午好，把薄弱点补一补。';
    if (hour < 22) return '晚上好，复习正当时。';
    return '夜深了，先轻量复盘。';
  }
}

class _PromptChip extends StatelessWidget {
  const _PromptChip({required this.label, required this.prompt});

  final String label;
  final String prompt;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      avatar: const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFF5B5FEF)),
      onPressed: () => ChatSheet.show(context, initialText: prompt),
      backgroundColor: Colors.white.withOpacity(0.94),
      side: BorderSide(color: Colors.white.withOpacity(0.45)),
      labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.black87),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    );

  }
}

class _ContextSectionTitle extends StatelessWidget {
  const _ContextSectionTitle();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 24,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AI 已结合这些学习上下文', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              SizedBox(height: 2),
              Text('任务、知识图谱和练习数据会进入你的对话决策。', style: TextStyle(fontSize: 12.5, color: Colors.black54)),
            ],
          ),
        ),
      ],
    );
  }
}

class _KnowledgeOverviewCard extends StatelessWidget {

  const _KnowledgeOverviewCard({required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context) {
    final total = data.totalKnowledgeCount;
    final mastered = data.masteredCount.clamp(0, total == 0 ? data.masteredCount : total);
    final progress = total > 0 ? mastered / total : 0.0;
    final weakLabels = data.weakPoints
        .map((item) => item['name']?.toString() ?? item['title']?.toString() ?? item['knowledge_name']?.toString() ?? '')
        .where((name) => name.isNotEmpty && name != 'null')
        .take(3)
        .toList();

    return CoachShellCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: const Color(0xFF5B5FEF).withOpacity(0.10), borderRadius: BorderRadius.circular(15)),
                child: const Icon(Icons.account_tree_rounded, color: Color(0xFF5B5FEF)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('知识体系', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                    SizedBox(height: 2),
                    Text('由对话、真题和复习记录持续生成', style: TextStyle(fontSize: 12.5, color: Colors.black54)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.black.withOpacity(0.06),
              color: const Color(0xFF20B486),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            total > 0 ? '已掌握 $mastered / $total 个知识节点' : '开始对话或导入真题后，会逐步生成你的知识地图。',
            style: const TextStyle(fontSize: 13.5, color: Colors.black87, fontWeight: FontWeight.w600),
          ),
          if (weakLabels.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: weakLabels.map((name) => _WeakPointChip(name: name)).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _WeakPointChip extends StatelessWidget {
  const _WeakPointChip({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(name, style: const TextStyle(fontSize: 12.5, color: Color(0xFFE65100), fontWeight: FontWeight.w700)),
    );
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



