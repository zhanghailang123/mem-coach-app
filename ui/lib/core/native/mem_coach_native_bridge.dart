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

  static Future<String> uploadPdf(String path) async {
    final result = await _methodChannel.invokeMethod<String>('pdf.upload', {'path': path});
    return result ?? '';
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
    this.isFinal = false,
    this.raw = const {},
  });

  final String type;
  final String? content;
  final int? round;
  final String? toolName;
  final String? arguments;
  final String? result;
  final String? error;
  final bool isFinal;
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
      isFinal: json['isFinal'] == true || json['isFinal']?.toString() == 'true',
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
