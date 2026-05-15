import 'package:flutter/material.dart';

import '../../../core/native/mem_coach_native_bridge.dart';
import '../widgets/question_card.dart';

/// 练习页面 - 展示题目列表，逐题练习
class PracticePage extends StatefulWidget {
  const PracticePage({
    super.key,
    required this.title,
    this.subject = 'logic',
    this.count = 5,
    this.topic,
  });

  final String title;
  final String subject;
  final int count;
  final String? topic;

  /// 导航到练习页面
  static Future<void> navigate(
    BuildContext context, {
    required String title,
    String subject = 'logic',
    int count = 5,
    String? topic,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PracticePage(
          title: title,
          subject: subject,
          count: count,
          topic: topic,
        ),
      ),
    );
  }

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  List<QuestionData> _questions = [];
  int _currentIndex = 0;
  bool _loading = true;
  String? _error;
  int _correctCount = 0;
  int _answeredCount = 0;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final questions = await MemCoachNativeBridge.getRandomQuestions(
        subject: widget.subject,
        count: widget.count,
        topic: widget.topic,
      );

      if (mounted) {
        setState(() {
          _questions = questions.map((q) => QuestionData.fromMap(q)).toList();
          _loading = false;
          _currentIndex = 0;
          _correctCount = 0;
          _answeredCount = 0;
        });

        if (_questions.isEmpty) {
          setState(() {
            _error = '暂无题目数据，请先导入真题 PDF';
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '加载题目失败：$e';
          _loading = false;
        });
      }
    }
  }

  void _onAnswerSubmitted(QuestionData question, String userAnswer, AnswerResult result) {
    setState(() {
      _answeredCount++;
      if (result.correct) _correctCount++;
    });
  }

  void _nextQuestion() {
    if (_currentIndex < _questions.length - 1) {
      setState(() => _currentIndex++);
    } else {
      _showCompleteDialog();
    }
  }

  void _onUncertain(QuestionData question) {
    setState(() => _answeredCount++);
    _nextQuestion();
  }

  void _showCompleteDialog() {
    final accuracy = _answeredCount > 0 ? (_correctCount / _answeredCount * 100).toInt() : 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('练习完成！'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              accuracy >= 80 ? Icons.emoji_events : Icons.school,
              size: 48,
              color: accuracy >= 80 ? const Color(0xFFFF9F1C) : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              '答对 $_correctCount / $_answeredCount 题',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              '正确率 $accuracy%',
              style: TextStyle(
                fontSize: 16,
                color: accuracy >= 80 ? const Color(0xFF20B486) : Colors.orange,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              accuracy >= 80 ? '表现优秀，继续保持！' : '继续加油，多练习薄弱知识点！',
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // 关闭对话框
              Navigator.of(context).pop(); // 返回上一页
            },
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop(); // 关闭对话框
              _loadQuestions(); // 重新加载题目
            },
            child: const Text('再来一轮'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (!_loading && _questions.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  '${_currentIndex + 1}/${_questions.length}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在加载题目...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loadQuestions,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_questions.isEmpty) {
      return const Center(child: Text('暂无题目'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (_currentIndex + 1) / _questions.length,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
            ),
          ),
          const SizedBox(height: 8),

          // 统计信息
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '已答 $_answeredCount 题',
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
              Text(
                '正确 $_correctCount 题',
                style: const TextStyle(color: Color(0xFF20B486), fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 题目卡片
          QuestionCard(
            key: ValueKey(_questions[_currentIndex].id),
            question: _questions[_currentIndex],
            currentIndex: _currentIndex + 1,
            totalCount: _questions.length,
            onAnswerSubmitted: _onAnswerSubmitted,
            onNextQuestion: _nextQuestion,
            onUncertain: _onUncertain,
          ),
        ],
      ),
    );
  }
}
