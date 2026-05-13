package cn.com.memcoach.agent.llm

import cn.com.memcoach.agent.AgentLlmClient
import cn.com.memcoach.agent.ChatMessage
import cn.com.memcoach.agent.LlmModelInfo
import cn.com.memcoach.agent.LlmStreamChunk
import cn.com.memcoach.agent.LlmTokenUsage
import cn.com.memcoach.agent.LlmTurnResult
import cn.com.memcoach.agent.ModelTier

/**
 * MVP 本地回声 LLM，用于在真实大模型接入前验证 Agent 编排、通道和 UI 事件流。
 */
class EchoAgentLlmClient : AgentLlmClient {
    override suspend fun streamTurn(
        messages: List<ChatMessage>,
        tools: List<Map<String, Any>>?,
        modelId: String?,
        onChunk: suspend (LlmStreamChunk) -> Unit
    ): LlmTurnResult {
        val userMessage = messages.lastOrNull { it.role == "user" }?.content.orEmpty()
        val content = "我已经收到你的学习请求：$userMessage。真实 LLM 接入后，我会调用题库、知识图谱和记忆工具生成个性化学习方案。"
        onChunk(LlmStreamChunk(content = content))
        return LlmTurnResult(
            content = content,
            finishReason = "stop",
            modelId = modelId ?: "echo-local",
            usage = LlmTokenUsage(promptTokens = 0, completionTokens = 0)
        )
    }

    override suspend fun completeTurn(
        messages: List<ChatMessage>,
        tools: List<Map<String, Any>>?,
        modelId: String?
    ): LlmTurnResult {
        val content = messages.lastOrNull { it.role == "user" }?.content.orEmpty()
        return LlmTurnResult(content = content, finishReason = "stop", modelId = modelId ?: "echo-local")
    }

    override fun getAvailableModels(): List<LlmModelInfo> = listOf(
        LlmModelInfo(
            id = "echo-local",
            displayName = "Echo Local Debug Model",
            tier = ModelTier.LIGHT,
            maxTokens = 4096,
            isDefault = true
        )
    )

    override fun getModelDisplayName(modelId: String): String = "Echo Local Debug Model"
}
