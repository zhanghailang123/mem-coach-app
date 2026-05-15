package cn.com.memcoach.agent

/**
 * 学习状态机 —— 管理 Agent 的 7 个学习状态及各状态的 Prompt 和工具配置。
 *
 * 状态说明：
 * - IDLE      初始状态，等待用户指令
 * - BROWSE    浏览真题库，用户自由探索
 * - PRACTICE  逐题练习模式，Agent 主动出题并检查答案
 * - EXPLAIN   深度讲解模式，Agent 详细解析题目推理链
 * - EXTEND    延伸学习模式，基于当前知识点推荐变式题和关联知识
 * - REVIEW    错题回顾模式，聚焦薄弱点进行针对性练习
 * - MOCK      模拟考试模式，计时组卷
 *
 * 设计借鉴：OpenOmniBot StateMachine 的状态定义和转换回调机制。
 * 每个状态包含：System Prompt 片段、允许的工具集合、状态转换规则。
 */
class StudyStateMachine {

    /** 7 个学习状态枚举 */
    enum class State {
        IDLE,
        BROWSE,
        PRACTICE,
        EXPLAIN,
        EXTEND,
        REVIEW,
        MOCK
    }

    /** 当前状态 */
    var currentState: State = State.IDLE
        private set

    /** 状态变更监听器列表 */
    private val listeners = mutableListOf<StateChangeListener>()

    /** 状态上下文（携带当前题目、知识点等信息） */
    var context: StateContext = StateContext()
        private set

    /** 状态变更监听器接口 */
    interface StateChangeListener {
        fun onStateChanged(from: State, to: State, context: StateContext)
    }

    /** 状态上下文 —— 携带当前学习状态中的上下文信息 */
    data class StateContext(
        /** 当前题目 ID */
        val currentQuestionId: String? = null,
        /** 当前知识点 ID */
        val currentTopicId: String? = null,
        /** 当前科目 */
        val currentSubject: String? = null,
        /** 练习模式：normal（正常）/ speed（极速3题）/ endless（无限） */
        val practiceMode: String = "normal",
        /** 模拟考试剩余时间（秒），0 表示不限制 */
        val mockTimeRemaining: Int = 0,
        /** 当前轮次 */
        val currentRound: Int = 0,
        /** 总轮次 */
        val totalRounds: Int = 0,
        /** 当前会话正确数 */
        val correctCount: Int = 0,
        /** 扩展数据 */
        val extras: Map<String, String> = emptyMap()
    )

    /** 注册状态变更监听器 */
    fun addListener(listener: StateChangeListener) {
        listeners.add(listener)
    }

    /** 移除状态变更监听器 */
    fun removeListener(listener: StateChangeListener) {
        listeners.remove(listener)
    }

    /** 转换到目标状态，通知所有监听器 */
    fun transition(newState: State, newContext: StateContext? = null): State {
        val from = currentState
        currentState = newState
        newContext?.let { context = it }
        listeners.forEach { it.onStateChanged(from, newState, context) }
        return currentState
    }

    /** 获取当前状态的 Prompt 片段（注入到 AgentSystemPrompt Layer B） */
    fun getStatePrompt(): String = when (currentState) {
        State.IDLE -> buildIdlePrompt()
        State.BROWSE -> buildBrowsePrompt()
        State.PRACTICE -> buildPracticePrompt()
        State.EXPLAIN -> buildExplainPrompt()
        State.EXTEND -> buildExtendPrompt()
        State.REVIEW -> buildReviewPrompt()
        State.MOCK -> buildMockPrompt()
    }

    /** 获取当前状态允许的工具集合 */
    fun getAllowedTools(): Set<String> {
        val pdfTools = setOf("pdf_upload", "pdf_list", "pdf_parse_status", "pdf_ocr_recognize", "pdf_query")
        val stateTools = when (currentState) {
            State.IDLE -> setOf("exam_question_search", "knowledge_search", "knowledge_node_detail", "memorize_query")
            State.BROWSE -> setOf("exam_question_search", "exam_question_explain", "knowledge_search", "knowledge_node_detail", "knowledge_graph_expand")
            State.PRACTICE -> setOf("exam_question_search", "exam_question_explain", "exam_answer_check", "exam_mastery_update", "exam_similar_find")
            State.EXPLAIN -> setOf("exam_question_explain", "exam_answer_check", "exam_similar_find", "knowledge_search", "knowledge_node_detail", "knowledge_graph_expand")
            State.EXTEND -> setOf("exam_similar_find", "exam_question_search", "knowledge_graph_expand", "knowledge_search", "exam_mock_generate")
            State.REVIEW -> setOf("exam_question_search", "exam_question_explain", "exam_answer_check", "exam_mastery_update", "exam_similar_find", "memorize_query", "memorize_record")
            State.MOCK -> setOf("exam_mock_generate", "exam_question_search", "exam_answer_check")
        }
        return stateTools + pdfTools
    }

    /** 根据用户意图推断合适的状态 */
    fun inferState(userMessage: String): State {
        val lower = userMessage.lowercase().trim()
        return when {
            lower.contains("pdf") || lower.contains("document_id") || lower.contains("文档") -> State.BROWSE
            lower.contains("做") && (lower.contains("题") || lower.contains("练习") || lower.contains("练") || lower.contains("刷")) -> State.PRACTICE
            lower.contains("讲解") || lower.contains("解释") || lower.contains("为什么") || lower.contains("怎么") -> State.EXPLAIN
            lower.contains("延伸") || lower.contains("相似") || lower.contains("关联") || lower.contains("变式") -> State.EXTEND
            lower.contains("错题") || lower.contains("回顾") || lower.contains("复习") || lower.contains("薄弱") -> State.REVIEW
            lower.contains("模拟") || lower.contains("考试") || lower.contains("模考") || lower.contains("组卷") -> State.MOCK
            lower.contains("浏览") || lower.contains("查看") || lower.contains("搜索") || lower.contains("找") -> State.BROWSE
            else -> State.IDLE
        }
    }

    /** 重置状态机到 IDLE */
    fun reset() {
        currentState = State.IDLE
        context = StateContext()
    }

    /** 获取状态的可读名称 */
    fun getStateDisplayName(state: State = currentState): String = when (state) {
        State.IDLE -> "\uD83C\uDFE0 教练首页"
        State.BROWSE -> "\uD83D\uDCDA 浏览真题"
        State.PRACTICE -> "\uD83D\uDCDD 逐题练习"
        State.EXPLAIN -> "\uD83D\uDD0D 深度讲解"
        State.EXTEND -> "\uD83D\uDD17 延伸学习"
        State.REVIEW -> "\uD83D\uDD04 错题回顾"
        State.MOCK -> "\uD83E\uDDEA 模拟考试"
    }

    /** 获取状态描述 */
    fun getStateDescription(state: State = currentState): String = when (state) {
        State.IDLE -> "等待用户指令，准备开始学习"
        State.BROWSE -> "自由探索历年真题库"
        State.PRACTICE -> "AI 教练引导的逐题练习"
        State.EXPLAIN -> "深入解析题目推理链和知识点"
        State.EXTEND -> "从当前知识点探索关联内容"
        State.REVIEW -> "聚焦薄弱点的针对性复习"
        State.MOCK -> "限时模拟考试实战"
    }

    // ─── 各状态 Prompt ───

    private fun buildIdlePrompt(): String = "## 当前模式：\uD83C\uDFE0 教练首页\n\n你处于待机状态，等待用户指令。\n\n### 你可以：\n- 主动问候用户，根据学情数据推荐今日学习任务\n- 引导用户选择学习模式（做题/浏览/背诵/模考）\n- 简要总结当前学习进度和薄弱点\n- 回答用户的疑问\n\n### 注意：\n- 保持简短友好\n- 如果用户没有明确意图，推荐他们开始今日练习\n- 鼓励碎片化学习（推荐3-5分钟的极速模式）"

    private fun buildBrowsePrompt(): String = "## 当前模式：\uD83D\uDCDA 浏览真题库\n\n用户正在浏览真题库，探索历年考题。\n\n### 你可以：\n- 根据用户查询搜索真题\n- 展示真题的题干（不带答案，除非用户明确要求）\n- 提供真题来源信息（年份、真题编号）\n- 建议相似题或相关知识点\n\n### 注意：\n- 不要直接给出答案，除非用户明确要求\n- 如果用户表现出想做题的意图，建议切换到练习模式\n- 强调真题来源，建立信任"

    private fun buildPracticePrompt(): String = "## 当前模式：\uD83D\uDCDD 逐题练习\n\n你正在引导用户进行逐题练习。当前进度：第 ${context.currentRound + 1}/${context.totalRounds} 题。\n\n### 核心流程：\n1. **出题**：使用 exam_question_search 获取一道题目\n2. **等待作答**：展示题目但不给答案，等待用户作答\n3. **检查答案**：使用 exam_answer_check 比对用户答案\n4. **反馈**：正确则肯定并简要总结；错误则分析错因并展示推理链\n5. **更新掌握度**：使用 exam_mastery_update 记录学习效果\n6. **推荐变式**：如果用户连续错误，推荐变式题练习\n\n### 注意：\n- 每道题标注来源年份和真题编号\n- 做题后给出掌握度变化反馈\n- 如果用户连续3题正确，主动询问是否升级难度\n- 如果用户连续错误，建议切换到讲解模式"

    private fun buildExplainPrompt(): String = "## 当前模式：\uD83D\uDD0D 深度讲解\n\n你正在对题目进行深度讲解，帮助用户理解解题思路和知识点。\n\n### 核心流程：\n1. **获取题目详情**：使用 exam_question_explain 获取完整题目信息\n2. **推理链分析**：展示推理步骤\n3. **知识点关联**：使用 knowledge_search 查找相关知识点\n4. **易错点提醒**：根据用户历史学习记录，提示常见错误\n5. **变式推荐**：使用 exam_similar_find 推荐变式题巩固\n\n### 反思要求：\n- 讲解完每个步骤后，询问用户是否理解\n- 如果用户表示困惑，换一个角度重新讲解\n- 引用真题来源和知识点定义，确保准确性"

    private fun buildExtendPrompt(): String = "## 当前模式：\uD83D\uDD17 延伸学习\n\n你正在帮助用户从当前知识点出发，探索相关联的知识和题目。\n\n### 核心流程：\n1. **确定锚点**：确认当前知识点\n2. **图谱展开**：使用 knowledge_graph_expand 查看知识结构\n3. **关联推荐**：使用 exam_similar_find 推荐相关真题\n4. **变式练习**：出不同角度但同知识点的题目\n\n### 注意：\n- 延伸范围不要过大，每次聚焦1-2个方向\n- 用知识图谱可视化说明知识点间的关系"

    private fun buildReviewPrompt(): String = "## 当前模式：\uD83D\uDD04 错题回顾\n\n你正在帮助用户回顾错题，聚焦薄弱点进行针对性练习。\n\n### 核心流程：\n1. **获取薄弱点**：根据用户掌握度数据，确定需要回顾的知识点\n2. **搜索错题**：使用 exam_question_search 按 topic 搜索真题\n3. **重新练习**：按顺序出题，检查答案\n4. **强化记忆**：对反复出错的知识点，使用 memorize_query 加入背诵清单\n5. **更新进度**：使用 exam_mastery_update 更新掌握度\n\n### 注意：\n- 优先回顾正确率 < 60% 的知识点\n- 每个薄弱点至少练习3道相关题\n- 鼓励用户：进步再小也要肯定"

    private fun buildMockPrompt(): String = "## 当前模式：\uD83E\uDDEA 模拟考试\n\n用户正在进行模拟考试。${if (context.mockTimeRemaining > 0) "剩余时间：${context.mockTimeRemaining / 60} 分钟。" else ""}\n\n### 核心流程：\n1. **组卷**：使用 exam_mock_generate 按约束抽取题目\n2. **计时**：告知用户总题数和时间限制\n3. **逐题展示**：不提供即时反馈，让用户独立完成\n4. **交卷分析**：统计正确率，分析各知识点得分，给出薄弱点诊断\n\n### 严格规则：\n- 考试过程中不要给出任何提示或讲解\n- 用户提交全部答案后再检查\n- 考试结束后提供完整的分析报告\n- 模拟考试可以提前交卷"
}
