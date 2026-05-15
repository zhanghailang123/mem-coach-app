package cn.com.memcoach.agent

import cn.com.memcoach.agent.llm.AgentLlmRouter
import cn.com.memcoach.agent.memory.DailyMemoryService
import cn.com.memcoach.agent.skill.StudySceneRecognizer
import cn.com.memcoach.agent.skill.StudySkillMatcher
import cn.com.memcoach.agent.skill.StudySkillLoader
import cn.com.memcoach.agent.skill.StudyScene
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.channels.SendChannel
import kotlinx.coroutines.launch


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
 * - 支持 LLM 分层路由，根据任务复杂度自动选择最优模型
 *
 * 借鉴：OpenOmniBot AgentOrchestrator 的 while(true) 多轮工具调用循环
 */
class AgentOrchestrator(
    private val llmClient: AgentLlmClient,
    private val toolRouter: AgentToolRouter,
    private val systemPrompt: AgentSystemPrompt,
    private val contextCompactor: AgentContextCompactor? = null,
    private val stateMachine: StudyStateMachine? = null,
    private val llmRouter: AgentLlmRouter? = null,
    private val dailyMemoryService: DailyMemoryService? = null,
    private val orchestratorScope: CoroutineScope? = null,
    private val skillRegistry: cn.com.memcoach.agent.skill.StudySkillRegistry? = null
) {
    companion object {
        private const val MAX_ROUNDS = 50  // 安全护栏：最多 50 轮
        private const val REFLECTION_INTERVAL = 5  // 每 5 轮触发一次反思
        private const val MAX_RETRY_ATTEMPTS = 3  // 工具调用最大重试次数
    }
    
    /**
     * 带序列号的事件发送包装函数
     * 用于前端去重和增量合并
     */
    private suspend fun <T> SendChannel<T>.sendWithSeq(event: T, seqCounter: () -> Int): T {
        // 注意：这里需要修改 AgentEvent 类来包含 seq 字段
        // 暂时直接发送事件，序列号功能需要配合 AgentEvent 和 AgentEventMapper 修改
        send(event)
        return event
    }

    private var reasoningEffort: AgentReasoningEffort = AgentReasoningEffort.MEDIUM

    fun setReasoningEffort(effort: AgentReasoningEffort) {
        reasoningEffort = effort
    }

    suspend fun manualCompact(
        history: List<ConversationMessage>,
        context: AgentPromptContext
    ): AgentManualCompactResult {
        val compactor = contextCompactor ?: return AgentManualCompactResult(
            compacted = false,
            summary = "当前未启用上下文压缩器。",
            messageCountBefore = history.size,
            messageCountAfter = history.size
        )

        val messages = mutableListOf<ChatMessage>()
        messages.add(ChatMessage(role = "system", content = systemPrompt.build(context)))
        history.forEach { messages.add(it.toChatMessage()) }

        val compactedMessages = compactor.compactNow(messages)
        val summary = compactedMessages.firstOrNull {
            it.role == "user" && it.content.startsWith("[以下是之前对话的压缩摘要")
        }?.content.orEmpty()

        return AgentManualCompactResult(
            compacted = compactedMessages.size < messages.size || summary.isNotBlank(),
            summary = summary,
            messageCountBefore = messages.size,
            messageCountAfter = compactedMessages.size
        )
    }

    /**
     * 执行 Agent 主循环
     *
     * @param input Agent 输入（用户消息、对话历史、上下文）
     * @return Flow<AgentEvent> SSE 事件流，供 Flutter UI 实时展示
     */
    suspend fun run(input: AgentInput): Flow<AgentEvent> = channelFlow {
        val messages = mutableListOf<ChatMessage>()
        var eventSeq = 0  // 事件序列号，用于前端去重

        // ── 集成 StudyStateMachine：推断学习状态 ──
        val currentState = stateMachine?.let { sm ->
            val inferred = sm.inferState(input.userMessage)
            sm.transition(inferred)
            send(AgentEvent.StateChanged(inferred.name, sm.getStateDisplayName(inferred)))
            inferred
        }

        // Layer 1: 注入 System Prompt（人设 + 工作模式 + 工具规范 + 上下文 + 状态 Prompt + Skill 指令）
        val basePrompt = systemPrompt.build(input.context)
        val statePrompt = stateMachine?.getStatePrompt() ?: ""
        val toolGuidelines = buildToolUsageGuidelines(currentState)
        
        // ── 集成 Skill 系统：识别场景、匹配 Skill、加载指令 ──
        val skillInstructions = if (skillRegistry != null) {
            val sceneRecognizer = StudySceneRecognizer()
            val skillMatcher = StudySkillMatcher(skillRegistry)
            val skillLoader = StudySkillLoader()
            
            // 识别学习场景
            val scene = sceneRecognizer.recognize(input.userMessage, input.context)
            
            // 匹配最合适的 Skill
            val matchedSkills = skillMatcher.match(scene, input.context)
            
            // 加载匹配 Skill 的指令
            val instructions = matchedSkills.joinToString("\n\n---\n\n") { result ->
                skillLoader.loadInstructions(result.skill)
            }
            
            // 发送场景识别事件（用于 UI 展示）
            send(AgentEvent.StateChanged(scene.name, sceneRecognizer.getSceneDisplayName(scene)))
            
            instructions
        } else {
            ""
        }
        
        val systemPromptText = basePrompt
            .replace("{{TOOLS}}", toolGuidelines)
            .replace("{{SKILLS}}", if (skillInstructions.isNotBlank()) skillInstructions else "当前没有特定的学习策略激活。")
            .plus(if (statePrompt.isNotEmpty()) "\n\n$statePrompt" else "")
        messages.add(ChatMessage(role = "system", content = systemPromptText))

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
            send(AgentEvent.ThinkingStart(round, reasoningEffort.name.lowercase()))

            // 调用 LLM（流式 + 工具定义，根据状态过滤工具）
            val accumulator = AgentLlmStreamAccumulator()
            val toolDefinitions = getFilteredToolDefinitions(currentState)

            // 优先使用路由器（根据任务复杂度自动选择模型），否则回退到直接客户端
            if (llmRouter != null) {
                llmRouter.streamTurn(
                    messages = messages.toList(),
                    tools = toolDefinitions,
                    taskDescription = input.userMessage,
                    onChunk = { chunk ->
                        accumulator.accumulate(chunk)
                        if (chunk.content != null) {
                            send(AgentEvent.ThinkingUpdate(chunk.content))
                        }
                    }
                )
            } else {
                llmClient.streamTurn(
                    messages = messages.toList(),
                    tools = toolDefinitions,
                    onChunk = { chunk ->
                        accumulator.accumulate(chunk)
                        if (chunk.content != null) {
                            send(AgentEvent.ThinkingUpdate(chunk.content))
                        }
                    }
                )
            }

            // ── 上下文压缩检查 ──
            // 如果 token 使用量超过阈值，压缩旧消息以节省上下文窗口
            if (contextCompactor != null && accumulator.promptTokens > 0) {
                val compacted = contextCompactor.compactIfNeeded(messages, accumulator.promptTokens)
                if (compacted !== messages) {
                    messages.clear()
                    messages.addAll(compacted)
                    send(AgentEvent.ContextCompacted(accumulator.promptTokens))
                }
            }

            // 判断 LLM 是否调用工具
            if (!accumulator.isToolCall()) {
                // 无工具调用 → 输出最终回复
                send(AgentEvent.ChatMessage(accumulator.content, isFinal = true))
                send(
                    AgentEvent.Complete(
                        AgentResult(
                            content = accumulator.content,
                            rounds = round,
                            promptTokens = totalPromptTokens,
                            decodeTokens = totalDecodeTokens
                        )
                    )
                )

                // ── 异步触发记忆巩固 ──
                orchestratorScope?.launch(Dispatchers.IO) {
                    consolidateSessionMemory(messages)
                }

                return@channelFlow
            }

            // ── 有工具调用：执行工具 ──
            // 1. 记录 assistant 的 tool_call 消息
            val assistantMsg = accumulator.toAssistantMessage()
            messages.add(assistantMsg)

            // 2. 逐个执行工具（带重试机制）
            for (toolCall in accumulator.toolCalls) {
                val toolName = toolCall.name
                val arguments = toolCall.arguments
                var lastError: Exception? = null
                var success = false

                if (toolName.isBlank() || toolName == "null") {
                    val errorResult = """{"error": "无效的工具名称 '$toolName'。请检查可用工具定义，确保名称拼写正确。"}"""
                    send(AgentEvent.ToolCallError(toolName, "无效工具名"))
                    messages.add(
                        ChatMessage(
                            role = "tool",
                            content = errorResult,
                            toolCallId = toolCall.id
                        )
                    )
                    continue
                }

                // 重试机制：最多3次
                for (attempt in 1..MAX_RETRY_ATTEMPTS) {
                    // 通知 UI：工具调用开始
                    send(AgentEvent.ToolCallStart(toolName, arguments, toolCall.id))

                    try {
                        // 路由到具体 Handler 执行
                        val result = toolRouter.execute(toolName, arguments)

                        // 通知 UI：工具调用完成
                        send(AgentEvent.ToolCallComplete(toolName, result, toolCall.id))

                        // 3. 工具结果以 role=tool 消息回传 LLM
                        messages.add(
                            ChatMessage(
                                role = "tool",
                                content = result,
                                toolCallId = toolCall.id
                            )
                        )
                        success = true
                        break
                    } catch (e: Exception) {
                        lastError = e
                        if (attempt < MAX_RETRY_ATTEMPTS) {
                            // 通知 UI：工具调用重试
                            send(AgentEvent.ToolCallRetry(toolName, attempt, e.message ?: "Unknown error"))
                            // 指数退避：1s, 2s, 4s...
                            delay(1000L * (1 shl (attempt - 1)))
                        }
                    }
                }

                // 所有重试都失败
                if (!success) {
                    val errorResult = """{"error": "${lastError?.message?.replace("\"", "\\\"") ?: "Unknown error"}","retry_exhausted": true}"""
                    send(AgentEvent.ToolCallError(toolName, lastError?.message ?: "Unknown error"))
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
                send(AgentEvent.ReflectionCheck(round))
            }

            // 继续下一轮循环（LLM 根据工具结果 continue 推理）
        }

        // 超过最大轮次 → 强制结束
        send(
            AgentEvent.Error(
                "已达到最大推理轮次（${input.maxRounds}），请尝试更简洁的问题。"
            )
        )
    }.flowOn(Dispatchers.IO)

    /**
     * 记忆巩固：从对话中提取关键学习笔记、用户偏好等
     */
    private suspend fun consolidateSessionMemory(messages: List<ChatMessage>) {
        val service = dailyMemoryService ?: return
        val client = llmClient // 使用标准模型提取即可

        try {
            val historyText = messages.takeLast(6).joinToString("\n") { 
                "${it.role}: ${it.content.take(200)}" 
            }

            val prompt = """
                你是一个学习教练助手。请从以下对话片段中提取有价值的学习记忆（用户偏好、难点、进度、待办）。
                
                对话内容：
                $historyText
                
                要求：
                1. 仅输出一条最重要的简洁记忆点。
                2. 语气要客观，如：“用户表示不喜欢代数推导，更倾向于几何直观展示。” 或 “用户计划本周末完成2024年真题。”
                3. 如果没有发现重要信息，输出 "NONE"。
                4. 不要带任何解释。
            """.trimIndent()

            val result = client.completeTurn(
                messages = listOf(ChatMessage(role = "user", content = prompt)),
                tools = null
            )

            val learning = result.content.trim()
            if (learning != "NONE" && learning.length > 5) {
                service.append("AI自动反思：$learning")
            }
        } catch (e: Exception) {
            // 后台任务失败不影响主流程
        }
    }

    /**
     * 根据学习状态获取过滤后的工具定义
     */
    private fun getFilteredToolDefinitions(currentState: StudyStateMachine.State?): List<Map<String, Any>> {
        val allDefinitions = toolRouter.getToolDefinitions()
        val allowedTools = currentState?.let { stateMachine?.getAllowedTools() }
        
        return if (allowedTools != null && allowedTools.isNotEmpty()) {
            allDefinitions.filter { toolMap ->
                val function = toolMap["function"] as? Map<*, *>
                val name = function?.get("name") as? String
                name in allowedTools
            }
        } else {
            allDefinitions
        }
    }

    /**
     * 构建工具使用规范文本，用于替换系统提示词中的 {{TOOLS}} 占位符。
     *
     * 工具定义已通过 API 的 tools 参数传入，此处只输出使用原则，避免重复浪费 token。
     */
    private fun buildToolUsageGuidelines(currentState: StudyStateMachine.State? = null): String {
        val definitions = getFilteredToolDefinitions(currentState)
        if (definitions.isEmpty()) {
            return "## 可用工具\n\n当前没有可用工具。"
        }

        // 仅列出工具名称概览，具体参数由 API tools 定义
        val toolNames = definitions.mapNotNull { toolMap ->
            val function = toolMap["function"] as? Map<*, *>
            function?.get("name") as? String
        }

        val sb = StringBuilder()
        sb.appendLine("## 可用工具")
        sb.appendLine()
        sb.appendLine("你有 ${toolNames.size} 个工具可以调用：${toolNames.joinToString("、") { "`$it`" }}。")
        sb.appendLine("调用工具时，使用 Function Calling 格式。工具的参数和描述已通过 API 定义，请参考。")
        sb.appendLine()
        sb.appendLine("## 工具使用原则")
        sb.appendLine("1. **先搜后答**：永远不要凭空编造题目、知识点或 PDF 内容。先用 exam_question_search、knowledge_search 或 pdf_query 获取真实数据。")
        sb.appendLine("2. **PDF 引用**：当用户消息包含 document_id 时，优先调用 pdf_query(document_id, question)，再基于返回的 text 回答。")
        sb.appendLine("3. **一次一个**：每次只调用一个工具，等待结果返回后再决定下一步。")
        sb.appendLine("4. **结果可溯源**：使用工具返回的数据时，标注来源（\"来自 2023 年真题第 5 题\" 或 \"来自 PDF xxx\"）。")
        sb.appendLine("5. **失败降级**：如果工具调用失败，告诉用户\"这个操作暂时不可用\"，并提供替代建议。")

        return sb.toString()
    }
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

data class AgentManualCompactResult(
    val compacted: Boolean,
    val summary: String,
    val messageCountBefore: Int,
    val messageCountAfter: Int
)

enum class AgentReasoningEffort {
    LOW,
    MEDIUM,
    HIGH
}

/**
 * Chat 消息
 */

data class ChatMessage(
    val role: String,               // system / user / assistant / tool
    val content: String,
    val reasoningContent: String? = null, // 深度思考内容
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
    val reasoningContent: String? = null,
    val toolCallId: String? = null,
    val toolCalls: List<Map<String, String>>? = null
) {
    fun toChatMessage(): ChatMessage = ChatMessage(
        role = role,
        content = content,
        reasoningContent = reasoningContent,
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
