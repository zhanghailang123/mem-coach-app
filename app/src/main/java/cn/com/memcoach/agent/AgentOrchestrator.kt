package cn.com.memcoach.agent

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * Agent 编排器 —— ReAct 模式主循环
 *
 * 实现 Reasoning + Acting 交替的 Agent 主循环：
 *   Thought → Action → Observation → Thought → ... → Final Answer
 *
 * 核心设计决策：
 * - while(true) 循环，最大 50 轮安全护栏
 * - 每轮 LLM 决定是否调用工具，不调用则输出最终回复
 * - 工具执行结果以 role=tool 消息回传 LLM
 * - 支持 Self-Reflection 检查点（每 5 轮或状态转换时）
 *
 * 借鉴：OpenOmniBot AgentOrchestrator 的 while(true) 多轮工具调用循环
 */
class AgentOrchestrator(
    private val llmClient: AgentLlmClient,
    private val toolRouter: AgentToolRouter,
    private val systemPrompt: AgentSystemPrompt
) {
    companion object {
        private const val MAX_ROUNDS = 50  // 安全护栏：最多 50 轮
        private const val REFLECTION_INTERVAL = 5  // 每 5 轮触发一次反思
    }

    /**
     * 执行 Agent 主循环
     *
     * @param input Agent 输入（用户消息、对话历史、上下文）
     * @return Flow<AgentEvent> SSE 事件流，供 Flutter UI 实时展示
     */
    suspend fun run(input: AgentInput): Flow<AgentEvent> = flow {
        val messages = mutableListOf<ChatMessage>()

        // Layer 1: 注入 System Prompt（人设 + 工作模式 + 工具规范 + 上下文）
        val systemPrompt = systemPrompt.build(input.context)
        messages.add(ChatMessage(role = "system", content = systemPrompt))

        // Layer 2: 注入对话历史（如果有）
        input.conversationHistory.forEach { msg ->
            messages.add(msg.toChatMessage())
        }

        // Layer 3: 注入用户消息
        messages.add(
            ChatMessage(
                role = "user",
                content = input.userMessage
            )
        )

        var round = 0
        var totalPromptTokens = 0
        var totalDecodeTokens = 0

        // ─────── ReAct 主循环 ───────
        while (round < input.maxRounds) {
            round++

            // 发送思考开始事件
            emit(AgentEvent.ThinkingStart(round))

            // 调用 LLM（流式 + 工具定义）
            val accumulator = AgentLlmStreamAccumulator()
            val toolDefinitions = toolRouter.getToolDefinitions()

            llmClient.streamTurn(
                messages = messages.toList(),
                tools = toolDefinitions,
                onChunk = { chunk ->
                    accumulator.accumulate(chunk)
                    // 流式输出思考内容
                    if (chunk.content != null) {
                        emit(AgentEvent.ThinkingUpdate(chunk.content))
                    }
                }
            )

            // 判断 LLM 是否调用工具
            if (!accumulator.isToolCall()) {
                // 无工具调用 → 输出最终回复
                emit(AgentEvent.ChatMessage(accumulator.content, isFinal = true))
                emit(
                    AgentEvent.Complete(
                        AgentResult(
                            content = accumulator.content,
                            rounds = round,
                            promptTokens = totalPromptTokens,
                            decodeTokens = totalDecodeTokens
                        )
                    )
                )
                return@flow
            }

            // ── 有工具调用：执行工具 ──
            // 1. 记录 assistant 的 tool_call 消息
            val assistantMsg = accumulator.toAssistantMessage()
            messages.add(assistantMsg)

            // 2. 逐个执行工具
            for (toolCall in accumulator.toolCalls) {
                val toolName = toolCall.name
                val arguments = toolCall.arguments

                // 通知 UI：工具调用开始
                emit(AgentEvent.ToolCallStart(toolName, arguments))

                try {
                    // 路由到具体 Handler 执行
                    val result = toolRouter.execute(toolName, arguments)

                    // 通知 UI：工具调用完成
                    emit(AgentEvent.ToolCallComplete(toolName, result))

                    // 3. 工具结果以 role=tool 消息回传 LLM
                    messages.add(
                        ChatMessage(
                            role = "tool",
                            content = result,
                            toolCallId = toolCall.id
                        )
                    )
                } catch (e: Exception) {
                    // 工具执行失败 → 返回错误信息给 LLM，让它决定如何处理
                    val errorResult = """{"error": "${e.message?.replace("\"", "\\\"")}"}"""
                    emit(AgentEvent.ToolCallError(toolName, e.message ?: "Unknown error"))
                    messages.add(
                        ChatMessage(
                            role = "tool",
                            content = errorResult,
                            toolCallId = toolCall.id
                        )
                    )
                }
            }

            // ── Self-Reflection 检查点 ──
            if (round % REFLECTION_INTERVAL == 0) {
                emit(AgentEvent.ReflectionCheck(round))
            }

            // 继续下一轮循环（LLM 根据工具结果继续推理）
        }

        // 超过最大轮次 → 强制结束
        emit(
            AgentEvent.Error(
                "已达到最大推理轮次（${input.maxRounds}），请尝试更简洁的问题。"
            )
        )
    }.kotlinx.coroutines.flow.flowOn(kotlinx.coroutines.Dispatchers.IO)
}

/**
 * Agent 输入
 */
data class AgentInput(
    val userMessage: String,                            // 用户消息
    val conversationHistory: List<ConversationMessage> = emptyList(),  // 历史对话
    val context: AgentPromptContext,                     // 上下文（学情、记忆等）
    val modelOverride: String? = null,                   // 模型覆盖（可选）
    val maxRounds: Int = 50                              // 最大轮次覆盖
)

/**
 * Agent 结果
 */
data class AgentResult(
    val content: String,            // 最终回复
    val rounds: Int,                // 实际轮次
    val promptTokens: Int,          // Prompt Token 消耗
    val decodeTokens: Int           // Decode Token 消耗
)

/**
 * Chat 消息
 */
data class ChatMessage(
    val role: String,               // system / user / assistant / tool
    val content: String,
    val toolCallId: String? = null, // tool 角色时使用
    val toolCalls: List<ToolCall>? = null  // assistant 角色调用工具时使用
)

/**
 * 工具调用
 */
data class ToolCall(
    val id: String,                 // call_abc123
    val name: String,               // 工具名称
    val arguments: String           // JSON 参数字符串
)

/**
 * 历史消息（从 Flutter 传过来的简化格式）
 */
data class ConversationMessage(
    val role: String,
    val content: String,
    val toolCallId: String? = null,
    val toolCalls: List<Map<String, String>>? = null
) {
    fun toChatMessage(): ChatMessage = ChatMessage(
        role = role,
        content = content,
        toolCallId = toolCallId,
        toolCalls = toolCalls?.map {
            ToolCall(
                id = it["id"] ?: "",
                name = it["name"] ?: "",
                arguments = it["arguments"] ?: "{}"
            )
        }
    )
}
