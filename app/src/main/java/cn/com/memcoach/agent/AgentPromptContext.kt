package cn.com.memcoach.agent

/**
 * Agent 的 Prompt 上下文 —— 构建 System Prompt 时注入的动态上下文。
 *
 * 设计思路：
 * - 静态部分：在 AgentSystemPrompt 中硬编码（人设、规则、工具规范等）
 * - 动态部分：每次调用时注入最新状态（学情、记忆、学习记录等）
 *
 * @param learningContext 学情摘要，来自近期学习记录
 * @param weakPoints 薄弱知识点列表（按掌握度正序）
 * @param memorizedItems 今日待背知识点
 * @param conversationSummary 历史对话摘要（长对话时用摘要替代原始对话，节省 Token）
 * @param studyMode 当前学习模式（practice/explain/mock/memorize）
 * @param currentTopic 当前关心的知识点（可选）
 */
data class AgentPromptContext(
    val learningContext: LearningContext? = null,
    val weakPoints: List<WeakPoint> = emptyList(),
    val memorizedItems: List<MemorizedItem> = emptyList(),
    val conversationSummary: String? = null,
    val studyMode: String = "practice",
    val currentTopic: String? = null
)

/**
 * 学情摘要
 *
 * @param totalQuestions 累计做题数
 * @param correctRate 正确率（0.0 ~ 1.0）
 * @param studyStreakDays 连续学习天数
 * @param totalStudyHours 总学习时长（小时）
 * @param weeklyHeatmap 本周每日学习分钟数 Map<"Mon" → 45, "Tue" → 0 ...>
 * @param predictedScore 预估分数
 * @param targetScore 目标分数
 */
data class LearningContext(
    val totalQuestions: Int = 0,
    val correctRate: Float = 0f,
    val studyStreakDays: Int = 0,
    val totalStudyHours: Float = 0f,
    val weeklyHeatmap: Map<String, Int> = emptyMap(),
    val predictedScore: Int = 0,
    val targetScore: Int = 170
)

/**
 * 薄弱知识点
 *
 * @param nodeId 知识点 ID
 * @param nodeName 知识点名称
 * @param masteryLevel 掌握度（0.0 ~ 1.0）
 * @param questionCount 相关做题数
 */
data class WeakPoint(
    val nodeId: String,
    val nodeName: String,
    val masteryLevel: Float,
    val questionCount: Int
)

/**
 * 待背诵知识点
 *
 * @param nodeId 知识点 ID
 * @param nodeName 知识点名称
 * @param form 背诵内容（公式/定理/口诀）
 * @param dueToday 今日是否到期
 */
data class MemorizedItem(
    val nodeId: String,
    val nodeName: String,
    val form: String,
    val dueToday: Boolean = true
)
