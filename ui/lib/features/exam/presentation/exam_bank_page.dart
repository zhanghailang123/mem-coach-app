import 'dart:convert';

import 'package:flutter/material.dart';
import '../../../core/native/mem_coach_native_bridge.dart';
import '../../../core/widgets/markdown_math.dart';
import '../../coach/widgets/coach_shell_card.dart';

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
  int? _selectedYear;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('真题库'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '按年份'),
            Tab(text: '错题本'),
            Tab(text: '收藏'),
          ],
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
    return Column(
      children: [
        // 科目筛选
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _subjectChip('数学', 'math'),
              const SizedBox(width: 8),
              _subjectChip('逻辑', 'logic'),
              const SizedBox(width: 8),
              _subjectChip('写作', 'writing'),
            ],
          ),
        ),
        // 年份列表 - 适配悬浮导航栏增加底部内边距
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: 14,
            itemBuilder: (context, index) {
              final year = 2025 - index;
              return _yearCard(year);
            },
          ),
        ),
      ],
    );
  }

  Widget _subjectChip(String label, String value) {
    final selected = _selectedSubject == value;
    final primaryColor = Theme.of(context).primaryColor;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w900 : FontWeight.w500,
          color: selected ? Colors.white : Colors.black54,
        ),
      ),
      selected: selected,
      selectedColor: primaryColor,
      backgroundColor: const Color(0xFFF0F2FA),
      checkmarkColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide.none,
      ),
      onSelected: (bool selected) {
        if (selected) {
          setState(() => _selectedSubject = value);
        }
      },
    );
  }

  Widget _yearCard(int year) {
    final primaryColor = Theme.of(context).primaryColor;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE9ECFF)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => _navigateToQuestionList(year),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      '$year',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: primaryColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$year年真题',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getQuestionCount(_selectedSubject),
                        style: const TextStyle(
                            fontSize: 13, color: Colors.black38),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: primaryColor.withOpacity(0.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getQuestionCount(String subject) {
    switch (subject) {
      case 'math':
        return '25 道数学题';
      case 'logic':
        return '30 道逻辑题';
      case 'writing':
        return '2 道写作题';
      default:
        return '';
    }
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
          return const Center(child: Text('暂无错题'));
        }

        // 错题列表 - 适配悬浮导航栏增加底部内边距
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9FA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFE9EC)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
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
                        color: const Color(0xFFEF476F).withOpacity(0.1),
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
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                      color: const Color(0xFFEF476F).withOpacity(0.5),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  item['stem'] ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Colors.black87,
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
    return const Center(child: Text('收藏功能待实现'));
  }

  void _navigateToQuestionList(int year) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuestionListPage(year: year, subject: _selectedSubject),
      ),
    );
  }

  void _navigateToQuestionDetail(String questionId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuestionDetailPage(questionId: questionId),
      ),
    );
  }
}

/// 题目列表页
class QuestionListPage extends StatelessWidget {
  final int year;
  final String subject;

  const QuestionListPage(
      {super.key, required this.year, required this.subject});

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    return Scaffold(
      appBar: AppBar(title: Text('$year年${_subjectName(subject)}')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: MemCoachNativeBridge.callAgentTool('exam_question_search', {
          'subject': 'management_comprehensive',
          'section': subject,
          'year': year,
          'limit': 100,
        }),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _messageState('加载真题失败', snapshot.error.toString());
          }

          if (!snapshot.hasData) {
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
                  color: const Color(0xFFF9FAFF),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE9ECFF)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
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
                              color: primaryColor.withOpacity(0.08),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: primaryColor,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              q['stem'] ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                                height: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right_rounded,
                              color: primaryColor.withOpacity(0.5)),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 34, color: Colors.black38),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(
                  fontSize: 13.5, height: 1.5, color: Colors.black45),
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
  late final Future<Map<String, dynamic>> _questionFuture;

  @override
  void initState() {
    super.initState();
    _questionFuture =
        MemCoachNativeBridge.callAgentTool('exam_question_explain', {
      'question_id': widget.questionId,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('题目详情'),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _questionFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _messageState('加载题目失败', snapshot.error.toString());
          }

          if (!snapshot.hasData) {
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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoCard(q),
                const SizedBox(height: 14),
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
                        mathColor: Theme.of(context).colorScheme.primary,
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
                          mathColor: Theme.of(context).colorScheme.primary,
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

  Widget _buildInfoCard(Map<String, dynamic> q) {
    final year = q['year']?.toString();
    final section = _sectionName(q['section']?.toString());
    final questionNumber = q['question_number']?.toString();
    final topic = q['topic']?.toString();
    final difficulty = _difficultyName(q['difficulty']?.toString());

    return CoachShellCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color:
                      Theme.of(context).colorScheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.school_rounded,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  [
                    if (year != null && year != 'null') '$year 年',
                    if (section.isNotEmpty) section,
                    if (questionNumber != null && questionNumber != 'null')
                      '第 $questionNumber 题',
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (topic != null && topic.isNotEmpty && topic != 'null')
                _metaPill(topic),
              if (difficulty.isNotEmpty) _metaPill(difficulty),
              _metaPill(widget.questionId),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
      ),
      child: Text(
        text,
        style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w800, color: Colors.black54),
      ),
    );
  }

  Widget _sectionTitle({
    required IconData icon,
    required String title,
    String? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.black54, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black87),
        ),
        if (trailing != null && trailing.isNotEmpty) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color:
                      Theme.of(context).colorScheme.primary.withOpacity(0.08),
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
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.22)),
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
                    style: const TextStyle(
                        fontSize: 13.5, height: 1.45, color: Colors.black54),
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
          bgColor = const Color(0xFF20B486).withOpacity(0.08);
          borderColor = const Color(0xFF20B486);
        } else if (isWrongSelection) {
          bgColor = const Color(0xFFEF476F).withOpacity(0.08);
          borderColor = const Color(0xFFEF476F);
        } else {
          bgColor = Colors.grey.shade50;
          borderColor = Colors.transparent;
        }
      } else {
        bgColor = active
            ? Theme.of(context).colorScheme.primary.withOpacity(0.08)
            : Colors.grey.shade50;
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
                            : Colors.black.withOpacity(0.04),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          e.key,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: active || isCorrectAnswer || isWrongSelection
                                ? Theme.of(context).colorScheme.primary
                                : Colors.black54,
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
                          mathColor: Theme.of(context).colorScheme.primary,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 34, color: Colors.black38),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(
                  fontSize: 13.5, height: 1.5, color: Colors.black45),
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
    final correctAnswer = _normalizeAnswer(question['answer']);
    final isCorrect = _selectedAnswer == correctAnswer;
    setState(() => _submitting = true);

    try {
      // 提交答题记录
      await MemCoachNativeBridge.callAgentTool('answer_submit', {
        'question_id': widget.questionId,
        'user_answer': _selectedAnswer,
        'correct_answer': correctAnswer,
        'is_correct': isCorrect,
      });

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
}
