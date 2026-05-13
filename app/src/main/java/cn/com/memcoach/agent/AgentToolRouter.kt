package cn.com.memcoach.agent

import cn.com.memcoach.agent.tool.ToolDefinition
import cn.com.memcoach.agent.tool.ToolHandler

/**
 * Agent 工具路由器 —— 注册、发现和执行工具。
 *
 * 设计借鉴：OpenOmniBot AgentToolRouter。
 *
 * 职责：
 * - 注册多个 ToolHandler
 * - 根据工具名路由到对应的 Handler 执行
 * - 汇聚所有已注册工具的定义，供 LLM API 使用
 *
 * 使用方式：
 * ```
 * val router = AgentToolRouter()
 * router.register(ExamToolHandler(questionDao, studyRecordDao, masteryDao))
 * router.register(KnowledgeToolHandler(knowledgeNodeDao, knowledgeEdgeDao))
 * // ...
 * val definitions = router.getToolDefinitions()  // → 传给 LLM API
 * val result = router.execute("exam_question_search", args)  // → 执行工具
 * ```
 */
class AgentToolRouter {
    /** 工具名 → Handler 的映射 */
    private val handlerMap = mutableMapOf<String, ToolHandler>()

    companion object {
        /**
         * 工具定义格式转换：将 ToolDefinition 转换为 LLM API 需要的格式
         */
        fun toToolMap(def: ToolDefinition): Map<String, Any> = mapOf(
            "type" to "function",
            "function" to mapOf(
                "name" to def.name,
                "description" to def.description,
                "parameters" to def.parameters
            )
        )
    }

    /**
     * 注册一个 ToolHandler。
     *
     * Handler 的 toolNames 集合中的每个工具名都会被注册。
     * 如果同一个工具名被多个 Handler 注册，后者覆盖前者（警告）。
     */
    fun register(handler: ToolHandler) {
        for (toolName in handler.toolNames) {
            if (handlerMap.containsKey(toolName)) {
                System.err.println("[AgentToolRouter] WARN: tool '$toolName' 被覆盖，新 Handler 将替换旧的")
            }
            handlerMap[toolName] = handler
        }
    }

    /**
     * 批量注册
     */
    fun registerAll(handlers: List<ToolHandler>) {
        handlers.forEach { register(it) }
    }

    /**
     * 注销一个 Handler（根据 toolNames 移除）
     */
    fun unregister(handler: ToolHandler) {
        for (toolName in handler.toolNames) {
            handlerMap.remove(toolName)
        }
    }

    /**
     * 获取所有已注册工具的定义列表，供 LLM API 调用。
     *
     * @return List<Map<String, Any>> 对应 Chat Completion API 的 tools 参数
     */
    fun getToolDefinitions(): List<Map<String, Any>> {
        // 先去重（同一个 handler 可能注册了多个工具名，但 getDefinitions() 返回所有定义）
        val definitions = mutableListOf<ToolDefinition>()
        val seenNames = mutableSetOf<String>()

        for (handler in handlerMap.values.distinct()) {
            for (def in handler.getDefinitions()) {
                if (seenNames.add(def.name)) {
                    definitions.add(def)
                }
            }
        }

        return definitions.map { toToolMap(it) }
    }

    /**
     * 执行指定的工具。
     *
     * @param toolName LLM 请求的工具名
     * @param arguments JSON 格式的参数字符串
     * @return JSON 格式的结果字符串
     * @throws NoSuchElementException 工具未注册
     */
    suspend fun execute(toolName: String, arguments: String): String {
        val handler = handlerMap[toolName]
            ?: throw NoSuchElementException("工具未注册: $toolName")
        return handler.execute(toolName, arguments)
    }

    /**
     * 安全执行：不抛异常，返回错误 JSON
     */
    suspend fun executeSafe(toolName: String, arguments: String): String {
        return try {
            execute(toolName, arguments)
        } catch (e: Exception) {
            """{"error": "${e.message?.replace("\"", "\\\"")}"}"""
        }
    }

    /**
     * 获取所有已注册的工具名
     */
    fun getRegisteredToolNames(): Set<String> = handlerMap.keys.toSet()

    /**
     * 获取所有已注册的 Handler 数量
     */
    fun getHandlerCount(): Int = handlerMap.values.distinct().count()

    /**
     * 清空所有注册的工具
     */
    fun clear() {
        handlerMap.clear()
    }
}
