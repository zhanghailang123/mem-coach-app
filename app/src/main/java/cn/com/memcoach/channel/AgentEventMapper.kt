package cn.com.memcoach.channel

import cn.com.memcoach.agent.AgentEvent

object AgentEventMapper {
    fun toMap(event: AgentEvent): Map<String, Any?> = when (event) {
        is AgentEvent.ThinkingStart -> mapOf(
            "type" to "thinking_start",
            "round" to event.round
        )

        is AgentEvent.ThinkingUpdate -> mapOf(
            "type" to "thinking_update",
            "content" to event.content
        )

        is AgentEvent.ToolCallStart -> mapOf(
            "type" to "tool_call_start",
            "toolName" to event.toolName,
            "arguments" to event.arguments
        )

        is AgentEvent.ToolCallComplete -> mapOf(
            "type" to "tool_call_complete",
            "toolName" to event.toolName,
            "result" to event.result
        )

        is AgentEvent.ToolCallError -> mapOf(
            "type" to "tool_call_error",
            "toolName" to event.toolName,
            "error" to event.error
        )

        is AgentEvent.ChatMessage -> mapOf(
            "type" to "chat_message",
            "content" to event.content,
            "isFinal" to event.isFinal
        )

        is AgentEvent.ReflectionCheck -> mapOf(
            "type" to "reflection_check",
            "round" to event.round
        )

        is AgentEvent.Complete -> mapOf(
            "type" to "complete",
            "content" to event.result.content,
            "rounds" to event.result.rounds,
            "promptTokens" to event.result.promptTokens,
            "decodeTokens" to event.result.decodeTokens
        )

        is AgentEvent.Error -> mapOf(
            "type" to "error",
            "error" to event.message
        )
    }
}
