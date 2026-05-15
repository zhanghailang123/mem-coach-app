package cn.com.memcoach.agent

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Agent 上下文压缩器 —— 当对话 Token 超过阈值时，用 LLM 生成摘要替换旧消息。
 *
 * 设计借鉴：OpenOmniBot AgentConversationContextCompactor 的 128K 阈值压缩机制。
 *
 * 核心流程：
 * 1. 每轮 LLM 调用后检查 promptTokens 是否超过阈值
 * 2. 超过阈值时，将旧消息（保留最近 N 轮）发送给 LLM 生成压缩摘要
 * 3. 用摘要替换旧消息，只保留 system + summary + 最近 N 轮
 *
 * 压缩策略：
 * - 保留 system prompt 不动
 * - 保留最近 COMPACT_KEEP_RECENT_ROUNDS 轮对话
 * - 将更早的消息压缩为一段摘要文本
 * - 摘要必须保留：文件路径、命令、决策、待办、错误信息
 */
class AgentContextCompactor(
    private val llmClient: AgentLlmClient
) {
    companion object {
        /** Token 阈值：超过此值触发压缩（与 OpenOmniBot 一致：128K） */
        const val TOKEN_THRESHOLD = 128_000

        /** 压缩后保留的最近轮次数 */
        const val COMPACT_KEEP_RECENT_ROUNDS = 5

        /** 压缩请求的 System Prompt */
        private const val COMPACTION_SYSTEM_PROMPT = """你是一个上下文压缩引擎。你的摘要将替换对话中的旧消息，Agent 会依赖它继续工作。

必须保留的内容（不可省略或缩短）：
- 所有文件路径、目录名、URL、UUID、标识符 — 原样复制
- 执行过的命令及其结果（成功/失败/输出）
- 当前任务：请求了什么、完成了什么、还有什么待做
- 做出的关键决策及其理由
- 遇到的错误及解决方式
- 用户提到的重要约束、规则或偏好
- 影响当前状态的工具调用及其结果

结构：
1. 以一行总结开头，概括整体目标
2. 然后是简洁的叙述，保留技术细节
3. 以"当前状态"结尾：完成了什么、待做什么、有什么阻塞

优先保留最近的上下文 — Agent 需要知道最近在做什么，而不是早期讨论了什么。

不要翻译或修改代码片段、文件路径、标识符或错误消息。简洁但不丢失 Agent 需要的信息。"""
    }

    /**
     * 检查是否需要压缩，如果需要则执行压缩并返回压缩后的消息列表。
     *
     * @param messages 当前完整消息列表
     * @param promptTokens 最近一次 LLM 调用的 prompt token 数
     * @return 压缩后的消息列表（如果不需要压缩则返回原列表）
     */
    suspend fun compactIfNeeded(
        messages: MutableList<ChatMessage>,
        promptTokens: Int
    ): List<ChatMessage> {
        if (promptTokens <= TOKEN_THRESHOLD) {
            return messages
        }

        // 需要压缩
        return try {
            compact(messages)
        } catch (e: Exception) {
            // 压缩失败时返回原消息，不中断对话
            System.err.println("[AgentContextCompactor] 压缩失败: ${e.message}")
            messages
        }
    }

    /**
     * 手动执行上下文压缩，不检查 Token 阈值。
     */
    suspend fun compactNow(messages: List<ChatMessage>): List<ChatMessage> {
        return compact(messages)
    }

    /**
     * 执行上下文压缩。
     *
     * 策略：
     * 1. 保留 system prompt（第一条消息）
     * 2. 将中间消息（除去最近 N 轮）提取出来
     * 3. 调用 LLM 生成压缩摘要
     * 4. 返回：system + summary_user + summary_assistant + 最近 N 轮
     */
    private suspend fun compact(messages: List<ChatMessage>): List<ChatMessage> {

        if (messages.size <= COMPACT_KEEP_RECENT_ROUNDS + 1) {
            return messages // 消息太少，无需压缩
        }

        // 1. 分离 system prompt
        val systemMessage = messages.firstOrNull { it.role == "system" }
        val nonSystemMessages = messages.filter { it.role != "system" }

        // 2. 分离最近 N 轮和待压缩消息
        val recentCount = COMPACT_KEEP_RECENT_ROUNDS * 2 // 每轮包含 user + assistant/tool
        val recentMessages = nonSystemMessages.takeLast(recentCount)
        val messagesToCompact = nonSystemMessages.dropLast(recentCount)

        if (messagesToCompact.isEmpty()) {
            return messages
        }

        // 3. 调用 LLM 生成压缩摘要
        val summary = requestCompaction(messagesToCompact)
        if (summary.isBlank()) {
            return messages
        }

        // 4. 构建压缩后的消息列表
        val result = mutableListOf<ChatMessage>()

        // 保留 system prompt
        if (systemMessage != null) {
            result.add(systemMessage)
        }

        // 添加压缩摘要（作为 user-assistant 对话）
        result.add(ChatMessage(
            role = "user",
            content = "[以下是之前对话的压缩摘要，请基于此继续]\n\n$summary"
        ))
        result.add(ChatMessage(
            role = "assistant",
            content = "已理解之前的对话上下文，继续为您服务。"
        ))

        // 添加最近的消息
        result.addAll(recentMessages)

        return result
    }

    /**
     * 调用 LLM 生成压缩摘要
     */
    private suspend fun requestCompaction(messagesToCompact: List<ChatMessage>): String = withContext(Dispatchers.IO) {
        val requestMessages = mutableListOf<ChatMessage>()

        // System prompt
        requestMessages.add(ChatMessage(
            role = "system",
            content = COMPACTION_SYSTEM_PROMPT
        ))

        // 待压缩的消息
        requestMessages.addAll(messagesToCompact)

        // 最终请求
        requestMessages.add(ChatMessage(
            role = "user",
            content = "请生成压缩摘要。"
        ))

        // 使用非流式调用生成摘要
        val result = llmClient.completeTurn(
            messages = requestMessages,
            tools = null // 压缩时不使用工具
        )

        result.content.trim()
    }
}
