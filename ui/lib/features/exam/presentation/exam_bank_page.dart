import 'dart:convert';

import 'package:flutter/material.dart';
import '../../../core/native/mem_coach_native_bridge.dart';
import '../../coach/widgets/coach_shell_card.dart';

/// 真题库页面
class ExamBankPage extends StatefulWidget {
  const ExamBankPage({super.key});

  @override
  State<ExamBankPage> createState() => _ExamBankPageState();
}

class _ExamBankPageState extends State<ExamBankPage> with SingleTickerProviderStateMixin {
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
                        style: const TextStyle(fontSize: 13, color: Colors.black38),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: primaryColor.withOpacity(0.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getQuestionCount(String subject) {
    switch (subject) {
      case 'math': return '25 道数学题';
      case 'logic': return '30 道逻辑题';
      case 'writing': return '2 道写作题';
      default: return '';
    }
  }

  Widget _buildWrongBookView() {
    return FutureBuilder<Map<String, dynamic>>(
      future: MemCoachNativeBridge.callAgentTool('wrong_book_list', {'limit': 50}),
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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

  const QuestionListPage({super.key, required this.year, required this.subject});

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
                          builder: (_) => QuestionDetailPage(questionId: q['id']),
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
                          Icon(Icons.chevron_right_rounded, color: primaryColor.withOpacity(0.5)),
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
            const Icon(Icons.info_outline_rounded, size: 34, color: Colors.black38),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(fontSize: 13.5, height: 1.5, color: Colors.black45),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _subjectName(String subject) {
    switch (subject) {
      case 'math': return '数学';
      case 'logic': return '逻辑';
      case 'writing': return '写作';
      default: return '';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('题目详情'),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: MemCoachNativeBridge.callAgentTool('exam_question_explain', {
          'question_id': widget.questionId,
        }),
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

          final correctAnswer = q['answer']?.toString();

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CoachShellCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 题干
                      Text(
                        q['stem'] ?? '',
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.6,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 选项列表
                      if (q['options'] != null)
                        ..._buildOptions(q['options'], correctAnswer),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 提交按钮
                if (!_showAnswer)
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _selectedAnswer == null || _submitting
                          ? null
                          : () => _submitAnswer(q),
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('提交答案', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),

                // 答题结果与解析
                if (_showAnswer) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _selectedAnswer == correctAnswer
                          ? const Color(0xFF20B486).withOpacity(0.08)
                          : const Color(0xFFEF476F).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _selectedAnswer == correctAnswer
                            ? const Color(0xFF20B486).withOpacity(0.2)
                            : const Color(0xFFEF476F).withOpacity(0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _selectedAnswer == correctAnswer
                                  ? Icons.check_circle_rounded
                                  : Icons.cancel_rounded,
                              color: _selectedAnswer == correctAnswer
                                  ? const Color(0xFF20B486)
                                  : const Color(0xFFEF476F),
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _selectedAnswer == correctAnswer ? '回答正确' : '回答错误',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: _selectedAnswer == correctAnswer
                                    ? const Color(0xFF20B486)
                                    : const Color(0xFFEF476F),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '正确答案：$correctAnswer',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        if (_selectedAnswer != correctAnswer) ...[
                          const SizedBox(height: 4),
                          Text(
                            '您的选择：$_selectedAnswer',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Row(
                    children: [
                      Icon(Icons.menu_book_rounded, color: Colors.black54, size: 20),
                      SizedBox(width: 8),
                      Text(
                        '题目解析',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black87),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  CoachShellCard(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    child: Text(
                      q['explanation'] ?? '暂无解析',
                      style: const TextStyle(fontSize: 14.5, height: 1.6, color: Colors.black87),
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

  List<Widget> _buildOptions(dynamic options, String? correctAnswer) {
    Map<String, dynamic> optionsMap = {};

    if (options is String) {
      final raw = options.trim();
      if (raw.isEmpty) return const [];

      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) return const [];
        optionsMap = Map<String, dynamic>.from(decoded);
      } catch (_) {
        optionsMap = Map<String, dynamic>.from(Uri.splitQueryString(raw));
      }
    } else if (options is Map) {
      optionsMap = Map<String, dynamic>.from(options);
    } else {
      return const [];
    }

    return optionsMap.entries.map((e) {
      final active = _selectedAnswer == e.key;
      final isCorrectAnswer = _showAnswer && e.key == correctAnswer;
      final isWrongSelection = _showAnswer && active && _selectedAnswer != correctAnswer;

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
        bgColor = active ? Theme.of(context).colorScheme.primary.withOpacity(0.08) : Colors.grey.shade50;
        borderColor = active ? Theme.of(context).colorScheme.primary : Colors.transparent;
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
              onTap: _showAnswer ? null : () => setState(() => _selectedAnswer = e.key),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                      child: Text(
                        e.value ?? '',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: active ? FontWeight.bold : FontWeight.normal,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    if (_showAnswer && isCorrectAnswer)
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF20B486), size: 22),
                    if (isWrongSelection)
                      const Icon(Icons.cancel_rounded, color: Color(0xFFEF476F), size: 22),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _messageState(String title, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline_rounded, size: 34, color: Colors.black38),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(fontSize: 13.5, height: 1.5, color: Colors.black45),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitAnswer(Map<String, dynamic> question) async {
    final isCorrect = _selectedAnswer == question['answer'];
    setState(() => _submitting = true);

    try {
      // 提交答题记录
      await MemCoachNativeBridge.callAgentTool('answer_submit', {
        'question_id': widget.questionId,
        'user_answer': _selectedAnswer,
        'correct_answer': question['answer'],
        'is_correct': isCorrect,
      });

      setState(() {
        _showAnswer = true;
        _submitting = false;
      });
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('提交失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
