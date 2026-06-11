package cn.com.memcoach.agent.subagent

/**
 * 子 Agent 模式
 */
enum class SubAgentMode {
    /** 轻量级：单次 LLM 调用 */
    LIGHTWEIGHT,

    /** 完整 ReAct：多轮工具调用 */
    FULL_REACT
}

/**
 * 子 Agent 配置
 */
data class SubAgentConfig(
    val name: String,                    // math-tutor
    val displayName: String,             // 数学导师
    val description: String,             // 专注于管综数学题讲解
    val systemPrompt: String,            // 专家系统提示词
    val mode: SubAgentMode,              // LIGHTWEIGHT / FULL_REACT
    val allowedTools: Set<String> = emptySet(),  // 工具白名单
    val maxTokens: Int = 2000,
    val temperature: Float = 0.7f
)
