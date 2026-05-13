import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

class MemCoachNativeBridge {
  MemCoachNativeBridge._();

  static const MethodChannel _methodChannel = MethodChannel('mem_coach/native');
  static const EventChannel _agentEventChannel = EventChannel('mem_coach/agent_events');

  static Stream<AgentNativeEvent>? _agentEvents;

  static Stream<AgentNativeEvent> get agentEvents {
    return _agentEvents ??= _agentEventChannel.receiveBroadcastStream().map((event) {
      if (event is String) {
        return AgentNativeEvent.fromJson(jsonDecode(event) as Map<String, dynamic>);
      }
      return AgentNativeEvent.fromJson(Map<String, dynamic>.from(event as Map));
    });
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
      content: json['content'] as String?,
      round: json['round'] as int?,
      toolName: json['toolName'] as String?,
      arguments: json['arguments'] as String?,
      result: json['result'] as String?,
      error: json['error'] as String?,
      isFinal: json['isFinal'] as bool? ?? false,
      raw: json,
    );
  }
}
