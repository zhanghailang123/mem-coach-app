package cn.com.memcoach.agent

/**
 * LLM 客户端接口 —— 抽象 LLM API 调用，支持流式和非流式两种模式。
 *
 * 设计原则：
 * - 接口与具体 LLM 提供商解耦（OpenAI / 通义千问 / DeepSeek 均可适配）
 * - 流式模式：SSE 逐 token 回调，用于实时展示 Agent 推理过程
 * - 非流式模式：完整返回，用于 Plan-Execute 等需要完整计划再执行的场景
 *
 * 借鉴：OpenOmniBot 的 LLM 调用封装
 */
interface AgentLlmClient {

    /**
     * 流式调用 LLM（默认模式，用于 ReAct 交互）
     *
     * @param messages 当前对话消息列表（包含 system、历史 user/assistant/tool）
     * @param tools 可用工具定义列表（可为空，表示本轮不允许调用工具）
     * @param modelId 指定模型 ID（可选，为空则使用路由自动选择）
     * @param onChunk 每个 SSE chunk 的回调
     * @return 最终累积的结果
     */
    suspend fun streamTurn(
        messages: List<ChatMessage>,
        tools: List<Map<String, Any>>? = null,
        modelId: String? = null,
        onChunk: suspend (LlmStreamChunk) -> Unit
    ): LlmTurnResult

    /**
     * 非流式调用 LLM（用于 Plan-Execute、Reflection 等需要完整输出再继续的场景）
     *
     * @param messages 当前对话消息列表
     * @param tools 可用工具定义列表
     * @param modelId 指定模型 ID
     * @return 完整回复结果
     */
    suspend fun completeTurn(
        messages: List<ChatMessage>,
        tools: List<Map<String, Any>>? = null,
        modelId: String? = null
    ): LlmTurnResult

    /**
     * 获取当前可用的模型列表
     */
    fun getAvailableModels(): List<LlmModelInfo>

    /**
     * 获取模型名称（用于日志和调试）
     */
    fun getModelDisplayName(modelId: String): String
}

/**
 * LLM 单轮调用结果
 */
data class LlmTurnResult(
    /** 累积的完整文本内容（如有） */
    val content: String,
    /** 工具调用列表（如有） */
    val toolCalls: List<ToolCall> = emptyList(),
    /** 终止原因 */
    val finishReason: String? = null,
    /** 使用的模型 ID */
    val modelId: String? = null,
    /** Token 使用量 */
    val usage: LlmTokenUsage? = null
)

/**
 * LLM 模型信息
 */
data class LlmModelInfo(
    val id: String,              // 模型 ID，如 "gpt-4o-mini"
    val displayName: String,     // 显示名称，如 "GPT-4o Mini"
    val tier: ModelTier,         // 模型层级
    val maxTokens: Int = 4096,   // 最大输出 Token
    val isDefault: Boolean = false
)

/**
 * 模型层级 —— 用于分层路由策略
 */
enum class ModelTier {
    /** 轻量级：快速、便宜，用于简单检查（如格式校验、答案比对） */
    LIGHT,

    /** 标准级：性价比平衡，用于日常做题和答疑 */
    STANDARD,

    /** 高级：推理能力强，用于复杂讲解和出题 */
    ADVANCED
}
