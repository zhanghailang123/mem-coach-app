package cn.com.memcoach.channel

import cn.com.memcoach.agent.AgentEvent

object AgentEventMapper {
    fun toMap(event: AgentEvent): Map<String, Any?> = when (event) {
        is AgentEvent.ThinkingStart -> mapOf(
            "type" to "thinking_start",
            "round" to event.round,
            "effort" to event.effort
        )


        is AgentEvent.ThinkingUpdate -> mapOf(
            "type" to "thinking_update",
            "content" to event.content
        )

        is AgentEvent.ToolCallStart -> mapOf(
            "type" to "tool_call_start",
            "toolName" to event.toolName,
            "arguments" to event.arguments,
            "toolCallId" to event.toolCallId
        )

        is AgentEvent.ToolCallComplete -> mapOf(
            "type" to "tool_call_complete",
            "toolName" to event.toolName,
            "result" to event.result,
            "toolCallId" to event.toolCallId
        )

        is AgentEvent.ToolCallError -> mapOf(
            "type" to "tool_call_error",
            "toolName" to event.toolName,
            "error" to event.error
        )

        is AgentEvent.ToolCallRetry -> mapOf(
            "type" to "tool_call_retry",
            "toolName" to event.toolName,
            "attempt" to event.attempt,
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

        is AgentEvent.StateChanged -> mapOf(
            "type" to "state_changed",
            "state" to event.state,
            "stateName" to event.stateName
        )

        is AgentEvent.ContextCompacted -> mapOf(
            "type" to "context_compacted",
            "previousPromptTokens" to event.previousPromptTokens
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
