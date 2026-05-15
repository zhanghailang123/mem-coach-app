import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

class MemCoachNativeBridge {
  MemCoachNativeBridge._();

  static const MethodChannel _methodChannel = MethodChannel('mem_coach/native');
  static const EventChannel _agentEventChannel = EventChannel('mem_coach/agent_events');

  static Stream<AgentNativeEvent>? _agentEvents;

  static Stream<AgentNativeEvent> get agentEvents {
    return _agentEvents ??= _agentEventChannel.receiveBroadcastStream().map(_parseAgentEvent);
  }

  static AgentNativeEvent _parseAgentEvent(Object? event) {
    try {
      if (event is String) {
        final decoded = jsonDecode(event);
        if (decoded is Map) {
          return AgentNativeEvent.fromJson(Map<String, dynamic>.from(decoded));
        }
        return AgentNativeEvent.error('Native 事件 JSON 不是对象：$decoded');
      }
      if (event is Map) {
        return AgentNativeEvent.fromJson(Map<String, dynamic>.from(event));
      }
      return AgentNativeEvent.error('未知 Native 事件类型：${event.runtimeType}');
    } catch (error) {
      return AgentNativeEvent.error('Native 事件解析失败：$error');
    }
  }

  static Future<String> startAgentTurn({
    required String message,
    List<Map<String, dynamic>> history = const [],
    Map<String, dynamic> context = const {},
  }) async {
    final result = await _methodChannel.invokeMethod<String>('agent.startTurn', {
      'message': message,
      'history': history,
      'context': context,
    });
    return result ?? '';
  }

  static Future<void> cancelAgentTurn() {
    return _methodChannel.invokeMethod<void>('agent.cancelTurn');
  }

  static Future<Map<String, dynamic>> compactContext({
    List<Map<String, dynamic>> history = const [],
  }) async {
    final result = await _methodChannel.invokeMapMethod<String, dynamic>('agent.compactContext', {
      'history': history,
    });
    return result ?? {};
  }

  static Future<Map<String, dynamic>> setReasoningEffort(String level) async {
    final result = await _methodChannel.invokeMapMethod<String, dynamic>('agent.setReasoningEffort', {
      'level': level,
    });
    return result ?? {};
  }

  static Future<Map<String, dynamic>> uploadPdf(String path, {String? subject, int? year}) async {

    final result = await _methodChannel.invokeMapMethod<String, dynamic>('pdf.upload', {
      'file_path': path,
      if (subject != null) 'subject': subject,
      if (year != null) 'year': year,
    });
    return result ?? {};
  }

  static Future<List<Map<String, dynamic>>> listPdfs() async {
    final result = await _methodChannel.invokeListMethod<dynamic>('pdf.list');
    return (result ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<Map<String, dynamic>> getPdfParseStatus(String jobId) async {
    final result = await _methodChannel.invokeMapMethod<String, dynamic>('pdf.parseStatus', {
      'job_id': jobId,
    });
    return result ?? {};
  }

  static Future<List<String>> getActivePdfJobs() async {
    final result = await _methodChannel.invokeListMethod<String>('pdf.getActiveJobs');
    return result ?? const [];
  }

  static Future<void> deletePdf(String id) async {
    await _methodChannel.invokeMethod<void>('pdf.delete', {
      'id': id,
    });
  }

  static Future<Map<String, dynamic>> getInsightSummary() async {

    final result = await _methodChannel.invokeMapMethod<String, dynamic>('insight.getSummary');
    return result ?? {};
  }

  static Future<List<Map<String, dynamic>>> getRandomQuestions({
    String subject = 'logic',
    int count = 5,
    String? topic,
  }) async {
    final result = await _methodChannel.invokeListMethod<dynamic>('exam.getRandomQuestions', {
      'subject': subject,
      'count': count,
      if (topic != null) 'topic': topic,
    });
    return (result ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<Map<String, dynamic>> submitAnswer({
    required String questionId,
    required String userAnswer,
    int timeSpentSeconds = 0,
  }) async {
    final result = await _methodChannel.invokeMapMethod<String, dynamic>('exam.submitAnswer', {
      'question_id': questionId,
      'user_answer': userAnswer,
      'time_spent_seconds': timeSpentSeconds,
    });
    return result ?? {};
  }

  static Future<List<Map<String, dynamic>>> getKnowledgeTree({
    String subject = 'logic',
  }) async {
    final result = await _methodChannel.invokeListMethod<dynamic>('knowledge.getTree', {
      'subject': subject,
    });
    return (result ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<Map<String, dynamic>> getHomeData() async {
    final result = await _methodChannel.invokeMapMethod<String, dynamic>('home.getData');
    return result ?? {};
  }
  
  // 会话管理方法
  
  /// 创建新会话
  static Future<Map<String, dynamic>> createConversation({
    String title = '新对话',
  }) async {
    final result = await _methodChannel.invokeMapMethod<String, dynamic>('conversation.create', {
      'title': title,
    });
    return result ?? {};
  }
  
  /// 获取用户的所有会话
  static Future<List<Map<String, dynamic>>> getConversations() async {
    final result = await _methodChannel.invokeListMethod<dynamic>('conversation.list');
    return (result ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
  
  /// 获取会话的所有消息
  static Future<List<Map<String, dynamic>>> getConversationMessages({
    required int conversationId,
  }) async {
    final result = await _methodChannel.invokeListMethod<dynamic>('conversation.getMessages', {
      'conversationId': conversationId,
    });
    return (result ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
  
  /// 添加聊天消息
  static Future<Map<String, dynamic>> addChatMessage({
    required int conversationId,
    required String role,
    required String content,
    String? reasoningContent,
    String? toolName,
    String? toolStatus,
    String? toolResult,
    String? toolCallId,
    List<Map<String, dynamic>> toolCalls = const [],
  }) async {

    final result = await _methodChannel.invokeMapMethod<String, dynamic>('conversation.addMessage', {
      'conversationId': conversationId,
      'role': role,
      'content': content,
      'reasoning_content': reasoningContent,
      if (toolName != null) 'toolName': toolName,
      if (toolStatus != null) 'toolStatus': toolStatus,
      if (toolResult != null) 'toolResult': toolResult,
      if (toolCallId != null) 'toolCallId': toolCallId,
      if (toolCalls.isNotEmpty) 'toolCalls': toolCalls,
    });

    return result ?? {};
  }
  
  /// 更新会话消息数量
  static Future<void> updateConversationMessageCount({
    required int conversationId,
  }) async {
    await _methodChannel.invokeMethod<void>('conversation.updateMessageCount', {
      'conversationId': conversationId,
    });
  }
  
  /// 删除会话
  static Future<void> deleteConversation({
    required int conversationId,
  }) async {
    await _methodChannel.invokeMethod<void>('conversation.delete', {
      'conversationId': conversationId,
    });
  }
}


class AgentNativeEvent {
  const AgentNativeEvent({
    required this.type,
    this.content,
    this.round,
    this.toolName,
    this.arguments,
    this.result,
    this.error,
    this.toolCallId,
    this.isFinal = false,

    this.state,
    this.stateName,
    this.raw = const {},
  });

  final String type;
  final String? content;
  final int? round;
  final String? toolName;
  final String? arguments;
  final String? result;
  final String? error;
  final String? toolCallId;
  final bool isFinal;

  final String? state;
  final String? stateName;
  final Map<String, dynamic> raw;

  factory AgentNativeEvent.fromJson(Map<String, dynamic> json) {
    return AgentNativeEvent(
      type: json['type'] as String? ?? 'unknown',
      content: json['content']?.toString(),
      round: json['round'] is int ? json['round'] as int : int.tryParse(json['round']?.toString() ?? ''),
      toolName: json['toolName']?.toString(),
      arguments: json['arguments']?.toString(),
      result: json['result']?.toString(),
      error: json['error']?.toString(),
      toolCallId: json['toolCallId']?.toString(),
      isFinal: json['isFinal'] == true || json['isFinal']?.toString() == 'true',

      state: json['state']?.toString(),
      stateName: json['stateName']?.toString(),
      raw: json,
    );
  }

  factory AgentNativeEvent.error(String message) {
    return AgentNativeEvent(
      type: 'error',
      error: message,
      raw: {'type': 'error', 'error': message},
    );
  }
}
