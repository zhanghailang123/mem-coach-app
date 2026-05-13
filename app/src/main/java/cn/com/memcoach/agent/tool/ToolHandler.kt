package cn.com.memcoach.agent.tool

/**
 * 工具处理器接口 —— 所有 Agent 工具必须实现此接口。
 *
 * 设计借鉴：OpenOmniBot ToolHandler 接口，保持兼容。
 * 每个 Handler 负责一组相关工具的执行逻辑。
 *
 * 工具执行协议：
 * - 入参：arguments 为 LLM 传入的 JSON 字符串
 * - 出参：JSON 字符串，LLM 可直接解析
 * - 异常：抛出后由 AgentOrchestrator 捕获并格式化 error 消息回传 LLM
 */
interface ToolHandler {
    /** 本 Handler 负责的工具名称集合 */
    val toolNames: Set<String>

    /**
     * 执行工具
     *
     * @param toolName 工具名称（用于一个 Handler 处理多个工具的场景）
     * @param arguments JSON 格式的参数字符串
     * @return JSON 格式的执行结果字符串
     */
    suspend fun execute(toolName: String, arguments: String): String

    /**
     * 获取工具定义（JSON Schema），用于注册到 AgentToolRouter
     */
    fun getDefinitions(): List<ToolDefinition>
}

/**
 * 工具定义 —— 对应 OpenAI 兼容 API 的 tools 参数格式
 *
 * @param name 工具名称
 * @param description 工具描述（LLM 根据此描述决定何时调用）
 * @param parameters JSON Schema 格式的参数定义（序列化后的 JSON 字符串）
 */
data class ToolDefinition(
    val name: String,
    val description: String,
    val parameters: String  // JSON Schema 字符串
) {
    /**
     * 转换为 LLM API 所需的 Map 格式
     */
    fun toMap(): Map<String, Any> = mapOf(
        "type" to "function",
        "function" to mapOf(
            "name" to name,
            "description" to description,
            "parameters" to parameters
        )
    )
}
