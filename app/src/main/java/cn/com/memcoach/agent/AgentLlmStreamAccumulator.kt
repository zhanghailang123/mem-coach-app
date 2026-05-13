package cn.com.memcoach.agent

import kotlinx.serialization.json.*

/**
 * SSE 流式累加器 —— 将 LLM 的 SSE 流式响应拼接为完整消息，并检测工具调用。
 *
 * 设计思路：
 * - assistant 的回复可能是纯文本，也可能包含 tool_calls
 * - tool_calls 在 SSE 流中是逐 chunk 拼接的（先发 id/name，再增量拼接 arguments）
 * - 需要在所有 chunk 到达后判断 isToolCall()，并提取结构化信息
 *
 * 借鉴：OpenOmniBot AgentLlmStreamAccumulator 的 tool_call 增量拼接逻辑
 */
class AgentLlmStreamAccumulator {
    /** 累积的纯文本内容 */
    var content: String = ""
        private set

    /** 累积的工具调用列表 */
    private val _toolCalls = mutableListOf<ToolCallAccumulator>()
    val toolCalls: List<ToolCall>
        get() = _toolCalls.map { it.toToolCall() }

    /** 当前正在累积的工具调用 index */
    private var currentToolCallIndex: Int? = null

    /** 识别到的终止原因 */
    var finishReason: String? = null
        private set

    /** Token 使用量 */
    var promptTokens: Int = 0
        private set
    var completionTokens: Int = 0
        private set

    /**
     * 累积一个 SSE chunk。
     *
     * 兼容两种输入：
     * - 解析后的 chunk 对象（推荐）
     * - 原始 JSON 字符串（兼容旧接口）
     */
    fun accumulate(chunk: LlmStreamChunk) {
        // 1. 累积纯文本增量
        if (!chunk.content.isNullOrBlank()) {
            content += chunk.content
        }

        // 2. 累积工具调用增量
        chunk.toolCalls?.forEach { tcChunk ->
            val index = tcChunk.index ?: 0

            // 如果 index 还没出现，说明是新工具调用
            while (_toolCalls.size <= index) {
                _toolCalls.add(ToolCallAccumulator())
            }

            val acc = _toolCalls[index]

            // 设置 id
            if (!tcChunk.id.isNullOrBlank()) {
                acc.id = tcChunk.id
            }

            // 增量拼接 arguments
            if (tcChunk.function != null) {
                if (!tcChunk.function.name.isNullOrBlank()) {
                    acc.functionName = tcChunk.function.name
                }
                if (!tcChunk.function.arguments.isNullOrBlank()) {
                    acc.argumentsBuilder.append(tcChunk.function.arguments)
                }
            }
        }

        // 3. 记录 finish reason
        if (!chunk.finishReason.isNullOrBlank()) {
            finishReason = chunk.finishReason
        }

        // 4. 记录 token 使用量
        chunk.usage?.let { usage ->
            promptTokens = usage.promptTokens ?: promptTokens
            completionTokens = usage.completionTokens ?: completionTokens
        }
    }

    /**
     * 批量累积：兼容 String JSON 输入
     */
    fun accumulateJson(jsonStr: String) {
        try {
            val json = Json.parseToJsonElement(jsonStr).jsonObject
            val choices = json["choices"]?.jsonArray?.firstOrNull()?.jsonObject
            val delta = choices?.get("delta")?.jsonObject

            val chunkObj = LlmStreamChunk(
                content = delta?.get("content")?.jsonPrimitive?.content,
                finishReason = choices?.get("finish_reason")?.jsonPrimitive?.content,
                toolCalls = delta?.get("tool_calls")?.jsonArray?.map { tcElement ->
                    val tc = tcElement.jsonObject
                    val fn = tc["function"]?.jsonObject
                    LlmToolCallChunk(
                        index = tc["index"]?.jsonPrimitive?.int,
                        id = tc["id"]?.jsonPrimitive?.content,
                        function = LlmToolCallFunction(
                            name = fn?.get("name")?.jsonPrimitive?.content,
                            arguments = fn?.get("arguments")?.jsonPrimitive?.content
                        )
                    )
                }
            )
            accumulate(chunkObj)
        } catch (_: Exception) {
            // 解析失败忽略
        }
    }

    /** 是否检测到工具调用 */
    fun isToolCall(): Boolean = _toolCalls.isNotEmpty()

    /** 生成 assistant 的 ChatMessage（包含 tool_calls） */
    fun toAssistantMessage(): ChatMessage {
        return ChatMessage(
            role = "assistant",
            content = content.ifBlank { " " },  // 纯工具调用时 content 可能为空，但 API 要求不能为空
            toolCalls = toolCalls
        )
    }

    /** 判断是否有内容 */
    fun hasContent(): Boolean = content.isNotBlank()

    /** 重置累加器 */
    fun reset() {
        content = ""
        _toolCalls.clear()
        finishReason = null
        promptTokens = 0
        completionTokens = 0
    }

    // ─── 内部累加器 ───

    private class ToolCallAccumulator {
        var id: String = ""
        var functionName: String = ""
        val argumentsBuilder = StringBuilder()

        fun toToolCall(): ToolCall = ToolCall(
            id = id,
            name = functionName,
            arguments = argumentsBuilder.toString()
        )
    }
}

/**
 * SSE 流式 chunk 的数据类
 */
data class LlmStreamChunk(
    val content: String? = null,
    val finishReason: String? = null,
    val toolCalls: List<LlmToolCallChunk>? = null,
    val usage: LlmTokenUsage? = null
)

/**
 * 单个工具调用的增量 chunk
 */
data class LlmToolCallChunk(
    val index: Int? = null,
    val id: String? = null,
    val function: LlmToolCallFunction? = null
)

/**
 * 工具调用函数 chunk
 */
data class LlmToolCallFunction(
    val name: String? = null,
    val arguments: String? = null
)

/**
 * Token 使用量
 */
data class LlmTokenUsage(
    val promptTokens: Int? = null,
    val completionTokens: Int? = null
)
