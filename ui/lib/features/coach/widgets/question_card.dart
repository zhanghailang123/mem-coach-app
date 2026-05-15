import 'dart:convert';
import 'package:flutter/material.dart';

import '../../../core/native/mem_coach_native_bridge.dart';
import 'coach_shell_card.dart';

/// 题目数据模型
class QuestionData {
  const QuestionData({
    required this.id,
    required this.stem,
    required this.options,
    this.answer,
    this.explanation,
    this.topic,
    this.difficulty,
    this.year,
    this.sourceFile,
  });

  final String id;
  final String stem;
  final Map<String, String> options;
  final String? answer;
  final String? explanation;
  final String? topic;
  final String? difficulty;
  final int? year;
  final String? sourceFile;

  factory QuestionData.fromMap(Map<String, dynamic> map) {
    final optionsRaw = map['options']?.toString() ?? '{}';
    Map<String, String> options;
    try {
      final decoded = jsonDecode(optionsRaw);
      if (decoded is Map) {
        options = decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      } else {
        options = {};
      }
    } catch (_) {
      options = {};
    }

    return QuestionData(
      id: map['id']?.toString() ?? '',
      stem: map['stem']?.toString() ?? '',
      options: options,
      answer: map['answer']?.toString(),
      explanation: map['explanation']?.toString(),
      topic: map['topic']?.toString(),
      difficulty: map['difficulty']?.toString(),
      year: map['year'] is int ? map['year'] as int : int.tryParse(map['year']?.toString() ?? ''),
      sourceFile: map['source_file']?.toString(),
    );
  }
}

/// 答题结果
class AnswerResult {
  const AnswerResult({
    required this.correct,
    required this.correctAnswer,
    this.explanation,
    this.hint,
    this.masteryLevel,
  });

  final bool correct;
  final String correctAnswer;
  final String? explanation;
  final String? hint;
  final String? masteryLevel;
}

/// 回调：答题完成
typedef OnAnswerSubmitted = void Function(QuestionData question, String userAnswer, AnswerResult result);
/// 回调：下一题
typedef OnNextQuestion = void Function();
/// 回调：标记不确定
typedef OnUncertain = void Function(QuestionData question);

class QuestionCard extends StatefulWidget {
  const QuestionCard({
    super.key,
    required this.question,
    this.currentIndex,
    this.totalCount,
    this.onAnswerSubmitted,
    this.onNextQuestion,
    this.onUncertain,
  });

  final QuestionData question;
  final int? currentIndex;
  final int? totalCount;
  final OnAnswerSubmitted? onAnswerSubmitted;
  final OnNextQuestion? onNextQuestion;
  final OnUncertain? onUncertain;

  @override
  State<QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<QuestionCard> {
  String? selected;
  bool submitted = false;
  AnswerResult? result;
  bool _loading = false;

  @override
  void didUpdateWidget(covariant QuestionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.question.id != widget.question.id) {
      setState(() {
        selected = null;
        submitted = false;
        result = null;
      });
    }
  }

  Future<void> _submit() async {
    if (selected == null || submitted || _loading) return;

    setState(() => _loading = true);
    try {
      final answerResult = await MemCoachNativeBridge.submitAnswer(
        questionId: widget.question.id,
        userAnswer: selected!,
      );

      final answerResultObj = AnswerResult(
        correct: answerResult['correct'] == true,
        correctAnswer: answerResult['correct_answer']?.toString() ?? '',
        explanation: answerResult['explanation']?.toString(),
        hint: answerResult['hint']?.toString(),
        masteryLevel: answerResult['mastery_level']?.toString(),
      );

      if (mounted) {
        setState(() {
          submitted = true;
          result = answerResultObj;
          _loading = false;
        });
        widget.onAnswerSubmitted?.call(widget.question, selected!, answerResultObj);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('提交失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _handleUncertain() {
    widget.onUncertain?.call(widget.question);
    // 标记为已提交但未选择答案
    setState(() {
      submitted = true;
      result = AnswerResult(
        correct: false,
        correctAnswer: widget.question.answer ?? '',
        explanation: widget.question.explanation,
        hint: '标记为不确定，请查看解析后再次练习',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final headerText = [
      if (widget.currentIndex != null && widget.totalCount != null)
        '第 ${widget.currentIndex}/${widget.totalCount} 题',
      if (q.topic != null && q.topic!.isNotEmpty) q.topic,
      if (q.difficulty != null && q.difficulty!.isNotEmpty) _difficultyLabel(q.difficulty!),
    ].join(' · ');

    return CoachShellCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 题目信息头
          if (headerText.isNotEmpty)
            Text(headerText, style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),

          // 题干
          Text(
            q.stem,
            style: const TextStyle(fontSize: 17, height: 1.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),

          // 选项
          ...q.options.entries.map((entry) {
            final active = selected == entry.key;
            final isCorrectAnswer = submitted && result != null && entry.key == result!.correctAnswer;
            final isWrongSelection = submitted && result != null && active && !result!.correct;

            Color bgColor;
            Color borderColor;
            if (submitted) {
              if (isCorrectAnswer) {
                bgColor = const Color(0xFF20B486).withOpacity(0.1);
                borderColor = const Color(0xFF20B486);
              } else if (isWrongSelection) {
                bgColor = Colors.red.withOpacity(0.1);
                borderColor = Colors.red;
              } else {
                bgColor = Colors.grey.shade50;
                borderColor = Colors.transparent;
              }
            } else {
              bgColor = active ? Theme.of(context).colorScheme.primary.withOpacity(0.08) : Colors.grey.shade50;
              borderColor = active ? Theme.of(context).colorScheme.primary : Colors.transparent;
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: submitted ? null : () => setState(() => selected = entry.key),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    children: [
                      Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(width: 12),
                      Expanded(child: Text(entry.value)),
                      if (submitted && isCorrectAnswer)
                        const Icon(Icons.check_circle, color: Color(0xFF20B486), size: 20),
                      if (isWrongSelection)
                        const Icon(Icons.cancel, color: Colors.red, size: 20),
                    ],
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 8),

          // 结果提示
          if (submitted && result != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: result!.correct ? const Color(0xFF20B486).withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result!.correct ? '✓ 回答正确！' : '✗ 回答错误',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: result!.correct ? const Color(0xFF20B486) : Colors.orange,
                    ),
                  ),
                  if (!result!.correct && result!.explanation != null && result!.explanation!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(result!.explanation!, style: const TextStyle(height: 1.4)),
                  ],
                  if (result!.masteryLevel != null) ...[
                    const SizedBox(height: 6),
                    Text('掌握度：${result!.masteryLevel}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 按钮行
          if (!submitted)
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: selected == null || _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('提交'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _loading ? null : _handleUncertain,
                    child: const Text('不确定'),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => widget.onNextQuestion?.call(),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('下一题'),
              ),
            ),
        ],
      ),
    );
  }

  String _difficultyLabel(String difficulty) {
    switch (difficulty) {
      case 'basic':
        return '⭐';
      case 'medium':
        return '⭐⭐';
      case 'hard':
        return '⭐⭐⭐';
      default:
        return difficulty;
    }
  }
}
