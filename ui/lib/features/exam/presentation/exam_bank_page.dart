import 'dart:convert';

import 'package:flutter/material.dart';
import '../../../core/native/mem_coach_native_bridge.dart';
import '../../../core/widgets/markdown_math.dart';
import '../../../core/state/page_context_manager.dart';
import '../../../core/widgets/ai_sparkle_logo.dart';
import '../../coach/widgets/coach_shell_card.dart';
import '../../coach/widgets/chat_sheet.dart';

/// 真题库页面
class ExamBankPage extends StatefulWidget {
  const ExamBankPage({super.key});

  @override
  State<ExamBankPage> createState() => _ExamBankPageState();
}

class _ExamBankPageState extends State<ExamBankPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedSubject = 'logic';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          '真题备考库',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: const Color(0xFF5B5FEF),
                unselectedLabelColor: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
                labelStyle: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14.5),
                unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w500, fontSize: 13.5),
                indicator: const UnderlineTabIndicator(
                  borderSide: BorderSide(color: Color(0xFF5B5FEF), width: 3),
                  insets: EdgeInsets.symmetric(horizontal: 8),
                ),
                tabs: const [
                  Tab(text: '科目库'),
                  Tab(text: '错题本'),
                  Tab(text: '收藏本'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildYearlyView(),
          _buildWrongBookView(),
          _buildFavoriteView(),
        ],
      ),
    );
  }

  Widget _buildYearlyView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '备考模块',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Theme.of(context).colorScheme.onSurface),
          ),
          const SizedBox(height: 12),
          // 三个科目卡片排版
          Row(
            children: [
              Expanded(
                child: _buildSubjectCard(
                  subject: 'math',
                  title: '数学真题',
                  subtitle: '25题/年',
                  desc: '核心考点解析',
                  icon: Icons.calculate_rounded,
                  colors: [const Color(0xFF5B5FEF), const Color(0xFF8C90FF)],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSubjectCard(
                  subject: 'logic',
                  title: '逻辑真题',
                  subtitle: '30题/年',
                  desc: '强化逻辑推理',
                  icon: Icons.psychology_rounded,
                  colors: [const Color(0xFF4F7BFF), const Color(0xFF4EA8DE)],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSubjectCard(
            subject: 'writing',
            title: '写作真题',
            subtitle: '2题/年',
            desc: '论说文与论证有效性分析精练',
            icon: Icons.edit_note_rounded,
            colors: [const Color(0xFF20B486), const Color(0xFF06D6A0)],
            isWide: true,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '选择年份 (${_subjectName(_selectedSubject)})',
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    color: Theme.of(context).colorScheme.onSurface),
              ),
              Text(
                '历年全国联考真题',
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 年份胶囊网格
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 2.1,
            ),
            itemCount: 14,
            itemBuilder: (context, index) {
              final year = 2025 - index;
              return _yearCapsule(year);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectCard({
    required String subject,
    required String title,
    required String subtitle,
    required String desc,
    required IconData icon,
    required List<Color> colors,
    bool isWide = false,
  }) {
    final isSelected = _selectedSubject == subject;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: isWide ? 85 : 125,
      decoration: BoxDecoration(
        color: isSelected
            ? null
            : (isDark ? const Color(0xFF1D1D26) : Colors.white),
        gradient: isSelected
            ? LinearGradient(
                colors: colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSelected
              ? Colors.transparent
              : (isDark ? const Color(0xFF2C2C35) : const Color(0xFFE2E6F5)),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? colors[0].withValues(alpha: 0.22)
                : Colors.black.withValues(alpha: 0.015),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            setState(() {
              _selectedSubject = subject;
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: isWide
                ? Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white.withValues(alpha: 0.2)
                              : colors[0].withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon,
                            color: isSelected ? Colors.white : colors[0],
                            size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? Colors.white
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              desc,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: isSelected
                                    ? Colors.white70
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : colors[0],
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : colors[0].withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(icon,
                                color: isSelected ? Colors.white : colors[0],
                                size: 20),
                          ),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white70 : colors[0],
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? Colors.white
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            desc,
                            style: TextStyle(
                              fontSize: 9.5,
                              color: isSelected
                                  ? Colors.white70
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.5),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _yearCapsule(int year) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1D1D26) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF2C2C35) : const Color(0xFFE2E6F5),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.01),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => _navigateToQuestionList(year),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$year',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '年联考真题',
                  style: TextStyle(
                    fontSize: 9,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWrongBookView() {
    return FutureBuilder<Map<String, dynamic>>(
      future:
          MemCoachNativeBridge.callAgentTool('wrong_book_list', {'limit': 50}),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final items = (snapshot.data?['items'] as List?) ?? [];
        if (items.isEmpty) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.assignment_turned_in_outlined,
                    size: 44, color: isDark ? Colors.white24 : Colors.black12),
                const SizedBox(height: 12),
                Text('暂无错题记录，继续保持！',
                    style: TextStyle(
                        color: isDark ? Colors.white38 : Colors.black38,
                        fontSize: 13)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return _wrongQuestionCard(item);
          },
        );
      },
    );
  }

  Widget _wrongQuestionCard(Map<String, dynamic> item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1D1D26) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: isDark ? const Color(0xFF3D2027) : const Color(0xFFFFE9EC),
            width: 1.0),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF476F)
                .withValues(alpha: isDark ? 0.05 : 0.015),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: () => _navigateToQuestionDetail(item['question_id']),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF476F).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '错误频次: ${item['wrong_count']}/${item['total_attempts']}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFEF476F),
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                      color: Color(0xFFEF476F),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                MarkdownMathPreview(
                  data: item['stem']?.toString() ?? '',
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.87)
                        : Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFavoriteView() {
    return FutureBuilder<Map<String, dynamic>>(
      future: MemCoachNativeBridge.callAgentTool(
          'exam_favorite_list', {'limit': 100}),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final questions = (snapshot.data?['questions'] as List?) ?? [];
        if (questions.isEmpty) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.star_border_rounded,
                    size: 48, color: isDark ? Colors.white24 : Colors.black12),
                const SizedBox(height: 12),
                Text(
                  '暂无收藏题目',
                  style: TextStyle(
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontSize: 13.5),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: questions.length,
          itemBuilder: (context, index) {
            final q = questions[index];
            return _favoriteQuestionCard(q);
          },
        );
      },
    );
  }

  Widget _favoriteQuestionCard(Map<String, dynamic> q) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final section = _sectionName(q['section']?.toString());
    final year = q['year']?.toString();
    final number = q['question_number']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1D1D26) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: isDark ? const Color(0xFF2C2C35) : const Color(0xFFE2E6F5),
            width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.08 : 0.015),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: () => _navigateToQuestionDetail(q['id']),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF5B5FEF).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$year年 · $section · 第$number题',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF5B5FEF),
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                      color: Color(0xFF5B5FEF),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                MarkdownMathPreview(
                  data: q['stem']?.toString() ?? '',
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.87)
                        : Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _navigateToQuestionList(int year) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuestionListPage(year: year, subject: _selectedSubject),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  void _navigateToQuestionDetail(String questionId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuestionDetailPage(questionId: questionId),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  String _subjectName(String subject) {
    switch (subject) {
      case 'math':
        return '数学';
      case 'logic':
        return '逻辑';
      case 'writing':
        return '写作';
      default:
        return subject;
    }
  }

  String _sectionName(String? section) {
    switch (section) {
      case 'math':
        return '数学';
      case 'logic':
        return '逻辑';
      case 'writing':
        return '写作';
      case 'english':
        return '英语';
      default:
        return section ?? '';
    }
  }
}

/// 题目列表页
class QuestionListPage extends StatefulWidget {
  final int year;
  final String subject;

  const QuestionListPage({
    super.key,
    required this.year,
    required this.subject,
  });

  @override
  State<QuestionListPage> createState() => _QuestionListPageState();
}

class _QuestionListPageState extends State<QuestionListPage> {
  bool _transitionEnded = false;
  late final Future<Map<String, dynamic>> _fetchFuture;

  @override
  void initState() {
    super.initState();
    _fetchFuture = MemCoachNativeBridge.callAgentTool('exam_question_search', {
      'subject': 'management_comprehensive',
      'section': widget.subject,
      'year': widget.year,
      'limit': 100,
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.animation != null) {
        void listener(AnimationStatus status) {
          if (status == AnimationStatus.completed) {
            route.animation!.removeStatusListener(listener);
            if (mounted) {
              setState(() {
                _transitionEnded = true;
              });
            }
          }
        }

        if (route.animation!.isCompleted) {
          setState(() {
            _transitionEnded = true;
          });
        } else {
          route.animation!.addStatusListener(listener);
        }
      } else {
        setState(() {
          _transitionEnded = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? Theme.of(context).scaffoldBackgroundColor
          : const Color(0xFFF9FAFF),
      appBar: AppBar(
        title: Text('${widget.year}年${_subjectName(widget.subject)}'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor:
            isDark ? Theme.of(context).colorScheme.onSurface : Colors.black87,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _fetchFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _messageState('加载真题失败', snapshot.error.toString());
          }

          if (!snapshot.hasData || !_transitionEnded) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data ?? {};
          if (data['error'] != null) {
            return _messageState('加载真题失败', data['error'].toString());
          }

          final questions = (data['questions'] as List?) ?? [];
          if (questions.isEmpty) {
            return _messageState('暂无真题数据', '请确认预置题库已导入，或重启应用后再试。');
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            itemCount: questions.length,
            itemBuilder: (context, index) {
              final q = questions[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1D1D26) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: isDark
                          ? const Color(0xFF2C2C35)
                          : const Color(0xFFE2E6F5),
                      width: 1.0),
                  boxShadow: [
                    BoxShadow(
                      color:
                          Colors.black.withValues(alpha: isDark ? 0.08 : 0.015),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              QuestionDetailPage(questionId: q['id']),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: const Color(0xFF5B5FEF)
                                  .withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF5B5FEF),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: MarkdownMathPreview(
                              data: q['stem']?.toString() ?? '',
                              maxLines: 2,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.87)
                                    : Colors.black87,
                                height: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right_rounded,
                              color: isDark ? Colors.white38 : Colors.black38),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _messageState(String title, String message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline_rounded,
                size: 34, color: isDark ? Colors.white38 : Colors.black38),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.87)
                      : Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: isDark ? Colors.white54 : Colors.black45),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _subjectName(String subject) {
    switch (subject) {
      case 'math':
        return '数学';
      case 'logic':
        return '逻辑';
      case 'writing':
        return '写作';
      default:
        return '';
    }
  }
}

/// 题目详情页
class QuestionDetailPage extends StatefulWidget {
  final String questionId;

  const QuestionDetailPage({super.key, required this.questionId});

  @override
  State<QuestionDetailPage> createState() => _QuestionDetailPageState();
}

class _QuestionDetailPageState extends State<QuestionDetailPage> {
  String? _selectedAnswer;
  bool _showAnswer = false;
  bool _submitting = false;
  bool _isFavorited = false; // 是否已收藏
  bool _transitionEnded = false; // 转场动画是否结束
  late final DateTime _enteredAt;
  late final Future<Map<String, dynamic>> _questionFuture;

  @override
  void initState() {
    super.initState();
    _enteredAt = DateTime.now();
    _questionFuture =
        MemCoachNativeBridge.callAgentTool('exam_question_explain', {
      'question_id': widget.questionId,
    });
    _checkFavoriteStatus();
    _setupAnimationListener();
    _setupPageContext();
  }

  void _setupPageContext() async {
    final data = await _questionFuture;
    if (data['error'] != null) return;
    final options = _parseOptions(data['options']);
    PageContextManager().setContext({
      'type': 'question',
      'question_id': widget.questionId,
      'stem': data['stem'],
      'options': options.entries
          .map((entry) => '${entry.key}. ${entry.value}')
          .join('\n'),
      'answer': _normalizeAnswer(data['answer']),
      'explanation': data['explanation'],
      'year': data['year'],
      'subject': data['subject'],
      'section': data['section'],
      'topic': data['topic'],
      'difficulty': data['difficulty'],
    });
  }

  @override
  void dispose() {
    PageContextManager().clearContext();
    super.dispose();
  }

  void _checkFavoriteStatus() async {
    try {
      final res =
          await MemCoachNativeBridge.callAgentTool('exam_favorite_check', {
        'question_id': widget.questionId,
      });
      if (mounted && res['favorited'] != null) {
        setState(() {
          _isFavorited = res['favorited'] == true;
        });
      }
    } catch (_) {}
  }

  void _setupAnimationListener() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.animation != null) {
        void listener(AnimationStatus status) {
          if (status == AnimationStatus.completed) {
            route.animation!.removeStatusListener(listener);
            if (mounted) {
              setState(() {
                _transitionEnded = true;
              });
            }
          }
        }

        if (route.animation!.isCompleted) {
          setState(() {
            _transitionEnded = true;
          });
        } else {
          route.animation!.addStatusListener(listener);
        }
      } else {
        setState(() {
          _transitionEnded = true;
        });
      }
    });
  }

  Future<void> _toggleFavorite() async {
    try {
      final tool = _isFavorited ? 'exam_favorite_remove' : 'exam_favorite_add';
      final res = await MemCoachNativeBridge.callAgentTool(tool, {
        'question_id': widget.questionId,
      });
      if (res['success'] == true) {
        setState(() {
          _isFavorited = !_isFavorited;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_isFavorited ? '已加入收藏' : '已取消收藏'),
              duration: const Duration(seconds: 1),
              backgroundColor:
                  _isFavorited ? const Color(0xFF5B5FEF) : Colors.black87,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? Theme.of(context).scaffoldBackgroundColor
          : const Color(0xFFF9FAFF),
      appBar: AppBar(
        title: const Text('题目详情',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor:
            isDark ? Theme.of(context).colorScheme.onSurface : Colors.black87,
        actions: [
          IconButton(
            icon: Icon(
              _isFavorited ? Icons.star_rounded : Icons.star_border_rounded,
              color: _isFavorited
                  ? const Color(0xFFFFD166)
                  : (isDark ? Colors.white54 : Colors.black54),
              size: 24,
            ),
            onPressed: _toggleFavorite,
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: _buildFloatingAiButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: _buildQuickActions(),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _questionFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _messageState('加载题目失败', snapshot.error.toString());
          }

          if (!snapshot.hasData || !_transitionEnded) {
            return const Center(child: CircularProgressIndicator());
          }

          final q = snapshot.data!;
          if (q['error'] != null) {
            return _messageState('加载题目失败', q['error'].toString());
          }

          final options = _parseOptions(q['options']);
          final correctAnswer = _normalizeAnswer(q['answer']);
          final isEssay = _isEssayQuestion(q);
          final isChoice = options.isNotEmpty && !isEssay;

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFlatHeader(q),
                CoachShellCard(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle(
                        icon: Icons.article_outlined,
                        title: '题干',
                        trailing: _typeName(q['type']?.toString()),
                      ),
                      const SizedBox(height: 12),
                      MarkdownMathView(
                        data: q['stem']?.toString() ?? '',
                        baseFontSize: 16,
                      ),
                    ],
                  ),
                ),
                if (isChoice) ...[
                  const SizedBox(height: 14),
                  CoachShellCard(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle(
                            icon: Icons.checklist_rounded, title: '请选择答案'),
                        const SizedBox(height: 14),
                        ..._buildOptions(options, correctAnswer),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                if (!_showAnswer) _buildActionButtons(q, isChoice),
                if (_showAnswer) ...[
                  _buildFeedbackBanner(
                    correctAnswer: correctAnswer,
                    isChoice: isChoice,
                    isEssay: isEssay,
                  ),
                  const SizedBox(height: 14),
                  CoachShellCard(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle(
                          icon: Icons.menu_book_rounded,
                          title: isEssay ? '参考解析' : '题目解析',
                          trailing: correctAnswer == null
                              ? null
                              : '答案：$correctAnswer',
                        ),
                        const SizedBox(height: 12),
                        MarkdownMathView(
                          data: q['explanation']?.toString() ?? '暂无解析',
                          baseFontSize: 15,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFlatHeader(Map<String, dynamic> q) {
    final year = q['year']?.toString();
    final section = _sectionName(q['section']?.toString());
    final questionNumber = q['question_number']?.toString();
    final topic = q['topic']?.toString();
    final difficulty = _difficultyName(q['difficulty']?.toString());
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              if (year != null && year != 'null') '$year年',
              if (section.isNotEmpty) section,
              if (questionNumber != null && questionNumber != 'null')
                '第 $questionNumber 题',
            ].join(' · '),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (difficulty.isNotEmpty)
                _metaPill(difficulty, isDifficulty: true),
              if (topic != null && topic.isNotEmpty && topic != 'null')
                _metaPill(topic),
              Text(
                'ID: ${widget.questionId}',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white30 : Colors.black26,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaPill(String text, {bool isDifficulty = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF2C2C35) : const Color(0xFFF4F6FA);
    Color textColor = isDark ? Colors.white54 : Colors.black54;

    if (isDifficulty) {
      if (text == '基础') {
        bgColor =
            const Color(0xFF20B486).withValues(alpha: isDark ? 0.15 : 0.08);
        textColor = const Color(0xFF20B486);
      } else if (text == '中等') {
        bgColor =
            const Color(0xFFFFD166).withValues(alpha: isDark ? 0.15 : 0.08);
        textColor = const Color(0xFFF5B041);
      } else if (text == '较难') {
        bgColor =
            const Color(0xFFEF476F).withValues(alpha: isDark ? 0.15 : 0.08);
        textColor = const Color(0xFFEF476F);
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: isDifficulty
            ? null
            : Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.04)),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold, color: textColor),
      ),
    );
  }

  Widget _sectionTitle({
    required IconData icon,
    required String title,
    String? trailing,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: isDark ? Colors.white54 : Colors.black54, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.87)
                  : Colors.black87),
        ),
        if (trailing != null && trailing.isNotEmpty) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  trailing,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActionButtons(Map<String, dynamic> q, bool isChoice) {
    if (!isChoice) {
      return SizedBox(
        width: double.infinity,
        height: 50,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: () => setState(() => _showAnswer = true),
          icon: const Icon(Icons.visibility_rounded),
          label: const Text('查看答案与解析',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold)),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              onPressed:
                  _submitting ? null : () => setState(() => _showAnswer = true),
              icon: const Icon(Icons.visibility_rounded, size: 18),
              label: const Text('查看答案'),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 50,
            child: FilledButton(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _selectedAnswer == null || _submitting
                  ? null
                  : () => _submitAnswer(q),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('提交答案',
                      style: TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeedbackBanner({
    required String? correctAnswer,
    required bool isChoice,
    required bool isEssay,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final answered = _selectedAnswer != null;
    final correct = answered && _selectedAnswer == correctAnswer;
    final color = isEssay || !isChoice
        ? Theme.of(context).colorScheme.primary
        : correct
            ? const Color(0xFF20B486)
            : answered
                ? const Color(0xFFEF476F)
                : const Color(0xFF4F7BFF);
    final icon = isEssay || !isChoice
        ? Icons.menu_book_rounded
        : correct
            ? Icons.check_circle_rounded
            : answered
                ? Icons.cancel_rounded
                : Icons.visibility_rounded;
    final title = isEssay
        ? '主观题请结合参考解析自评'
        : !isChoice
            ? '已显示参考答案'
            : !answered
                ? '已直接查看答案'
                : correct
                    ? '回答正确'
                    : '回答错误';
    final detail = isChoice
        ? [
            if (correctAnswer != null) '正确答案：$correctAnswer',
            if (answered && !correct) '你的选择：$_selectedAnswer',
          ].join(' · ')
        : (correctAnswer == null ? '请阅读下方解析' : '参考答案：$correctAnswer');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900, color: color),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    detail,
                    style: TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: isDark ? Colors.white54 : Colors.black54),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildOptions(
      Map<String, String> optionsMap, String? correctAnswer) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final entries = optionsMap.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return entries.map((e) {
      final active = _selectedAnswer == e.key;
      final isCorrectAnswer = _showAnswer && e.key == correctAnswer;
      final isWrongSelection =
          _showAnswer && active && _selectedAnswer != correctAnswer;

      Color bgColor;
      Color borderColor;
      if (_showAnswer) {
        if (isCorrectAnswer) {
          bgColor = const Color(0xFF20B486).withValues(alpha: 0.08);
          borderColor = const Color(0xFF20B486);
        } else if (isWrongSelection) {
          bgColor = const Color(0xFFEF476F).withValues(alpha: 0.08);
          borderColor = const Color(0xFFEF476F);
        } else {
          bgColor = isDark ? const Color(0xFF23232C) : Colors.grey.shade50;
          borderColor = Colors.transparent;
        }
      } else {
        bgColor = active
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
            : (isDark ? const Color(0xFF23232C) : Colors.grey.shade50);
        borderColor =
            active ? Theme.of(context).colorScheme.primary : Colors.transparent;
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: _showAnswer
                  ? null
                  : () => setState(() => _selectedAnswer = e.key),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: active || isCorrectAnswer || isWrongSelection
                            ? Colors.transparent
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.04)),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          e.key,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: active || isCorrectAnswer || isWrongSelection
                                ? Theme.of(context).colorScheme.primary
                                : (isDark ? Colors.white54 : Colors.black54),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DefaultTextStyle.merge(
                        style: TextStyle(
                          fontWeight:
                              active ? FontWeight.w800 : FontWeight.w500,
                        ),
                        child: MarkdownMathView(
                          data: e.value,
                          selectable: false,
                          baseFontSize: 14.5,
                        ),
                      ),
                    ),
                    if (_showAnswer && isCorrectAnswer)
                      const Icon(Icons.check_circle_rounded,
                          color: Color(0xFF20B486), size: 22),
                    if (isWrongSelection)
                      const Icon(Icons.cancel_rounded,
                          color: Color(0xFFEF476F), size: 22),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Map<String, String> _parseOptions(dynamic options) {
    Map<String, dynamic> optionsMap = {};

    if (options is String) {
      final raw = options.trim();
      if (raw.isEmpty) return const {};

      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) return const {};
        optionsMap = Map<String, dynamic>.from(decoded);
      } catch (_) {
        optionsMap = Map<String, dynamic>.from(Uri.splitQueryString(raw));
      }
    } else if (options is Map) {
      optionsMap = Map<String, dynamic>.from(options);
    } else {
      return const {};
    }

    return optionsMap
        .map((key, value) => MapEntry(key.toString(), value?.toString() ?? ''));
  }

  Widget _messageState(String title, String message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline_rounded,
                size: 34, color: isDark ? Colors.white38 : Colors.black38),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.87)
                      : Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: isDark ? Colors.white54 : Colors.black45),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  bool _isEssayQuestion(Map<String, dynamic> question) {
    final type = question['type']?.toString();
    final section = question['section']?.toString();
    return type == 'essay' || section == 'writing';
  }

  String? _normalizeAnswer(dynamic answer) {
    final text = answer?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text.toUpperCase();
  }

  String _sectionName(String? section) {
    switch (section) {
      case 'math':
        return '数学';
      case 'logic':
        return '逻辑';
      case 'writing':
        return '写作';
      case 'english':
        return '英语';
      default:
        return section ?? '';
    }
  }

  String _typeName(String? type) {
    switch (type) {
      case 'choice':
        return '选择题';
      case 'condition_sufficiency':
        return '条件充分性判断';
      case 'essay':
        return '写作题';
      case 'analysis':
        return '论证分析';
      default:
        return type ?? '';
    }
  }

  String _difficultyName(String? difficulty) {
    switch (difficulty) {
      case 'basic':
        return '基础';
      case 'medium':
        return '中等';
      case 'hard':
        return '较难';
      default:
        return difficulty ?? '';
    }
  }

  Future<void> _submitAnswer(Map<String, dynamic> question) async {
    setState(() => _submitting = true);

    try {
      // 提交答题记录
      await MemCoachNativeBridge.submitAnswer(
        questionId: widget.questionId,
        userAnswer: _selectedAnswer!,
        timeSpentSeconds: DateTime.now().difference(_enteredAt).inSeconds,
      );

      if (!mounted) return;
      setState(() {
        _showAnswer = true;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('提交失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildQuickActions() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1D1D26) : Colors.white,
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
        ],
        border: isDark
            ? const Border(
                top: BorderSide(
                  color: Color(0xFF2C2C35),
                  width: 1.0,
                ),
              )
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                final pageContext = PageContextManager().currentContext;
                ChatSheet.show(context,
                    pageContext: pageContext, initialText: '帮我讲解这道题');
              },
              icon: const Icon(Icons.lightbulb_outline, size: 18),
              label: const Text('讲解'),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                final pageContext = PageContextManager().currentContext;
                ChatSheet.show(context,
                    pageContext: pageContext, initialText: '推荐相似题目');
              },
              icon: const Icon(Icons.compare_arrows, size: 18),
              label: const Text('相似题'),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                final pageContext = PageContextManager().currentContext;
                ChatSheet.show(context,
                    pageContext: pageContext, initialText: '帮我总结知识点');
              },
              icon: const Icon(Icons.bookmark_outline, size: 18),
              label: const Text('总结'),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingAiButton() {
    return FloatingActionButton(
      onPressed: () {
        final pageContext = PageContextManager().currentContext;
        ChatSheet.show(context, pageContext: pageContext);
      },
      backgroundColor: const Color(0xFF5B5FEF),
      child: const AiSparkleLogo(size: 24, color: Colors.white),
    );
  }
}
