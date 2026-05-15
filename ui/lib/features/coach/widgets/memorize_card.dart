import 'package:flutter/material.dart';

import '../../../core/native/mem_coach_native_bridge.dart';
import 'coach_shell_card.dart';

/// 背诵卡片数据
class MemorizeData {
  const MemorizeData({
    required this.id,
    required this.title,
    required this.content,
    this.answer,
    this.hint,
    this.topic,
  });

  final String id;
  final String title;
  final String content;
  final String? answer;
  final String? hint;
  final String? topic;

  factory MemorizeData.fromMap(Map<String, dynamic> map) {
    return MemorizeData(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      content: map['content']?.toString() ?? '',
      answer: map['answer']?.toString(),
      hint: map['hint']?.toString(),
      topic: map['topic']?.toString(),
    );
  }
}

/// 回调：检查答案完成
typedef OnCheckAnswer = void Function(MemorizeData data, bool correct);
/// 回调：查看提示
typedef OnShowHint = void Function(MemorizeData data, String hint);

class MemorizeCard extends StatefulWidget {
  const MemorizeCard({
    super.key,
    required this.data,
    this.onCheckAnswer,
    this.onShowHint,
  });

  final MemorizeData data;
  final OnCheckAnswer? onCheckAnswer;
  final OnShowHint? onShowHint;

  @override
  State<MemorizeCard> createState() => _MemorizeCardState();
}

class _MemorizeCardState extends State<MemorizeCard> {
  final _answerController = TextEditingController();
  bool _showAnswer = false;
  bool _showHint = false;
  bool? _isCorrect;

  @override
  void didUpdateWidget(covariant MemorizeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.id != widget.data.id) {
      setState(() {
        _answerController.clear();
        _showAnswer = false;
        _showHint = false;
        _isCorrect = null;
      });
    }
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  void _checkAnswer() {
    final userAnswer = _answerController.text.trim();
    if (userAnswer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入答案')),
      );
      return;
    }

    final correctAnswer = widget.data.answer ?? '';
    final isCorrect = userAnswer.toLowerCase() == correctAnswer.toLowerCase();

    setState(() {
      _showAnswer = true;
      _isCorrect = isCorrect;
    });

    widget.onCheckAnswer?.call(widget.data, isCorrect);

    // 记录学习记录
    MemCoachNativeBridge.submitAnswer(
      questionId: widget.data.id,
      userAnswer: userAnswer,
    ).catchError((e) {
      debugPrint('记录背诵答案失败: $e');
    });
  }

  void _toggleHint() {
    setState(() {
      _showHint = !_showHint;
    });
    if (_showHint && widget.data.hint != null) {
      widget.onShowHint?.call(widget.data, widget.data.hint!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;

    return CoachShellCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Text(d.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          if (d.topic != null && d.topic!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(d.topic!, style: const TextStyle(color: Colors.black54, fontSize: 13)),
          ],
          const SizedBox(height: 16),

          // 内容区
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FC),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              d.content,
              style: const TextStyle(fontSize: 18, height: 1.6, fontWeight: FontWeight.w700),
            ),
          ),

          // 提示区
          if (_showHint && d.hint != null && d.hint!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.withOpacity(0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline, color: Colors.blue, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(d.hint!, style: const TextStyle(height: 1.4)),
                  ),
                ],
              ),
            ),
          ],

          // 答案输入区
          if (!_showAnswer) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _answerController,
              decoration: InputDecoration(
                hintText: '输入你的答案...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onSubmitted: (_) => _checkAnswer(),
            ),
          ],

          // 结果显示
          if (_showAnswer && _isCorrect != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _isCorrect! ? const Color(0xFF20B486).withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isCorrect! ? '✓ 回答正确！' : '✗ 回答错误',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: _isCorrect! ? const Color(0xFF20B486) : Colors.orange,
                    ),
                  ),
                  if (!_isCorrect!) ...[
                    const SizedBox(height: 6),
                    Text('正确答案：${d.answer}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // 按钮行
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _showAnswer ? null : _checkAnswer,
                  child: Text(_showAnswer ? '已检查' : '检查答案'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _toggleHint,
                  icon: Icon(_showHint ? Icons.visibility_off : Icons.visibility),
                  label: Text(_showHint ? '隐藏提示' : '看提示'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
