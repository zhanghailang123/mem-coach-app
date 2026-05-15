/// Agent 流式事件状态管理器
/// 借鉴 OpenOmniBot 的 AgentStreamReducer 模式
/// 通过序列号检查避免重复处理，使用增量合并优化 UI 更新
class AgentStreamState {
  const AgentStreamState({
    this.lastSeq = 0,
    this.isThinking = false,
    this.thinkingStage = 1,
    this.currentPhase = AgentStreamPhase.idle,
    this.lastAssistantContent = '',
  });

  final int lastSeq;
  final bool isThinking;
  final int thinkingStage;
  final AgentStreamPhase currentPhase;
  final String lastAssistantContent;

  AgentStreamState copyWith({
    int? lastSeq,
    bool? isThinking,
    int? thinkingStage,
    AgentStreamPhase? currentPhase,
    String? lastAssistantContent,
  }) {
    return AgentStreamState(
      lastSeq: lastSeq ?? this.lastSeq,
      isThinking: isThinking ?? this.isThinking,
      thinkingStage: thinkingStage ?? this.thinkingStage,
      currentPhase: currentPhase ?? this.currentPhase,
      lastAssistantContent: lastAssistantContent ?? this.lastAssistantContent,
    );
  }
}

enum AgentStreamPhase {
  idle,
  thinking,
  toolCall,
  output,
  completed,
  error,
}

class AgentStreamReduceResult {
  const AgentStreamReduceResult({
    required this.accepted,
    required this.previousState,
    required this.nextState,
  });

  final bool accepted;
  final AgentStreamState previousState;
  final AgentStreamState nextState;
}

class AgentStreamReducer {
  const AgentStreamReducer();

  /// 处理流式事件，返回是否接受该事件
  AgentStreamReduceResult reduce(AgentStreamState? current, String eventType, int? seq) {
    final previousState = current ?? const AgentStreamState();
    
    // 如果没有序列号，接受事件（兼容旧版本）
    if (seq == null) {
      final nextState = _applyEvent(previousState, eventType);
      return AgentStreamReduceResult(
        accepted: true,
        previousState: previousState,
        nextState: nextState,
      );
    }
    
    // 检查序列号，避免重复处理
    if (seq <= previousState.lastSeq) {
      return AgentStreamReduceResult(
        accepted: false,
        previousState: previousState,
        nextState: previousState,
      );
    }

    final nextState = _applyEvent(previousState, eventType);
    return AgentStreamReduceResult(
      accepted: true,
      previousState: previousState,
      nextState: nextState.copyWith(lastSeq: seq),
    );
  }

  AgentStreamState _applyEvent(AgentStreamState state, String eventType) {
    switch (eventType) {
      case 'thinking_start':
        return state.copyWith(
          isThinking: true,
          thinkingStage: 1,
          currentPhase: AgentStreamPhase.thinking,
        );
      case 'thinking_update':
        return state.copyWith(
          thinkingStage: 2,
          currentPhase: AgentStreamPhase.thinking,
        );
      case 'tool_call_start':
      case 'tool_call_complete':
      case 'tool_call_error':
        return state.copyWith(
          isThinking: false,
          thinkingStage: 2,
          currentPhase: AgentStreamPhase.toolCall,
        );
      case 'chat_message':
        return state.copyWith(
          isThinking: false,
          thinkingStage: 3,
          currentPhase: AgentStreamPhase.output,
        );
      case 'complete':
        return state.copyWith(
          isThinking: false,
          thinkingStage: 4,
          currentPhase: AgentStreamPhase.completed,
        );
      case 'error':
        return state.copyWith(
          isThinking: false,
          thinkingStage: 4,
          currentPhase: AgentStreamPhase.error,
        );
      default:
        return state;
    }
  }
}

/// 增量合并助手内容
/// 借鉴 OpenOmniBot 的 stream_text_merge.dart
String mergeAssistantContent(String current, String incoming) {
  if (incoming.isEmpty) return current;
  if (current.isEmpty) return incoming;
  if (incoming == current) return current;
  
  // 如果 incoming 是 current 的前缀（回退），忽略
  if (incoming.length < current.length && current.startsWith(incoming)) {
    return current;
  }
  
  // 直接替换，不累加（OpenOmniBot 的做法）
  return incoming;
}
