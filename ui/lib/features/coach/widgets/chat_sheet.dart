import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/state/page_context_manager.dart';
import '../../../core/widgets/ai_sparkle_logo.dart';
import '../../../core/native/mem_coach_native_bridge.dart';
import 'markdown_bubble.dart';
import 'deep_thinking_card.dart';
import 'slash_command_panel.dart';
import '../utils/deep_thinking_parser.dart';
import '../utils/agent_stream_reducer.dart';
import 'tool_call_chip.dart';

/// 全屏沉浸式聊天 Sheet
/// 借鉴 OpenOmniBot ChatBotSheet 的 DraggableScrollableSheet 设计
class ChatSheet extends StatefulWidget {
  const ChatSheet({
    super.key,
    this.conversationId,
    this.initialText,
    this.pageContext,
  });

  /// 会话 ID，如果为 null 则创建新会话
  final int? conversationId;

  /// 打开聊天框时预填到输入框的文本
  final String? initialText;

  /// 页面上下文（当前题目/单词等）
  final Map<String, dynamic>? pageContext;

  /// 打开全屏聊天 Sheet

  static Future<void> show(
    BuildContext context, {
    int? conversationId,
    String? initialText,
    Map<String, dynamic>? pageContext,
  }) async {
    // 如果没有指定会话ID，尝试加载最新会话
    int? targetConversationId = conversationId;
    if (targetConversationId == null) {
      try {
        final conversations = await MemCoachNativeBridge.getConversations();
        if (conversations.isNotEmpty) {
          targetConversationId = conversations.first['id'] as int?;
        }
      } catch (e) {
        // 获取失败，使用null（会创建新会话）
      }
    }

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChatSheet(
        conversationId: targetConversationId,
        initialText: initialText,
        pageContext: pageContext,
      ),
    );
  }

  @override
  State<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<ChatSheet> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  StreamSubscription<AgentNativeEvent>? _sub;
  String _status = '';
  bool _running = false;
  final StringBuffer _assistantDeltaBuffer = StringBuffer();
  Timer? _assistantDeltaFlushTimer;
  static const Duration _assistantDeltaFlushInterval =
      Duration(milliseconds: 50);

  // Agent 流式事件状态管理（借鉴 OpenOmniBot Reducer 模式）
  final AgentStreamReducer _agentStreamReducer = const AgentStreamReducer();
  AgentStreamState _agentStreamState = const AgentStreamState();

  // 会话状态
  int? _conversationId;
  bool _isLoadingConversation = false;

  // 深度思考状态
  String _thinkingText = '';
  bool _isThinking = false;
  int _thinkingStage = 1;
  int? _thinkingStartTime;
  int? _thinkingEndTime;
  String _reasoningEffort = '中';
  static const String _thinkingPlaceholder = '正在理解你的问题...';

  // 学习状态
  String _currentStateName = '';

  // 斜杠命令状态

  bool _showSlashCommandPanel = false;

  // 重试状态
  String? _lastSentText;
  bool _nativePersistsCurrentTurn = false;

  // 当前轮次工具调用历史，用于下一轮传回 Native 保留 ReAct 上下文
  final List<_ToolCallRecord> _currentTurnToolCalls = [];

  // 自动补全状态

  bool _isAutoCompleting = false;

  Map<String, dynamic>? _activePageContext;
  String? _manuallyClearedContextId; // 手动清除的上下文ID

  @override
  void initState() {
    super.initState();
    _activePageContext = widget.pageContext;
    final initialText = widget.initialText?.trim();
    if (initialText != null && initialText.isNotEmpty) {
      _controller.text = initialText;
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
    }

    // 监听页面上下文变化
    PageContextManager().addListener(_onPageContextChanged);

    // 初始化会话
    _initConversation();
  }

  void _onPageContextChanged() {
    if (!mounted) return;
    final newContext = PageContextManager().currentContext;
    if (newContext == null) {
      setState(() {
        _activePageContext = null;
        _manuallyClearedContextId = null;
      });
      return;
    }

    final newId = (newContext['question_id'] ?? newContext['word_id'])?.toString();
    if (_manuallyClearedContextId != null && _manuallyClearedContextId == newId) {
      // 忽略手动清除的相同上下文更新
      return;
    }

    setState(() {
      _activePageContext = newContext;
      _manuallyClearedContextId = null;
    });
  }

  void _subscribeAgentEvents() {
    _sub ??= MemCoachNativeBridge.agentEvents.listen(
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

  /// 初始化会话
  Future<void> _initConversation() async {
    if (widget.conversationId != null) {
      // 加载现有会话
      await _loadConversation(widget.conversationId!);
    } else {
      // 创建新会话
      await _createNewConversation();
    }
    await _syncAgentRunningState();
    _subscribeAgentEvents();
  }

  Future<void> _syncAgentRunningState() async {
    try {
      final state = await MemCoachNativeBridge.getAgentRunningState(
        conversationId: _conversationId,
      );
      final running =
          state['running'] == true || state['running']?.toString() == 'true';
      final status = state['status']?.toString();
      if (!mounted) return;
      if (!running) {
        if (status == 'interrupted') {
          setState(() {
            _status = '上次生成已中断，可以继续提问';
          });
        }
        return;
      }
      setState(() {
        _running = true;
        _status = 'Agent 正在后台生成...';
        _isThinking = true;
        if (_thinkingText.trim().isEmpty) {
          _thinkingText = _thinkingPlaceholder;
        }
        _thinkingStage = 1;
        _thinkingStartTime ??= _nullableInt(state['started_at']) ??
            DateTime.now().millisecondsSinceEpoch;
      });
    } catch (_) {
      // 状态查询失败不影响聊天框使用，后续事件仍会正常接入。
    }
  }

  /// 创建新会话
  Future<void> _createNewConversation() async {
    try {
      final result = await MemCoachNativeBridge.createConversation(
        title: '新对话',
      );
      if (!mounted) return;
      setState(() {
        _conversationId = result['id'] as int?;
        _status = ''; // 清空初始化状态
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = '创建会话失败：$error';
      });
    }
  }

  /// 加载现有会话
  Future<void> _loadConversation(int conversationId) async {
    setState(() {
      _isLoadingConversation = true;
      _status = '加载会话中...';
    });

    try {
      final messages = await MemCoachNativeBridge.getConversationMessages(
        conversationId: conversationId,
      );

      if (!mounted) return;
      setState(() {
        _conversationId = conversationId;
        _messages.clear();
        for (final msg in messages) {
          final role = msg['role'] as String? ?? 'user';
          final content = msg['content'] as String? ?? '';
          final timestamp =
              _parseMessageTimestamp(msg['timestamp'] ?? msg['created_at']);
          final toolCallsRaw = msg['tool_calls'];
          final toolCalls = toolCallsRaw is List
              ? toolCallsRaw
                  .whereType<Map>()
                  .map((item) =>
                      _ToolCallRecord.fromJson(Map<String, dynamic>.from(item)))
                  .toList()
              : <_ToolCallRecord>[];
          _messages.add(_ChatMessage(
            role: switch (role) {
              'assistant' => _ChatRole.assistant,
              'tool' => _ChatRole.tool,
              'tool_chip' => _ChatRole.toolChip,
              'skill_chip' => _ChatRole.skillChip,
              'system' => _ChatRole.system,
              _ => _ChatRole.user,
            },
            content: content,
            reasoningContent: _nullableMessageText(
              msg['reasoning_content'] ?? msg['thinking_content'],
            ),
            toolCallId: msg['tool_call_id']?.toString(),
            toolArguments: _nullableMessageText(
              msg['tool_arguments'] ?? msg['arguments'],
            ),
            toolResult: _nullableMessageText(
              msg['tool_result'] ?? msg['result'],
            ),
            toolError: _nullableMessageText(
              msg['tool_error'] ?? msg['error'],
            ),
            toolDurationMs: _nullableInt(msg['tool_duration_ms']),
            skillId: _nullableMessageText(msg['skill_id']),
            skillConfidence: msg['skill_confidence'] is num
                ? (msg['skill_confidence'] as num).toDouble()
                : double.tryParse(msg['skill_confidence']?.toString() ?? ''),
            skillTriggerReason:
                _nullableMessageText(msg['skill_trigger_reason']),
            toolCalls: toolCalls,
            timestamp: timestamp,
          ));
        }
        _isLoadingConversation = false;
        _status = '';
      });

      // 首次加载历史消息时直接定位到底部，避免打开聊天框时出现滚动动画卡顿。
      _scrollToBottom(animated: false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingConversation = false;
        _status = '加载会话失败：$error';
      });
    }
  }

  void _handleAgentEvent(AgentNativeEvent event) {
    if (!mounted) return;
    final isHighFrequencyStreamEvent = event.type == 'thinking_update' ||
        (event.type == 'chat_message' && event.isFinal != true);

    // 使用 Reducer 模式检查事件是否需要处理
    final seq = event.seq;
    final reduceResult =
        _agentStreamReducer.reduce(_agentStreamState, event.type, seq);
    if (!reduceResult.accepted) {
      return; // 忽略重复事件
    }
    _agentStreamState = reduceResult.nextState;

    if (event.type == 'chat_message' &&
        event.isDelta &&
        event.isFinal != true) {
      _queueAssistantDelta(event.content ?? '');
      return;
    }

    final pendingAssistantDelta =
        event.type == 'chat_message' ? '' : _takePendingAssistantDelta();
    setState(() {
      if (pendingAssistantDelta.isNotEmpty) {
        _status = 'Agent 正在回复...';
        _isThinking = false;
        _thinkingStage = 3;
        _thinkingEndTime ??= DateTime.now().millisecondsSinceEpoch;
        _appendAssistantDelta(pendingAssistantDelta);
      }
      switch (event.type) {
        case 'state_changed':
          _currentStateName = event.stateName ?? '';
          _status = '模式：$_currentStateName';
          break;
        case 'skill_activated':
          final skill = _ActiveSkill.fromEvent(event);
          if (skill != null && !_hasCurrentTurnSkillChip(skill)) {
            _messages.add(_ChatMessage(
              role: _ChatRole.skillChip,
              content: skill.name,
              timestamp: DateTime.now(),
              skillId: skill.id,
              skillConfidence: skill.confidence,
              skillTriggerReason: skill.triggerReason,
            ));
            _status = '已激活策略：${skill.name}';
          }
          break;
        case 'thinking_start':
          final effort = event.raw['effort']?.toString();
          if (effort != null) {
            _reasoningEffort = _effortLabel(effort);
          }
          _status = 'Agent 正在思考（$_reasoningEffort强度）...';
          _isThinking = true;
          if (_thinkingText.trim().isEmpty) {
            _thinkingText = _thinkingPlaceholder;
          }
          _thinkingStage = 1;
          _thinkingStartTime ??= DateTime.now().millisecondsSinceEpoch;
          _thinkingEndTime = null;
          break;
        case 'thinking_update':
          _status = 'Agent 正在思考...';
          // 如果当前是占位符，先清空再追加真实内容
          if (_thinkingText == _thinkingPlaceholder) {
            _thinkingText = '';
          }
          _thinkingText += event.content ?? '';
          _thinkingStage = 2;
          final thinkingResult =
              DeepThinkingParser.extractDeepThinking(_thinkingText);
          if (thinkingResult.hasAnyContent) {
            _thinkingText = thinkingResult.toDisplayText();
          }
          break;
        case 'tool_call_start':
          _status = '正在调用工具：${event.toolName ?? 'unknown'}';
          final toolCallId = event.toolCallId ??
              'tool_${DateTime.now().millisecondsSinceEpoch}_${_currentTurnToolCalls.length}';
          // 插入工具调用胶囊到消息列表
          _messages.add(_ChatMessage(
            role: _ChatRole.toolChip,
            content: event.toolName ?? 'unknown',
            timestamp: DateTime.now(),
            toolCallId: toolCallId,
            toolArguments: _eventToolArguments(event),
          ));

          _currentTurnToolCalls.add(_ToolCallRecord(
            id: toolCallId,
            name: event.toolName ?? 'unknown',
            arguments: _eventToolArguments(event) ?? '{}',
          ));

          break;
        case 'tool_call_complete':
          _status = '工具调用完成：${event.toolName ?? 'unknown'}';
          final toolResult = _eventToolResult(event) ?? '';
          // 更新最后一个工具胶囊，显示耗时
          for (var i = _messages.length - 1; i >= 0; i--) {
            if (_messages[i].role == _ChatRole.toolChip &&
                _isMatchingToolChip(_messages[i], event)) {
              final startTime = _messages[i].timestamp ?? DateTime.now();
              final duration = DateTime.now().difference(startTime);
              _messages[i] = _messages[i].copyWith(
                toolResult: toolResult,
                toolDurationMs: duration.inMilliseconds,
              );
              break;
            }
          }

          if (event.toolCallId != null) {
            _messages.add(_ChatMessage(
              role: _ChatRole.tool,
              content: toolResult,
              toolCallId: event.toolCallId,
              timestamp: DateTime.now(),
            ));
          }
          break;
        case 'tool_call_retry':
          _status = event.raw['progress']?.toString() ??
              '工具调用重试：${event.toolName ?? 'unknown'}';
          break;
        case 'tool_call_error':
          _status = '工具调用失败：${event.toolName ?? 'unknown'}';
          for (var i = _messages.length - 1; i >= 0; i--) {
            if (_messages[i].role == _ChatRole.toolChip &&
                _isMatchingToolChip(_messages[i], event)) {
              final startTime = _messages[i].timestamp ?? DateTime.now();
              final duration = DateTime.now().difference(startTime);
              _messages[i] = _messages[i].copyWith(
                toolError: event.error ?? '工具调用失败',
                toolResult: _eventToolResult(event),
                toolDurationMs: duration.inMilliseconds,
              );
              break;
            }
          }
          break;
        case 'chat_message':
          _discardPendingAssistantDelta();
          _status = 'Agent 正在回复...';
          _isThinking = false;
          _thinkingStage = 3;
          _thinkingEndTime ??= DateTime.now().millisecondsSinceEpoch;
          _appendAssistantContent(event.content ?? '');
          if (event.isFinal) {
            _attachCurrentToolCallsToLastAssistantMessage();
          }
          break;
        case 'context_compacted':
          final prevTokens = event.raw['previousPromptTokens'] ?? 0;
          _status = '上下文已压缩（原 Token: $prevTokens）';
          _appendAssistantContent('\n\n---\n_上下文已自动压缩以优化对话质量_\n\n---\n');
          break;
        case 'complete':
          _running = false;
          _status = '';
          _isThinking = false;
          _thinkingText = '';
          _thinkingStage = 4;
          _thinkingEndTime = DateTime.now().millisecondsSinceEpoch;
          _attachThinkingToLastAssistantMessage();
          if (!_nativePersistsCurrentTurn) {
            _saveAssistantMessageToDatabase();
          }
          _thinkingStartTime = null;
          break;
        case 'error':
          _running = false;
          _status = event.error ?? '执行失败';
          _appendAssistantContent('\n${event.error ?? '执行失败'}');
          _isThinking = false;
          _thinkingStage = 4;
          _thinkingEndTime = DateTime.now().millisecondsSinceEpoch;
          _attachThinkingToLastAssistantMessage();
          if (!_nativePersistsCurrentTurn) {
            _saveAssistantMessageToDatabase();
          }
          // 清空状态
          _thinkingText = '';
          break;
      }
    });
    _scrollToBottom(animated: !isHighFrequencyStreamEvent);
  }

  bool _isMatchingToolChip(_ChatMessage message, AgentNativeEvent event) {
    final eventToolCallId = event.toolCallId;
    if (eventToolCallId != null && eventToolCallId.isNotEmpty) {
      return message.toolCallId == eventToolCallId;
    }
    return message.content == (event.toolName ?? 'unknown') &&
        message.toolDurationMs == null &&
        message.toolResult == null &&
        message.toolError == null;
  }

  String? _eventToolArguments(AgentNativeEvent event) {
    return _firstNonBlank([event.argsJson, event.arguments]);
  }

  String? _eventToolResult(AgentNativeEvent event) {
    return _firstNonBlank([
      event.rawResultJson,
      event.resultPreviewJson,
      event.result,
      event.summary,
    ]);
  }

  String? _firstNonBlank(List<String?> values) {
    for (final value in values) {
      final text = value?.trim();
      if (text != null && text.isNotEmpty && text != 'null') {
        return text;
      }
    }
    return null;
  }

  bool _hasCurrentTurnSkillChip(_ActiveSkill skill) {
    final lastUserIndex = _messages.lastIndexWhere(
      (message) => message.role == _ChatRole.user,
    );
    final startIndex = lastUserIndex < 0 ? 0 : lastUserIndex + 1;
    for (var i = startIndex; i < _messages.length; i++) {
      final message = _messages[i];
      if (message.role != _ChatRole.skillChip) continue;
      final sameId = message.skillId != null && message.skillId == skill.id;
      final sameName = message.content == skill.name;
      if (sameId || sameName) return true;
    }
    return false;
  }

  /// 保存助手消息到数据库
  Future<void> _saveAssistantMessageToDatabase() async {
    if (_conversationId == null || _messages.isEmpty) return;

    final lastMessage = _messages.last;
    if (lastMessage.role != _ChatRole.assistant) return;

    try {
      await MemCoachNativeBridge.addChatMessage(
        conversationId: _conversationId!,
        role: 'assistant',
        content: lastMessage.content,
        reasoningContent: lastMessage.reasoningContent,
        toolCalls: lastMessage.toolCalls.map((call) => call.toJson()).toList(),
      );
      for (final message in _messages.where((message) =>
          message.role == _ChatRole.tool && message.toolCallId != null)) {
        await MemCoachNativeBridge.addChatMessage(
          conversationId: _conversationId!,
          role: 'tool',
          content: message.content,
          toolCallId: message.toolCallId,
        );
      }

      // 更新会话消息数量
      await MemCoachNativeBridge.updateConversationMessageCount(
        conversationId: _conversationId!,
      );

      // 首轮对话后自动生成标题
      final assistantCount =
          _messages.where((m) => m.role == _ChatRole.assistant).length;
      if (assistantCount == 1) {
        _generateConversationTitle();
      }
    } catch (error) {
      // 忽略数据库错误
      debugPrint('保存助手消息失败：$error');
    }
  }

  Future<void> _generateConversationTitle() async {
    if (_conversationId == null) return;
    final userMessages =
        _messages.where((m) => m.role == _ChatRole.user).toList();
    if (userMessages.isEmpty) return;
    final firstUserMessage = userMessages.first.content.trim();
    if (firstUserMessage.isEmpty) return;
    final title = firstUserMessage.length > 20
        ? '${firstUserMessage.substring(0, 20)}...'
        : firstUserMessage;
    try {
      await MemCoachNativeBridge.updateConversationTitle(
          conversationId: _conversationId!, title: title);
    } catch (e) {
      // 静默失败
    }
  }

  @override
  void dispose() {
    _assistantDeltaFlushTimer?.cancel();
    _sub?.cancel();
    _controller.dispose();

    _scrollController.dispose();
    PageContextManager().removeListener(_onPageContextChanged); // 移除上下文监听
    PageContextManager().requestRefresh(); // 销毁聊天框时发送全局数据刷新广播
    super.dispose();
  }

  void _handleInputChanged(String text) {
    // 避免自动补全时的递归调用
    if (_isAutoCompleting) return;

    // 检测是否输入了斜杠命令
    final trimmed = text.trim();
    final showPanel = trimmed.startsWith('/') && !_running;

    if (showPanel != _showSlashCommandPanel) {
      setState(() {
        _showSlashCommandPanel = showPanel;
      });
    }

    // @PDF 自动补全
    _handlePdfAutoComplete(text);
  }

  /// 处理 @PDF 自动补全
  void _handlePdfAutoComplete(String text) {
    if (text.isEmpty) return;

    // 检查是否以 @p 或 @P 结尾（不区分大小写）
    final lowerText = text.toLowerCase();
    if (lowerText.endsWith('@p') && !lowerText.endsWith('@pdf')) {
      // 自动补全为 @PDF
      _isAutoCompleting = true;
      final newText = '${text.substring(0, text.length - 2)}@PDF ';
      _controller.text = newText;
      _controller.selection = TextSelection.collapsed(offset: newText.length);
      _isAutoCompleting = false;
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _running) return;

    // 检查是否是斜杠命令
    final commandResult = parseSlashCommand(text);
    if (commandResult.isCommand) {
      // 处理命令
      _controller.clear();
      setState(() {
        _showSlashCommandPanel = false;
      });
      _handleSlashCommand(SlashCommand(
        type: commandResult.type,
        name: text.substring(1).split(' ')[0],
        description: '',
        icon: Icons.terminal_rounded,
      ));
      return;
    }

    _lastSentText = text;
    final sentAt = DateTime.now();

    setState(() {
      _messages.add(_ChatMessage(
        role: _ChatRole.user,
        content: text,
        timestamp: sentAt,
      ));
      _status = 'Agent 正在思考（$_reasoningEffort强度）...';
      _running = true;
      _controller.clear();
      _showSlashCommandPanel = false;
      _currentTurnToolCalls.clear();
      _thinkingText = _thinkingPlaceholder;
      _isThinking = true;
      _thinkingStage = 1;
      _thinkingStartTime = sentAt.millisecondsSinceEpoch;
      _thinkingEndTime = null;
    });
    _scrollToBottom(animated: false);

    final history = _messagesForNativeHistory();

    try {
      final conversationId = _conversationId;
      _nativePersistsCurrentTurn = conversationId != null;
      if (conversationId != null) {
        await MemCoachNativeBridge.addChatMessage(
          conversationId: conversationId,
          role: 'user',
          content: text,
        );
      }

      await MemCoachNativeBridge.startAgentTurn(
        message: text,
        conversationId: conversationId,
        history: history,
        context: _activePageContext ?? {},
      );
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
      await MemCoachNativeBridge.cancelAgentTurn(
        conversationId: _conversationId,
      );
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

  /// 重试上一次发送
  Future<void> _retryLastSend() async {
    if (_lastSentText == null || _lastSentText!.isEmpty || _running) return;

    // 将文本放回输入框
    _controller.text = _lastSentText!;
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);

    // 清除失败状态
    setState(() {
      _status = '';
    });

    // 重新发送
    await _send();
  }

  /// 语音输入（占位符）
  void _onVoiceInput() {
    // TODO: 实现语音输入功能
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('语音输入功能开发中...'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showPdfPicker() async {
    setState(() => _status = '正在读取 PDF 列表...');
    try {
      final documents = await MemCoachNativeBridge.listPdfs();
      if (!mounted) return;

      if (documents.isEmpty) {
        setState(() => _status = '暂无已导入 PDF。请先通过 Agent 上传 PDF 文件。');
        return;
      }

      // 读取成功后，在显示弹窗前先清空状态，避免状态栏一直显示“正在读取”
      setState(() => _status = '');

      final selected = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        showDragHandle: true,
        builder: (context) => _PdfDocumentSheet(documents: documents),
      );

      if (!mounted) return;

      if (selected == null) {
        setState(() => _status = ''); // 用户取消了，清空状态
        return;
      }

      final id = selected['id']?.toString() ?? '';
      final name = selected['file_name']?.toString() ?? 'PDF';
      final pageCount = selected['page_count']?.toString() ?? '?';
      final marker = '请基于 PDF「$name」（document_id: $id，$pageCount 页）回答：';
      setState(() {
        _controller.text = _controller.text.trim().isEmpty
            ? marker
            : '${_controller.text.trim()}\n$marker';
        _controller.selection =
            TextSelection.collapsed(offset: _controller.text.length);
        _status = '已引用 PDF：$name';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '读取 PDF 列表失败：$error');
    }
  }

  void _ensureAssistantMessage() {
    if (_messages.isEmpty || _messages.last.role != _ChatRole.assistant) {
      _messages.add(const _ChatMessage(role: _ChatRole.assistant, content: ''));
    }
  }

  void _appendAssistantContent(String content) {
    _ensureAssistantMessage();
    if (content.isEmpty) return;
    final last = _messages.removeLast();
    // 使用增量合并而非累加（借鉴 OpenOmniBot 的 stream_text_merge.dart）
    final mergedContent = mergeAssistantContent(last.content, content);
    _messages.add(last.copyWith(
      content: mergedContent,
      reasoningContent: _currentThinkingContent(),
    ));
  }

  void _appendAssistantDelta(String content) {
    _ensureAssistantMessage();
    if (content.isEmpty) return;
    final last = _messages.removeLast();
    _messages.add(last.copyWith(
      content: last.content + content,
      reasoningContent: _currentThinkingContent(),
    ));
  }

  void _queueAssistantDelta(String content) {
    if (content.isEmpty) return;
    _assistantDeltaBuffer.write(content);
    _assistantDeltaFlushTimer ??=
        Timer(_assistantDeltaFlushInterval, _flushAssistantDelta);
  }

  void _flushAssistantDelta() {
    final content = _takePendingAssistantDelta();
    if (!mounted || content.isEmpty) return;
    setState(() {
      _status = 'Agent 正在回复...';
      _isThinking = false;
      _thinkingStage = 3;
      _thinkingEndTime ??= DateTime.now().millisecondsSinceEpoch;
      _appendAssistantDelta(content);
    });
    _scrollToBottom(animated: false);
  }

  void _discardPendingAssistantDelta() {
    _takePendingAssistantDelta();
  }

  String _takePendingAssistantDelta() {
    _assistantDeltaFlushTimer?.cancel();
    _assistantDeltaFlushTimer = null;
    final content = _assistantDeltaBuffer.toString();
    _assistantDeltaBuffer.clear();
    return content;
  }

  String? _currentThinkingContent() {
    return _nullableMessageText(
        _thinkingText == _thinkingPlaceholder ? null : _thinkingText);
  }

  String? _nullableMessageText(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  int? _nullableInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  DateTime? _parseMessageTimestamp(Object? value) {
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') return null;
    final millis = int.tryParse(text);
    if (millis != null) return DateTime.fromMillisecondsSinceEpoch(millis);
    return DateTime.tryParse(text);
  }

  void _attachThinkingToLastAssistantMessage() {
    final thinking = _currentThinkingContent();
    if (thinking == null) return;
    for (var i = _messages.length - 1; i >= 0; i--) {
      final message = _messages[i];
      if (message.role == _ChatRole.assistant) {
        _messages[i] = message.copyWith(reasoningContent: thinking);
        return;
      }
    }
  }

  void _attachCurrentToolCallsToLastAssistantMessage() {
    if (_currentTurnToolCalls.isEmpty) return;
    final currentIds = _currentTurnToolCalls.map((call) => call.id).toSet();
    for (var i = _messages.length - 1; i >= 0; i--) {
      final message = _messages[i];
      if (message.role == _ChatRole.assistant) {
        _messages[i] = message.copyWith(
            toolCalls: List<_ToolCallRecord>.from(_currentTurnToolCalls));
        _messages.removeWhere((message) =>
            message.role == _ChatRole.toolChip &&
            message.toolCallId != null &&
            currentIds.contains(message.toolCallId));
        return;
      }
    }
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final targetOffset = _scrollController.position.maxScrollExtent;
        if (!animated) {
          _scrollController.jumpTo(targetOffset);
          return;
        }
        _scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.55,
      maxChildSize: 1,
      snap: true,
      snapSizes: const [0.75, 0.92, 1],
      builder: (context, scrollController) {
        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: keyboardInset),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF1D1D26)
                  : Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                // ── 拖拽指示条 + 头部 ──
                _buildHeader(context),
                // ── 状态指示 ──
                if (_status.isNotEmpty && !_isTransientStatus())
                  _buildStatusBar(),
                // ── 斜杠命令面板 ──

                if (_showSlashCommandPanel) _buildSlashCommandPanel(),
                // ── 消息列表 ──
                Expanded(
                  child: _isLoadingConversation
                      ? _buildLoadingState()
                      : _messages.isEmpty
                          ? _buildEmptyState()
                          : Builder(
                              builder: (context) {
                                final showLiveThinking = _isThinking &&
                                    _thinkingText.trim().isNotEmpty;
                                final liveThinkingText =
                                    _thinkingText.trim().isNotEmpty
                                        ? _thinkingText
                                        : _thinkingPlaceholder;
                                return ListView.builder(
                                  controller: _scrollController,
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.onDrag,
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 8, 16, 24),
                                  itemCount: _messages.length +
                                      (showLiveThinking ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    // 如果有思考状态，在最后一个位置显示实时思考卡片（默认折叠）
                                    if (showLiveThinking &&
                                        index == _messages.length) {
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                            top: 8, bottom: 24),
                                        child: DeepThinkingCard(
                                          thinkingText: liveThinkingText,
                                          isLoading: _isThinking,
                                          stage: _thinkingStage,
                                          startTime: _thinkingStartTime,
                                          endTime: _thinkingEndTime,
                                          isCollapsible: true,
                                          autoCollapseOnComplete: true,
                                        ),
                                      );
                                    }

                                    final message = _messages[index];
                                    if (message.role == _ChatRole.tool) {
                                      return const SizedBox.shrink();
                                    }
                                    if (message.role == _ChatRole.skillChip) {
                                      return ToolCallChip(
                                        toolName: 'skill:${message.content}',
                                        arguments:
                                            _formatSkillArguments(message),
                                        result: message.skillTriggerReason,
                                      );
                                    }
                                    if (message.role == _ChatRole.toolChip) {
                                      return ToolCallChip(
                                        toolName: message.content,
                                        arguments: message.toolArguments,
                                        result: message.toolResult,
                                        error: message.toolError,
                                        duration: message.toolDurationMs != null
                                            ? Duration(
                                                milliseconds:
                                                    message.toolDurationMs!)
                                            : null,
                                        isRunning:
                                            message.toolDurationMs == null &&
                                                message.toolResult == null &&
                                                message.toolError == null,
                                      );
                                    }
                                    return _buildMessageItem(message);
                                  },
                                );
                              },
                            ),
                ),
                // ── 底部输入栏 ──
                _buildInputBar(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: '历史会话',
            onPressed: _running ? null : _showConversationHistorySheet,
            icon: const Icon(Icons.history_rounded),
            style: IconButton.styleFrom(
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.grey.withValues(alpha: 0.1),
              foregroundColor: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          Expanded(
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.black.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
            style: IconButton.styleFrom(
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.grey.withValues(alpha: 0.1),
              foregroundColor: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showConversationHistorySheet() async {
    setState(() => _status = '正在读取历史会话...');
    try {
      final conversations = await MemCoachNativeBridge.getConversations();
      if (!mounted) return;
      setState(() => _status = '');
      final selectedId = await showModalBottomSheet<int>(
        context: context,
        showDragHandle: true,
        builder: (context) => _ConversationHistorySheet(
          conversations: conversations,
          currentConversationId: _conversationId,
          formatTimestamp: _formatHistoryTimestamp,
        ),
      );
      if (selectedId == null || !mounted || selectedId == _conversationId)
        return;
      await _loadConversation(selectedId);
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '读取历史会话失败：$error');
    }
  }

  String _formatHistoryTimestamp(Object? raw) {
    if (raw == null) return '';
    final value = raw.toString();
    if (value.isEmpty || value == 'null') return '';
    DateTime? time;
    final millis = int.tryParse(value);
    if (millis != null) {
      time = DateTime.fromMillisecondsSinceEpoch(millis);
    } else {
      time = DateTime.tryParse(value);
    }
    if (time == null) return value;
    final local = time.toLocal();
    final now = DateTime.now();
    final isToday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final minute = local.minute.toString().padLeft(2, '0');
    if (isToday) return '今天 ${local.hour}:$minute';
    return '${local.month}/${local.day} ${local.hour}:$minute';
  }

  Widget _buildMessageItem(_ChatMessage message) {
    if (message.role == _ChatRole.assistant && message.toolCalls.isNotEmpty) {
      final children = <Widget>[
        for (final call in message.toolCalls)
          ToolCallChip(
            toolName: call.name,
            arguments: call.arguments,
            result: _toolResultForCall(call.id),
          ),
        if (message.content.trim().isNotEmpty) MarkdownBubble(message: message),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    }

    return MarkdownBubble(message: message);
  }

  String? _toolResultForCall(String toolCallId) {
    if (toolCallId.trim().isEmpty) return null;
    for (var i = _messages.length - 1; i >= 0; i--) {
      final message = _messages[i];
      if (message.role == _ChatRole.tool && message.toolCallId == toolCallId) {
        return message.content;
      }
    }
    return null;
  }

  bool _isTransientStatus() {
    return _status.startsWith('Agent 正在思考') || _status.startsWith('Agent 正在回复');
  }

  Widget _buildStatusBar() {
    final isFailure = _status.startsWith('启动失败');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          if (_running) ...[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              _status,
              style: TextStyle(
                color: isFailure
                    ? Colors.red.shade700
                    : (Theme.of(context).brightness == Brightness.dark
                        ? Colors.white70
                        : Colors.black54),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (isFailure && _lastSentText != null && _lastSentText!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: TextButton(
                onPressed: _retryLastSend,
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  '重试',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatSkillArguments(_ChatMessage message) {
    final lines = <String>[
      if (message.skillId != null && message.skillId!.trim().isNotEmpty)
        '策略 ID：${message.skillId}',
      if (message.skillConfidence != null && message.skillConfidence! > 0)
        '置信度：${(message.skillConfidence! * 100).round()}%',
    ];
    return lines.join('\n');
  }

  Widget _buildSlashCommandPanel() {
    return SlashCommandPanel(
      inputText: _controller.text,
      visible: _showSlashCommandPanel,
      onCommandSelected: _handleSlashCommand,
    );
  }

  Future<void> _showQuickCommandSheet() async {
    final command = await showModalBottomSheet<SlashCommand>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          itemBuilder: (context, index) {
            final command = kSlashCommands[index];
            return ListTile(
              leading: Icon(command.icon, color: const Color(0xFF5B5FEF)),
              title: Text('/${command.name}'),
              subtitle: Text(command.description),
              onTap: () => Navigator.of(context).pop(command),
            );
          },
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemCount: kSlashCommands.length,
        ),
      ),
    );
    if (command == null || !mounted) return;
    _handleSlashCommand(command);
  }

  void _handleSlashCommand(SlashCommand command) {
    setState(() {
      _showSlashCommandPanel = false;
      _controller.clear();
    });

    // 执行命令

    switch (command.type) {
      case SlashCommandType.compact:
        _executeCompactCommand();
        break;
      case SlashCommandType.effort:
        _executeEffortCommand();
        break;
      case SlashCommandType.help:
        _executeHelpCommand();
        break;
      case SlashCommandType.clear:
        _executeClearCommand();
        break;
      case SlashCommandType.export:
        _executeExportCommand();
        break;
    }
  }

  Future<void> _executeCompactCommand() async {
    setState(() {
      _messages.add(const _ChatMessage(
        role: _ChatRole.system,
        content: '正在压缩上下文...',
      ));
      _status = '正在压缩上下文...';
    });

    try {
      final result = await MemCoachNativeBridge.compactContext(
        history: _messagesForNativeHistory(),
      );
      if (!mounted) return;
      final before = result['message_count_before'] ?? 0;
      final after = result['message_count_after'] ?? 0;
      final compacted = result['compacted'] == true;
      setState(() {
        _status = '';
        _messages.add(_ChatMessage(
          role: _ChatRole.system,
          content: compacted
              ? '上下文压缩完成：$before 条消息压缩为 $after 条摘要上下文。'
              : '当前对话内容较少，暂不需要压缩。',
        ));
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = '';
        _messages.add(_ChatMessage(
          role: _ChatRole.system,
          content: '上下文压缩失败：$error',
        ));
      });
    }
  }

  void _executeEffortCommand() {
    // 显示思考强度选择对话框
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置思考强度'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildEffortOption('低', '快速回答，较少思考', 'low'),
            _buildEffortOption('中', '平衡思考深度和速度', 'medium'),
            _buildEffortOption('高', '深度思考，更详细的分析', 'high'),
          ],
        ),
      ),
    );
  }

  Widget _buildEffortOption(
      String level, String description, String nativeLevel) {
    return ListTile(
      title: Text(level),
      subtitle: Text(description),
      onTap: () async {
        Navigator.of(context).pop();
        try {
          final result =
              await MemCoachNativeBridge.setReasoningEffort(nativeLevel);
          if (!mounted) return;
          final label = result['label']?.toString() ?? level;
          setState(() {
            _reasoningEffort = label;
            _messages.add(_ChatMessage(
              role: _ChatRole.system,
              content: '已设置思考强度为：$label',
            ));
          });
        } catch (error) {
          if (!mounted) return;
          setState(() {
            _messages.add(_ChatMessage(
              role: _ChatRole.system,
              content: '设置思考强度失败：$error',
            ));
          });
        }
      },
    );
  }

  List<Map<String, dynamic>> _messagesForNativeHistory() {
    final toolMessagesById = <String, _ChatMessage>{};
    for (final message in _messages) {
      final id = message.toolCallId;
      if (message.role == _ChatRole.tool && id != null && id.isNotEmpty) {
        toolMessagesById[id] = message;
      }
    }

    final history = <Map<String, dynamic>>[];
    for (final message in _messages) {
      if (message.role == _ChatRole.system ||
          message.role == _ChatRole.tool ||
          message.role == _ChatRole.toolChip ||
          message.role == _ChatRole.skillChip) {
        continue;
      }
      if (message.content.trim().isEmpty &&
          !(message.role == _ChatRole.assistant &&
              message.toolCalls.isNotEmpty)) {
        continue;
      }

      history.add(_messageToNativeHistory(message));
      if (message.role == _ChatRole.assistant && message.toolCalls.isNotEmpty) {
        for (final call in message.toolCalls) {
          final toolMessage = toolMessagesById[call.id];
          if (toolMessage == null) continue;
          history.add(_messageToNativeHistory(toolMessage));
        }
      }
    }
    return history;
  }

  Map<String, dynamic> _messageToNativeHistory(_ChatMessage message) {
    final role = switch (message.role) {
      _ChatRole.user => 'user',
      _ChatRole.assistant => 'assistant',
      _ChatRole.tool => 'tool',
      _ChatRole.system => 'system',
      _ChatRole.toolChip => 'system',
      _ChatRole.skillChip => 'system',
    };
    return <String, dynamic>{
      'role': role,
      'content': message.content,
      if (message.reasoningContent != null)
        'reasoning_content': message.reasoningContent,
      if (message.toolCallId != null) 'tool_call_id': message.toolCallId,
      if (message.toolCalls.isNotEmpty)
        'tool_calls': message.toolCalls.map((call) => call.toJson()).toList(),
    };
  }

  String _effortLabel(String effort) {
    switch (effort.toLowerCase()) {
      case 'low':
        return '低';
      case 'high':
        return '高';
      default:
        return '中';
    }
  }

  void _executeHelpCommand() {
    // 显示帮助信息
    _messages.add(const _ChatMessage(
      role: _ChatRole.system,
      content: '''可用命令：
/compact - 压缩上下文，优化对话质量
/effort - 设置思考强度（低/中/高）
/help - 查看此帮助信息
/clear - 清空当前对话历史
/export - 导出对话记录''',
    ));
    setState(() {});
  }

  void _executeClearCommand() {
    setState(() {
      _messages
        ..clear()
        ..add(const _ChatMessage(
          role: _ChatRole.system,
          content: '已清空当前屏幕上下文，数据库中的历史会话不会被删除。',
        ));
      _thinkingText = '';
      _isThinking = false;
    });
  }

  Future<void> _executeExportCommand() async {
    final buffer = StringBuffer();
    for (final msg in _messages.where((msg) =>
        msg.role != _ChatRole.tool &&
        msg.role != _ChatRole.toolChip &&
        msg.role != _ChatRole.skillChip)) {
      final role = msg.role == _ChatRole.user
          ? '用户'
          : msg.role == _ChatRole.assistant
              ? '助手'
              : '系统';
      buffer.writeln('[$role]: ${msg.content}');
      if (msg.toolCalls.isNotEmpty) {
        final toolNames = msg.toolCalls
            .map((call) => call.name.trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .join('、');
        final toolSummary =
            toolNames.isEmpty ? '${msg.toolCalls.length} 次' : toolNames;
        buffer.writeln('[工具调用]: $toolSummary');
      }
      buffer.writeln();
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    setState(() {
      _messages.add(const _ChatMessage(
        role: _ChatRole.system,
        content: '对话记录已导出到剪贴板。',
      ));
    });
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AiSparkleLogo(
            size: 48,
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 16),
          Text(
            'MEM 搭子',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '问我：今天该怎么学？',
            style: TextStyle(
              fontSize: 15,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            '加载会话中...',
            style: TextStyle(
              fontSize: 15,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        16,
        8,
        8,
        12,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1D1D26) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 关联上下文提示胶囊 ──
          if (_activePageContext != null && _activePageContext!.isNotEmpty)
            _buildContextChip(),
          // ── 第一行：功能按钮 ──
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: '快捷命令',
                  onPressed: _running ? null : _showQuickCommandSheet,
                  icon: const Icon(Icons.bolt_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.grey.withValues(alpha: 0.1),
                    foregroundColor: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '引用 PDF',
                  onPressed: _running ? null : _showPdfPicker,
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.grey.withValues(alpha: 0.1),
                    foregroundColor: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '语音输入',
                  onPressed: _running ? null : _onVoiceInput,
                  icon: const Icon(Icons.mic_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.grey.withValues(alpha: 0.1),
                    foregroundColor: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          // ── 第二行：输入框 + 发送按钮 ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF252530)
                        : const Color(0xFFF4F6FA),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TextField(
                    controller: _controller,
                    enabled: !_running,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: '输入消息...',
                      hintStyle: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.4),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    onChanged: _handleInputChanged,
                    onSubmitted: (_) => _send(),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton.filled(
                onPressed: _running ? _cancel : _send,
                icon: Icon(_running ? Icons.stop_rounded : Icons.send_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContextChip() {
    if (_activePageContext == null || _activePageContext!.isEmpty) {
      return const SizedBox.shrink();
    }

    final type = _activePageContext!['type']?.toString();

    String label = '关联上下文';
    IconData icon = Icons.link_rounded;
    Color color = Theme.of(context).colorScheme.primary;

    if (type == 'vocabulary') {
      final word = _activePageContext!['word']?.toString() ?? '';
      label = '关联生词：$word';
      icon = Icons.book_rounded;
      color = const Color(0xFF5B5FEF);
    } else if (type == 'question') {
      final stem = _activePageContext!['stem']?.toString() ?? '';
      final displayStem =
          stem.length > 22 ? '${stem.substring(0, 22)}...' : stem;
      label = '关联真题：$displayStem';
      icon = Icons.quiz_rounded;
      color = const Color(0xFF20B486);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: color.withValues(alpha: 0.25),
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      if (_activePageContext != null) {
                        _manuallyClearedContextId = (_activePageContext!['question_id'] ??
                                _activePageContext!['word_id'])
                            ?.toString();
                      }
                      _activePageContext = null;
                    });
                  },
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: color.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

/// PDF 文档选择弹窗
class _PdfDocumentSheet extends StatelessWidget {
  const _PdfDocumentSheet({required this.documents});

  final List<Map<String, dynamic>> documents;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        itemBuilder: (context, index) {
          final document = documents[index];
          final name = document['file_name']?.toString() ?? '未命名 PDF';
          final pageCount = document['page_count']?.toString() ?? '?';
          final subject = document['subject']?.toString();
          final year = document['year']?.toString();
          final meta = [
            '$pageCount 页',
            if (subject != null && subject.isNotEmpty && subject != 'null')
              subject,
            if (year != null && year.isNotEmpty && year != 'null') year,
          ].join(' · ');
          return ListTile(
            leading:
                const CircleAvatar(child: Icon(Icons.picture_as_pdf_rounded)),
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(meta),
            onTap: () => Navigator.of(context).pop(document),
          );
        },
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemCount: documents.length,
      ),
    );
  }
}

class _ConversationHistorySheet extends StatelessWidget {
  const _ConversationHistorySheet({
    required this.conversations,
    required this.currentConversationId,
    required this.formatTimestamp,
  });

  final List<Map<String, dynamic>> conversations;
  final int? currentConversationId;
  final String Function(Object? raw) formatTimestamp;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      child: conversations.isEmpty
          ? Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history_toggle_off_rounded,
                      size: 42,
                      color: isDark
                          ? Colors.white30
                          : Colors.black.withValues(alpha: 0.25)),
                  const SizedBox(height: 12),
                  const Text('暂无历史会话',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('开始一次对话后，会在这里显示历史记录。',
                      style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black54)),
                ],
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              itemBuilder: (context, index) {
                final conversation = conversations[index];
                final id = int.tryParse(conversation['id']?.toString() ?? '');
                final title = conversation['title']?.toString().trim();
                final summary = conversation['summary']?.toString().trim();
                final messageCount =
                    conversation['message_count']?.toString() ?? '0';
                final updatedAt = formatTimestamp(conversation['updated_at']);
                final isCurrent = id != null && id == currentConversationId;
                final subtitle = [
                  if (summary != null &&
                      summary.isNotEmpty &&
                      summary != 'null')
                    summary,
                  '$messageCount 条消息',
                  if (updatedAt.isNotEmpty) updatedAt,
                ].join(' · ');

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isCurrent
                        ? const Color(0xFF5B5FEF)
                        : (isDark
                            ? const Color(0xFF2C2C35)
                            : const Color(0xFFF4F6FA)),
                    child: Icon(
                      isCurrent
                          ? Icons.chat_bubble_rounded
                          : Icons.chat_bubble_outline_rounded,
                      color: isCurrent ? Colors.white : const Color(0xFF5B5FEF),
                    ),
                  ),
                  title: Text(
                    title == null || title.isEmpty || title == 'null'
                        ? '未命名会话'
                        : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight:
                            isCurrent ? FontWeight.w800 : FontWeight.w600),
                  ),
                  subtitle: Text(subtitle,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: isCurrent
                      ? const Text('当前',
                          style: TextStyle(
                              color: Color(0xFF5B5FEF),
                              fontWeight: FontWeight.w700))
                      : const Icon(Icons.chevron_right_rounded),
                  onTap:
                      id == null ? null : () => Navigator.of(context).pop(id),
                );
              },
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemCount: conversations.length,
            ),
    );
  }
}

/// 聊天消息角色
enum _ChatRole { user, assistant, tool, system, toolChip, skillChip }

class _ActiveSkill {
  const _ActiveSkill({
    required this.id,
    required this.name,
    required this.confidence,
    required this.triggerReason,
  });

  final String id;
  final String name;
  final double confidence;
  final String triggerReason;

  static _ActiveSkill? fromEvent(AgentNativeEvent event) {
    final id = event.skillId?.trim();
    final name = event.skillName?.trim();
    if ((id == null || id.isEmpty) && (name == null || name.isEmpty)) {
      return null;
    }
    return _ActiveSkill(
      id: id == null || id.isEmpty ? name! : id,
      name: name == null || name.isEmpty ? id! : name,
      confidence: event.confidence ?? 0,
      triggerReason: event.triggerReason?.trim() ?? '',
    );
  }
}

class _ToolCallRecord {
  const _ToolCallRecord({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final String arguments;

  factory _ToolCallRecord.fromJson(Map<String, dynamic> json) {
    return _ToolCallRecord(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      arguments: json['arguments']?.toString() ?? '{}',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'arguments': arguments,
      };
}

/// 聊天消息数据
class _ChatMessage {
  const _ChatMessage({
    required this.role,
    required this.content,
    this.reasoningContent,
    this.timestamp,
    this.toolCallId,
    this.toolArguments,
    this.toolResult,
    this.toolError,
    this.toolDurationMs,
    this.skillId,
    this.skillConfidence,
    this.skillTriggerReason,
    this.toolCalls = const [],
  });

  final _ChatRole role;
  final String content;
  final String? reasoningContent;
  final DateTime? timestamp;
  final String? toolCallId;
  final String? toolArguments;
  final String? toolResult;
  final String? toolError;
  final int? toolDurationMs;
  final String? skillId;
  final double? skillConfidence;
  final String? skillTriggerReason;
  final List<_ToolCallRecord> toolCalls;

  _ChatMessage copyWith({
    String? content,
    String? reasoningContent,
    DateTime? timestamp,
    String? toolCallId,
    String? toolArguments,
    String? toolResult,
    String? toolError,
    int? toolDurationMs,
    String? skillId,
    double? skillConfidence,
    String? skillTriggerReason,
    List<_ToolCallRecord>? toolCalls,
  }) {
    return _ChatMessage(
      role: role,
      content: content ?? this.content,
      reasoningContent: reasoningContent ?? this.reasoningContent,
      timestamp: timestamp ?? this.timestamp,
      toolCallId: toolCallId ?? this.toolCallId,
      toolArguments: toolArguments ?? this.toolArguments,
      toolResult: toolResult ?? this.toolResult,
      toolError: toolError ?? this.toolError,
      toolDurationMs: toolDurationMs ?? this.toolDurationMs,
      skillId: skillId ?? this.skillId,
      skillConfidence: skillConfidence ?? this.skillConfidence,
      skillTriggerReason: skillTriggerReason ?? this.skillTriggerReason,
      toolCalls: toolCalls ?? this.toolCalls,
    );
  }
}
