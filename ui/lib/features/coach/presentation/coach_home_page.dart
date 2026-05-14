import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/native/mem_coach_native_bridge.dart';
import '../widgets/coach_shell_card.dart';
import '../widgets/quick_action_grid.dart';
import '../widgets/study_mission_card.dart';

class CoachHomePage extends StatelessWidget {
  const CoachHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: _Header(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: _CoachBriefing(),
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
                child: _InsightStrip(),
              ),
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: _ChatBar(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('MEM Coach', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              SizedBox(height: 2),
              Text('距考试 226 天 · 连续学习 12 天', style: TextStyle(color: Colors.black54)),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: () {},
          icon: const Icon(Icons.notifications_none_rounded),
        ),
      ],
    );
  }
}

class _CoachBriefing extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
              const Expanded(
                child: Text(
                  '上午好，我看了你的学习曲线。',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            '昨天你逻辑题正确率 67%，但「否定后件式」连续错了 2 次。今天我不建议泛刷题，先用 5 道真题把这个点打穿。',
            style: TextStyle(fontSize: 15.5, height: 1.55, color: Colors.black87),
          ),
        ],
      ),
    );
  }
}

class _InsightStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(child: _MetricCard(title: '预估分', value: '156', delta: '+12')),
        SizedBox(width: 12),
        Expanded(child: _MetricCard(title: '正确率', value: '68%', delta: '+6%')),
        SizedBox(width: 12),
        Expanded(child: _MetricCard(title: '待背', value: '12', delta: '今日')),
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

class _ChatBar extends StatefulWidget {
  @override
  State<_ChatBar> createState() => _ChatBarState();
}

class _ChatBarState extends State<_ChatBar> {
  final _controller = TextEditingController();
  final List<_ChatMessage> _messages = [];
  StreamSubscription<AgentNativeEvent>? _sub;
  String _status = '';
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _sub = MemCoachNativeBridge.agentEvents.listen(
      _handleAgentEvent,
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _running = false;
          _status = '事件流异常：$error';
        });
      },
    );
  }

  void _handleAgentEvent(AgentNativeEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event.type) {
        case 'thinking_start':
          _status = 'Agent 正在思考...';
          _ensureAssistantMessage();
          break;
        case 'thinking_update':
          _status = 'Agent 正在回复...';
          _appendAssistantContent(event.content ?? '');
          break;
        case 'tool_start':
          _status = '正在调用工具：${event.toolName ?? 'unknown'}';
          break;
        case 'tool_result':
          _status = '工具调用完成：${event.toolName ?? 'unknown'}';
          break;
        case 'chat_message':
          _setAssistantContent(event.content ?? '');
          break;
        case 'complete':
          _running = false;
          _status = '完成';
          break;
        case 'error':
          _running = false;
          _status = event.error ?? '执行失败';
          _appendAssistantContent('\n${event.error ?? '执行失败'}');
          break;
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _running) return;
    setState(() {
      _messages.add(_ChatMessage(role: _ChatRole.user, content: text));
      _messages.add(const _ChatMessage(role: _ChatRole.assistant, content: ''));
      _status = '启动 Agent...';
      _running = true;
      _controller.clear();
    });
    try {
      await MemCoachNativeBridge.startAgentTurn(message: text);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _status = '启动失败：$error';
        _appendAssistantContent('\n启动失败：$error');
      });
    }
  }

  Future<void> _cancel() async {
    if (!_running) return;
    setState(() => _status = '正在取消...');
    try {
      await MemCoachNativeBridge.cancelAgentTurn();
      if (!mounted) return;
      setState(() {
        _running = false;
        _status = '已取消';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '取消失败：$error');
    }
  }

  void _ensureAssistantMessage() {
    if (_messages.isEmpty || _messages.last.role != _ChatRole.assistant) {
      _messages.add(const _ChatMessage(role: _ChatRole.assistant, content: ''));
    }
  }

  void _appendAssistantContent(String content) {
    if (content.isEmpty) return;
    _ensureAssistantMessage();
    final last = _messages.removeLast();
    _messages.add(last.copyWith(content: last.content + content));
  }

  void _setAssistantContent(String content) {
    _ensureAssistantMessage();
    final last = _messages.removeLast();
    _messages.add(last.copyWith(content: content.isEmpty ? last.content : content));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_messages.isNotEmpty || _status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: CoachShellCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_status.isNotEmpty) Text(_status, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                  if (_messages.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: SingleChildScrollView(
                        reverse: true,
                        child: Column(
                          children: _messages.map((message) => _ChatBubble(message: message)).toList(),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
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
              Expanded(
                child: TextField(
                  controller: _controller,
                  enabled: !_running,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration.collapsed(hintText: '问我：今天该怎么学？'),
                  onSubmitted: (_) => _send(),
                ),
              ),
              IconButton.filled(
                onPressed: _running ? _cancel : _send,
                icon: Icon(_running ? Icons.stop_rounded : Icons.send_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _ChatRole { user, assistant }

class _ChatMessage {
  const _ChatMessage({required this.role, required this.content});

  final _ChatRole role;
  final String content;

  _ChatMessage copyWith({String? content}) {
    return _ChatMessage(role: role, content: content ?? this.content);
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == _ChatRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: isUser ? Theme.of(context).colorScheme.primary : const Color(0xFFF4F6FA),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          message.content.isEmpty ? '...' : message.content,
          style: TextStyle(
            color: isUser ? Colors.white : Colors.black87,
            fontSize: 14.5,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}
