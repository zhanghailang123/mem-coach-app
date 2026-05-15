import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/native/mem_coach_native_bridge.dart';
import 'markdown_bubble.dart';
import 'tool_activity_bar.dart';
import 'deep_thinking_card.dart';
import 'slash_command_panel.dart';
import '../utils/deep_thinking_parser.dart';
import '../utils/agent_stream_reducer.dart';

/// 全屏沉浸式聊天 Sheet
/// 借鉴 OpenOmniBot ChatBotSheet 的 DraggableScrollableSheet 设计
class ChatSheet extends StatefulWidget {
  const ChatSheet({
    super.key,
    this.conversationId,
    this.initialText,
    this.initialStatus,
    this.initialPdfJobId,
  });


  /// 会话 ID，如果为 null 则创建新会话
  final int? conversationId;

  /// 打开聊天框时预填到输入框的文本
  final String? initialText;

  /// 打开聊天框时展示的状态提示
  final String? initialStatus;

  /// 上传 PDF 后启动的后台解析任务 ID
  final String? initialPdfJobId;

  /// 打开全屏聊天 Sheet

  static Future<void> show(
    BuildContext context, {
    int? conversationId,
    String? initialText,
    String? initialStatus,
    String? initialPdfJobId,
  }) {

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChatSheet(
        conversationId: conversationId,
        initialText: initialText,
        initialStatus: initialStatus,
        initialPdfJobId: initialPdfJobId,
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
  Timer? _pdfStatusTimer;
  Timer? _pdfDismissTimer;
  String _status = '';
  bool _running = false;

  // Agent 流式事件状态管理（借鉴 OpenOmniBot Reducer 模式）
  final AgentStreamReducer _agentStreamReducer = const AgentStreamReducer();
  AgentStreamState _agentStreamState = const AgentStreamState();

  
  // 会话状态
  int? _conversationId;
  bool _isLoadingConversation = false;
  
  // 工具活动状态
  final List<ToolActivity> _toolActivities = [];
  bool _toolBarExpanded = false;
  
  // 深度思考状态
  String _thinkingText = '';
  bool _isThinking = false;
  int _thinkingStage = 1;
  int? _thinkingStartTime;
  int? _thinkingEndTime;
  String _reasoningEffort = '中';
  static const String _thinkingPlaceholder = '正在理解你的问题...';
  
  // 学习状态
  String _currentState = '';
  String _currentStateName = '';

  // PDF 解析状态
  String? _pdfJobId;
  String _pdfParseStatus = '';
  int _pdfParseProgress = 0;
  int _pdfParsedQuestions = 0;
  int _pdfInsertedQuestions = 0;
  int _pdfDuplicateQuestions = 0;
  List<String> _pdfParseErrors = const [];
  
  // 斜杠命令状态

  bool _showSlashCommandPanel = false;
  
  // 重试状态
  String? _lastSentText;

  // 当前轮次工具调用历史，用于下一轮传回 Native 保留 ReAct 上下文
  final List<_ToolCallRecord> _currentTurnToolCalls = [];
  
  // 自动补全状态

  bool _isAutoCompleting = false;


  @override
  void initState() {
    super.initState();
    final initialText = widget.initialText?.trim();
    if (initialText != null && initialText.isNotEmpty) {
      _controller.text = initialText;
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    }
    final initialStatus = widget.initialStatus?.trim();
    if (initialStatus != null && initialStatus.isNotEmpty) {
      _status = initialStatus;
    }
    final initialPdfJobId = widget.initialPdfJobId?.trim();
    if (initialPdfJobId != null && initialPdfJobId.isNotEmpty) {
      _pdfJobId = initialPdfJobId;
      _pdfParseStatus = 'pending';
      _startPdfStatusPolling(initialPdfJobId);
    }
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
    
    // 初始化会话
    _initConversation();

    // 自动恢复 PDF 解析进度追踪
    if (widget.initialPdfJobId == null) {
      _resumeActivePdfJobs();
    }
  }

  /// 恢复正在运行的 PDF 解析任务
  Future<void> _resumeActivePdfJobs() async {
    try {
      final activeJobs = await MemCoachNativeBridge.getActivePdfJobs();
      if (!mounted) return;
      if (activeJobs.isNotEmpty) {
        final latestJobId = activeJobs.last;
        setState(() {
          _pdfJobId = latestJobId;
          _pdfParseStatus = 'processing';
        });
        _startPdfStatusPolling(latestJobId);
      }
    } catch (e) {
      debugPrint('恢复 PDF 任务进度失败: $e');
    }
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
          final timestampStr = msg['timestamp'] as String?;
          DateTime? timestamp;
          if (timestampStr != null) {
            try {
              timestamp = DateTime.parse(timestampStr);
            } catch (_) {
              timestamp = null;
            }
          }
          final toolCallsRaw = msg['tool_calls'];
          final toolCalls = toolCallsRaw is List
              ? toolCallsRaw.whereType<Map>().map((item) => _ToolCallRecord.fromJson(Map<String, dynamic>.from(item))).toList()
              : <_ToolCallRecord>[];
          _messages.add(_ChatMessage(
            role: switch (role) {
              'assistant' => _ChatRole.assistant,
              'tool' => _ChatRole.tool,
              'system' => _ChatRole.system,
              _ => _ChatRole.user,
            },
            content: content,
            reasoningContent: _nullableMessageText(
              msg['reasoning_content'] ?? msg['thinking_content'],
            ),
            toolCallId: msg['tool_call_id']?.toString(),
            toolCalls: toolCalls,
            timestamp: timestamp,
          ));

        }
        _isLoadingConversation = false;
        _status = '';
      });
      
      // 滚动到底部
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingConversation = false;
        _status = '加载会话失败：$error';
      });
    }
  }

  void _startPdfStatusPolling(String jobId) {
    _pdfStatusTimer?.cancel();
    _pollPdfStatus(jobId);
    _pdfStatusTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollPdfStatus(jobId));
  }

  Future<void> _pollPdfStatus(String jobId) async {
    try {
      final status = await MemCoachNativeBridge.getPdfParseStatus(jobId);
      if (!mounted || _pdfJobId != jobId) return;
      final rawErrors = status['errors'];
      setState(() {
        _pdfParseStatus = status['status']?.toString() ?? '';
        _pdfParseProgress = int.tryParse(status['progress']?.toString() ?? '') ?? 0;
        _pdfParsedQuestions = int.tryParse(status['parsed_questions']?.toString() ?? '') ?? 0;
        _pdfInsertedQuestions = int.tryParse(status['inserted_questions']?.toString() ?? '') ?? 0;
        _pdfDuplicateQuestions = int.tryParse(status['duplicate_questions']?.toString() ?? '') ?? 0;
        _pdfParseErrors = rawErrors is List ? rawErrors.map((e) => e.toString()).toList() : const [];
      });
      if (_pdfParseStatus == 'done') {
        _pdfStatusTimer?.cancel();
        _pdfStatusTimer = null;
        _schedulePdfStatusDismiss();
      } else if (_pdfParseStatus == 'error' || _pdfParseStatus == 'not_found') {
        _pdfStatusTimer?.cancel();
        _pdfStatusTimer = null;
      }
    } catch (error) {
      if (!mounted || _pdfJobId != jobId) return;
      setState(() {
        _pdfParseStatus = 'error';
        _pdfParseErrors = ['解析状态查询失败：$error'];
      });
      _pdfStatusTimer?.cancel();
      _pdfStatusTimer = null;
    }
  }

  void _schedulePdfStatusDismiss() {
    _pdfDismissTimer?.cancel();
    _pdfDismissTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      setState(_clearPdfStatusCard);
    });
  }

  void _clearPdfStatusCard() {
    _pdfStatusTimer?.cancel();
    _pdfStatusTimer = null;
    _pdfDismissTimer?.cancel();
    _pdfDismissTimer = null;
    _pdfJobId = null;
    _pdfParseStatus = '';
    _pdfParseProgress = 0;
    _pdfParsedQuestions = 0;
    _pdfInsertedQuestions = 0;
    _pdfDuplicateQuestions = 0;
    _pdfParseErrors = const [];
  }

  void _handleAgentEvent(AgentNativeEvent event) {
    if (!mounted) return;

    // 使用 Reducer 模式检查事件是否需要处理
    final seq = event.raw['seq'] as int?;
    final reduceResult = _agentStreamReducer.reduce(_agentStreamState, event.type, seq);
    if (!reduceResult.accepted) {
      return; // 忽略重复事件
    }
    _agentStreamState = reduceResult.nextState;

    setState(() {
      switch (event.type) {
        case 'state_changed':
          _currentState = event.state ?? '';
          _currentStateName = event.stateName ?? '';
          _status = '模式：$_currentStateName';
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
          _thinkingText += event.content ?? '';
          _thinkingStage = 2;
          final thinkingResult = DeepThinkingParser.extractDeepThinking(_thinkingText);
          if (thinkingResult.hasAnyContent) {
            _thinkingText = thinkingResult.toDisplayText();
          }
          break;
        case 'tool_call_start':
          _status = '正在调用工具：${event.toolName ?? 'unknown'}';
          _currentTurnToolCalls.add(_ToolCallRecord(
            id: event.toolCallId ?? 'tool_${DateTime.now().millisecondsSinceEpoch}_${_currentTurnToolCalls.length}',
            name: event.toolName ?? 'unknown',
            arguments: event.arguments ?? '{}',
          ));
          _toolActivities.add(ToolActivity(
            toolName: event.toolName ?? 'unknown',
            status: ToolActivityStatus.running,
            summary: event.arguments?.toString(),
            startTime: DateTime.now(),
          ));
          break;
        case 'tool_call_complete':
          _status = '工具调用完成：${event.toolName ?? 'unknown'}';
          if (event.toolCallId != null) {
            _messages.add(_ChatMessage(
              role: _ChatRole.tool,
              content: event.result ?? '',
              toolCallId: event.toolCallId,
              timestamp: DateTime.now(),
            ));
          }
          _updateToolActivity(
            event.toolName ?? 'unknown',
            ToolActivityStatus.success,
            result: event.result,
          );
          break;
        case 'tool_call_error':
          _status = '工具调用失败：${event.toolName ?? 'unknown'}';
          _updateToolActivity(
            event.toolName ?? 'unknown',
            ToolActivityStatus.error,
            result: event.error,
          );
          break;
        case 'chat_message':
          _status = 'Agent 正在回复...';
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
          _thinkingStage = 4;
          _thinkingEndTime = DateTime.now().millisecondsSinceEpoch;
          _attachThinkingToLastAssistantMessage();
          _saveAssistantMessageToDatabase();
          break;
        case 'error':
          _running = false;
          _status = event.error ?? '执行失败';
          _appendAssistantContent('\n${event.error ?? '执行失败'}');
          _isThinking = false;
          _thinkingStage = 4;
          _thinkingEndTime = DateTime.now().millisecondsSinceEpoch;
          _attachThinkingToLastAssistantMessage();
          _saveAssistantMessageToDatabase();
          for (var i = 0; i < _toolActivities.length; i++) {
            if (_toolActivities[i].status == ToolActivityStatus.running) {
              _toolActivities[i] = _toolActivities[i].copyWith(
                status: ToolActivityStatus.error,
                endTime: DateTime.now(),
              );
            }
          }
          break;
      }
    });
    _scrollToBottom();
  }
  
  void _updateToolActivity(
    String toolName,
    ToolActivityStatus status, {
    String? result,
  }) {
    for (var i = _toolActivities.length - 1; i >= 0; i--) {
      final activity = _toolActivities[i];
      if (activity.toolName == toolName && activity.status == ToolActivityStatus.running) {
        _toolActivities[i] = activity.copyWith(
          status: status,
          result: result,
          endTime: DateTime.now(),
        );
        return;
      }
    }
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
      for (final message in _messages.where((message) => message.role == _ChatRole.tool && message.toolCallId != null)) {
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
    } catch (error) {
      // 忽略数据库错误
      debugPrint('保存助手消息失败：$error');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pdfStatusTimer?.cancel();
    _pdfDismissTimer?.cancel();
    _controller.dispose();

    _scrollController.dispose();
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
      _toolActivities.clear();
      _currentTurnToolCalls.clear();
      _thinkingText = _thinkingPlaceholder;
      _isThinking = true;
      _thinkingStage = 1;
      _thinkingStartTime = sentAt.millisecondsSinceEpoch;
      _thinkingEndTime = null;
    });
    _scrollToBottom();

    final history = _messagesForNativeHistory();

    if (_conversationId != null) {
      unawaited(MemCoachNativeBridge.addChatMessage(
        conversationId: _conversationId!,
        role: 'user',
        content: text,
      ).catchError((Object error) {
        debugPrint('保存用户消息失败：$error');
        return <String, dynamic>{};
      }));
    }

    try {
      await MemCoachNativeBridge.startAgentTurn(
        message: text,
        history: history,
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

  /// 重试上一次发送
  Future<void> _retryLastSend() async {
    if (_lastSentText == null || _lastSentText!.isEmpty || _running) return;
    
    // 将文本放回输入框
    _controller.text = _lastSentText!;
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    
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
        _controller.text = _controller.text.trim().isEmpty ? marker : '${_controller.text.trim()}\n$marker';
        _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
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
    if (content.isEmpty) return;
    _ensureAssistantMessage();
    final last = _messages.removeLast();
    // 使用增量合并而非累加（借鉴 OpenOmniBot 的 stream_text_merge.dart）
    final mergedContent = mergeAssistantContent(last.content, content);
    _messages.add(last.copyWith(
      content: mergedContent,
      reasoningContent: _currentThinkingContent(),
    ));
  }

  String? _currentThinkingContent() {
    return _nullableMessageText(_thinkingText == _thinkingPlaceholder ? null : _thinkingText);
  }

  String? _nullableMessageText(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
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
    for (var i = _messages.length - 1; i >= 0; i--) {
      final message = _messages[i];
      if (message.role == _ChatRole.assistant) {
        _messages[i] = message.copyWith(toolCalls: List<_ToolCallRecord>.from(_currentTurnToolCalls));
        return;
      }
    }
  }

  void _scrollToBottom() {

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
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
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                // ── 拖拽指示条 + 头部 ──
                _buildHeader(context),
                // ── 状态指示 ──
                if (_status.isNotEmpty && !_isTransientStatus()) _buildStatusBar(),
                // ── 工具活动条 ──
                if (_toolActivities.isNotEmpty) _buildToolActivityBar(),
                // ── PDF 解析状态 ──
                if (_pdfJobId != null && _pdfParseStatus.isNotEmpty) _buildPdfParseStatusCard(),
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
                                final showLiveThinking = _isThinking || _thinkingText.trim().isNotEmpty;
                                final liveThinkingText = _thinkingText.trim().isNotEmpty
                                    ? _thinkingText
                                    : _thinkingPlaceholder;
                                return ListView.builder(
                                  controller: _scrollController,
                                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                                  itemCount: _messages.length + (showLiveThinking ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    // 如果有思考状态，在第一个位置显示实时思考卡片
                                    if (showLiveThinking && index == 0) {
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 12),
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
                                    // 调整消息索引
                                    final messageIndex = showLiveThinking ? index - 1 : index;
                                    final message = _messages[messageIndex];
                                    if (message.role == _ChatRole.tool) {
                                      return const SizedBox.shrink();
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
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: '历史会话',
            onPressed: _running ? null : _showConversationHistorySheet,
            icon: const Icon(Icons.history_rounded),
            style: IconButton.styleFrom(
              backgroundColor: Colors.grey.withOpacity(0.1),
            ),
          ),
          Expanded(
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.15),
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
              backgroundColor: Colors.grey.withOpacity(0.1),
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
      if (selectedId == null || !mounted || selectedId == _conversationId) return;
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
    final isToday = local.year == now.year && local.month == now.month && local.day == now.day;
    final minute = local.minute.toString().padLeft(2, '0');
    if (isToday) return '今天 ${local.hour}:$minute';
    return '${local.month}/${local.day} ${local.hour}:$minute';
  }

  Widget _buildMessageItem(_ChatMessage message) {
    final hasToolCalls = message.role == _ChatRole.assistant && message.toolCalls.isNotEmpty;
    final reasoningContent = _nullableMessageText(message.reasoningContent);
    if (!hasToolCalls && reasoningContent == null) {
      return MarkdownBubble(message: message);
    }

    final children = <Widget>[MarkdownBubble(message: message)];

    if (reasoningContent != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
          child: DeepThinkingCard(
            thinkingText: reasoningContent,
            isLoading: false,
            stage: 4,
            isCollapsible: true,
            autoCollapseOnComplete: true,
            maxHeight: 260,
          ),
        ),
      );
    }

    if (hasToolCalls) {
      final names = message.toolCalls
          .map((call) => call.name.trim())
          .where((name) => name.isNotEmpty)
          .toSet()
          .join('、');
      final summary = names.isEmpty
          ? '工具调用 ${message.toolCalls.length} 次'
          : '已使用工具：$names';
      children.add(
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F6FA),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.black.withOpacity(0.06)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.build_circle_outlined, size: 14, color: Color(0xFF5B5FEF)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
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
                color: isFailure ? Colors.red.shade700 : Colors.black54,
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
  
  Widget _buildToolActivityBar() {
    return ToolActivityBar(
      toolActivities: _toolActivities,
      expanded: _toolBarExpanded,
      onExpandedChanged: (expanded) {
        setState(() {
          _toolBarExpanded = expanded;
        });
      },
    );
  }

  Widget _buildPdfParseStatusCard() {
    final isDone = _pdfParseStatus == 'done';
    final isError = _pdfParseStatus == 'error' || _pdfParseStatus == 'not_found';
    final label = _pdfStatusLabel(_pdfParseStatus);
    final progress = (_pdfParseProgress.clamp(0, 100)) / 100.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? Colors.red.shade50 : const Color(0xFFF7F8FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isError ? Colors.red.shade100 : const Color(0xFFE1E5FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isDone ? Icons.check_circle_rounded : isError ? Icons.error_rounded : Icons.picture_as_pdf_rounded,
                size: 18,
                color: isDone ? const Color(0xFF20B486) : isError ? Colors.red.shade600 : const Color(0xFF5B5FEF),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'PDF 解析：$label',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${_pdfParseProgress.clamp(0, 100)}%',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              if (isDone || isError) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => setState(_clearPdfStatusCard),
                  icon: const Icon(Icons.close_rounded, size: 16),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                ),
              ],

            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: isError ? null : progress,
              minHeight: 6,
              backgroundColor: Colors.black.withOpacity(0.06),
              color: isDone ? const Color(0xFF20B486) : const Color(0xFF5B5FEF),
            ),
          ),
          if (_pdfParsedQuestions > 0 || _pdfInsertedQuestions > 0 || _pdfDuplicateQuestions > 0) ...[
            const SizedBox(height: 8),
            Text(
              '已识别 $_pdfParsedQuestions 题，入库 $_pdfInsertedQuestions 题，重复 $_pdfDuplicateQuestions 题',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
          if (_pdfParseErrors.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _pdfParseErrors.first,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
          ],
        ],
      ),
    );
  }

  String _pdfStatusLabel(String status) {
    switch (status) {
      case 'pending':
        return '等待开始';
      case 'extracting':
        return '提取文本';
      case 'ocr':
        return 'OCR 识别';
      case 'structuring':
        return 'AI 结构化题目';
      case 'dedup':
        return '去重检测';
      case 'inserting':
        return '写入题库';
      case 'done':
        return '完成';
      case 'not_found':
        return '任务不存在';
      case 'error':
        return '失败';
      default:
        return status.isEmpty ? '处理中' : status;
    }
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
  
  Widget _buildEffortOption(String level, String description, String nativeLevel) {
    return ListTile(
      title: Text(level),
      subtitle: Text(description),
      onTap: () async {
        Navigator.of(context).pop();
        try {
          final result = await MemCoachNativeBridge.setReasoningEffort(nativeLevel);
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
    return _messages
        .where((message) => message.role != _ChatRole.system && message.content.trim().isNotEmpty)
        .map((message) {
          final role = switch (message.role) {
            _ChatRole.user => 'user',
            _ChatRole.assistant => 'assistant',
            _ChatRole.tool => 'tool',
            _ChatRole.system => 'system',
          };
          return <String, dynamic>{
            'role': role,
            'content': message.content,
            if (message.reasoningContent != null) 'reasoning_content': message.reasoningContent,
            if (message.toolCallId != null) 'tool_call_id': message.toolCallId,
            if (message.toolCalls.isNotEmpty)
              'tool_calls': message.toolCalls.map((call) => call.toJson()).toList(),
          };
        })
        .toList();
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
      _toolActivities.clear();
      _thinkingText = '';
      _isThinking = false;
    });
  }
  
  Future<void> _executeExportCommand() async {
    final buffer = StringBuffer();
    for (final msg in _messages.where((msg) => msg.role != _ChatRole.tool)) {
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
        final toolSummary = toolNames.isEmpty ? '${msg.toolCalls.length} 次' : toolNames;
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
          Icon(
            Icons.auto_awesome_rounded,
            size: 48,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'MEM Coach',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '问我：今天该怎么学？',
            style: TextStyle(
              fontSize: 15,
              color: Colors.black54,
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
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        16,
        8,
        8,
        12,
      ),

      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.black.withOpacity(0.06)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 第一行：功能按钮 ──
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: '引用 PDF',
                  onPressed: _running ? null : _showPdfPicker,
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.withOpacity(0.1),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '快捷命令',
                  onPressed: _running ? null : _showQuickCommandSheet,
                  icon: const Icon(Icons.bolt_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.withOpacity(0.1),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '语音输入',
                  onPressed: _running ? null : _onVoiceInput,
                  icon: const Icon(Icons.mic_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.withOpacity(0.1),
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
                    color: const Color(0xFFF4F6FA),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TextField(
                    controller: _controller,
                    enabled: !_running,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: '输入消息...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
            if (subject != null && subject.isNotEmpty && subject != 'null') subject,
            if (year != null && year.isNotEmpty && year != 'null') year,
          ].join(' · ');
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.picture_as_pdf_rounded)),
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
    return SafeArea(
      child: conversations.isEmpty
          ? Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history_toggle_off_rounded, size: 42, color: Colors.black.withOpacity(0.25)),
                  const SizedBox(height: 12),
                  const Text('暂无历史会话', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text('开始一次对话后，会在这里显示历史记录。', style: TextStyle(color: Colors.black54)),
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
                final messageCount = conversation['message_count']?.toString() ?? '0';
                final updatedAt = formatTimestamp(conversation['updated_at']);
                final isCurrent = id != null && id == currentConversationId;
                final subtitle = [
                  if (summary != null && summary.isNotEmpty && summary != 'null') summary,
                  '$messageCount 条消息',
                  if (updatedAt.isNotEmpty) updatedAt,
                ].join(' · ');

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isCurrent ? const Color(0xFF5B5FEF) : const Color(0xFFF4F6FA),
                    child: Icon(
                      isCurrent ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
                      color: isCurrent ? Colors.white : const Color(0xFF5B5FEF),
                    ),
                  ),
                  title: Text(
                    title == null || title.isEmpty || title == 'null' ? '未命名会话' : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600),
                  ),
                  subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: isCurrent
                      ? const Text('当前', style: TextStyle(color: Color(0xFF5B5FEF), fontWeight: FontWeight.w700))
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: id == null ? null : () => Navigator.of(context).pop(id),
                );
              },
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemCount: conversations.length,
            ),
    );
  }
}

/// 聊天消息角色
enum _ChatRole { user, assistant, tool, system }


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
    this.toolCalls = const [],
  });

  final _ChatRole role;
  final String content;
  final String? reasoningContent;
  final DateTime? timestamp;
  final String? toolCallId;
  final List<_ToolCallRecord> toolCalls;

  _ChatMessage copyWith({
    String? content,
    String? reasoningContent,
    DateTime? timestamp,
    String? toolCallId,
    List<_ToolCallRecord>? toolCalls,
  }) {
    return _ChatMessage(
      role: role,
      content: content ?? this.content,
      reasoningContent: reasoningContent ?? this.reasoningContent,
      timestamp: timestamp ?? this.timestamp,
      toolCallId: toolCallId ?? this.toolCallId,
      toolCalls: toolCalls ?? this.toolCalls,
    );
  }
}

