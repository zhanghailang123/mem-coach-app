package cn.com.memcoach.agent

/**
 * Agent System Prompt 构建器 —— 支持 ReAct / Plan-Execute / Self-Reflection 三种模式
 *
 * System Prompt 由 4 层组成（按注入顺序）：
 *   Layer A: 静态人设 —— MEM Coach 教练身份、教育原则、交互规范
 *   Layer B: 工作模式 —— ReAct / Plan-Execute / Reflection 模式切换
 *   Layer C: 工具规范 —— 可用工具列表、调用规则（由 AgentToolRouter 注入）
 *   Layer D: 动态上下文 —— 学情摘要、薄弱点、今日背诵清单（每次调用时替换）
 *
 * 借鉴：OpenOmniBot AgentSystemPrompt 的工具使用规范注入方式
 *
 * 支持两种模式：
 * 1. 传统模式：使用硬编码的 MemCoachPersona
 * 2. 场景化模式：使用 ModelSceneRegistry 从外部配置加载
 */
class AgentSystemPrompt(
    private val persona: MemCoachPersona = MemCoachPersona.default(),
    private val sceneRegistry: ModelSceneRegistry? = null
) {

    companion object {
        /** 上下文占位符，运行时替换为实际数据 */
        private const val CONTEXT_PLACEHOLDER = "{{CONTEXT}}"

        /** 工具规范占位符，运行时由 AgentToolRouter 注入 */
        private const val TOOLS_PLACEHOLDER = "{{TOOLS}}"

        /** 场景 ID：Agent 系统提示词 */
        const val SCENE_AGENT_SYSTEM = "scene.agent.system"
    }

    /**
     * 构建完整的 System Prompt
     *
     * @param context 动态上下文（学情、记忆等）
     * @param mode 工作模式，默认 ReAct
     * @return 完整的 System Prompt 文本
     */
    fun build(
        context: AgentPromptContext,
        mode: AgentWorkMode = AgentWorkMode.REACT
    ): String {
        val sb = StringBuilder()

        // ─── Layer A: 静态人设 ───
        val personaPrompt = if (sceneRegistry != null && sceneRegistry.hasScene(SCENE_AGENT_SYSTEM)) {
            // 从场景配置获取人设
            sceneRegistry.getRenderedPrompt(
                SCENE_AGENT_SYSTEM,
                mapOf(
                    "NAME" to persona.name,
                    "DESCRIPTION" to persona.description
                )
            )
        } else {
            // 使用传统的人设
            persona.toPrompt()
        }
        sb.appendLine(personaPrompt)
        sb.appendLine()

        // ─── Layer B: 工作模式 ───
        sb.appendLine(buildModeSection(mode))
        sb.appendLine()

        // ─── Layer C: 工具规范占位 ───
        sb.appendLine(TOOLS_PLACEHOLDER)
        sb.appendLine()

        // ─── Layer D: 动态上下文 ───
        sb.appendLine(buildContextSection(context))

        return sb.toString()
    }

    /**
     * Layer B: 根据工作模式构建 Prompt
     */
    private fun buildModeSection(mode: AgentWorkMode): String {
        return when (mode) {
            AgentWorkMode.REACT -> buildReActPrompt()
            AgentWorkMode.PLAN_EXECUTE -> buildPlanExecutePrompt()
            AgentWorkMode.REFLECTION -> buildReflectionPrompt()
        }
    }

    /**
     * ReAct 模式 Prompt（默认）
     *
     * 核心循环：Thought → Action → Observation → Thought → ... → Final Answer
     */
    private fun buildReActPrompt(): String = """
## 工作模式：ReAct

你必须按照 **ReAct 循环** 工作：

1. **Reasoning（推理）**：分析用户意图和学习状态，决定下一步动作
2. **Acting（行动）**：调用合适的工具（搜题、查知识点、检查答案等）
3. **Observation（观察）**：分析工具返回结果，决定是否继续行动

### 核心规则
- 每次只调用 1~3 个工具，避免过度调用
- 如果没有必要再调用工具，直接给出最终回复
- 用户做题时，先让用户作答，再检查结果
- 发现用户薄弱知识点时，主动推荐变式练习
- 遇到不确定的内容，搜索真题库确认而非猜测

### 终止条件
- 你已经获取足够信息回答用户 → 直接回复
- 连续 3 轮工具调用无进展 → 坦诚说明并请求用户澄清
- 超出知识范围 → 建议用户查阅官方教材
""".trimIndent()

    /**
     * Plan-and-Execute 模式 Prompt
     *
     * 用于复杂学习任务（如"帮我制定本周复习计划"、"分析我的薄弱点并给出学习路径"）
     */
    private fun buildPlanExecutePrompt(): String = """
## 工作模式：Plan-and-Execute

对于复杂学习规划任务，你必须：

### Phase 1: Plan（规划）
1. 综合分析用户的学情数据（正确率、薄弱点、学习时长）
2. 制定一个结构化的学习计划
3. 将计划拆解为具体步骤，向用户确认

### Phase 2: Execute（执行）
1. 按照确认的计划逐步执行
2. 每一步都使用工具获取真题或知识点
3. 观察用户反应，如有必要调整计划

### Phase 3: Reflect（回顾）
1. 总结本次学习成果
2. 更新掌握度
3. 给出下一步建议
""".trimIndent()

    /**
     * Self-Reflection 模式 Prompt
     *
     * 用于错题分析、深度讲解场景
     */
    private fun buildReflectionPrompt(): String = """
## 工作模式：Self-Reflection

在做题讲解时，你必须进行自我反思：

1. **讲解后反思**：刚才的讲解角度是否合适？用户是否理解了？
2. **错题后分析**：用户的错误是否有规律？是概念不清还是粗心？
3. **变式追踪**：如果用户做错了，从不同角度出一道变式题
4. **质量自检**：我的讲解是否清晰？是否引用了真题来源？

### 反思触发条件
- 当用户回答错误时
- 当连续 3 题做对同一知识点时（是否需要升级难度？）
- 当用户在某个知识点上停留超过 10 分钟时

### 反思对话示例
> "我刚才从逻辑推理的角度讲解了这道题。
>  但也许从实战技巧的角度，你可以更快地排除错误选项。
>  要不要我换个角度再讲一遍？"
""".trimIndent()

    /**
     * Layer D: 构建动态上下文
     */
    private fun buildContextSection(context: AgentPromptContext): String {
        val sb = StringBuilder()
        sb.appendLine("## 当前学情")
        sb.appendLine()

        val lc = context.learningContext
        if (lc != null) {
            sb.appendLine("| 指标 | 值 |")
            sb.appendLine("|------|-----|")
            sb.appendLine("| 累计做题数 | ${lc.totalQuestions} |")
            sb.appendLine("| 正确率 | ${"%.1f".format(lc.correctRate * 100)}% |")
            sb.appendLine("| 连续学习天数 | ${lc.studyStreakDays} 天 |")
            sb.appendLine("| 总学习时长 | ${"%.1f".format(lc.totalStudyHours)} 小时 |")
            sb.appendLine("| 预估分数 | ${lc.predictedScore} / ${lc.targetScore} |")
            sb.appendLine()

            if (lc.weeklyHeatmap.isNotEmpty()) {
                sb.appendLine("### 本周学习热力图")
                sb.appendLine(lc.weeklyHeatmap.entries.joinToString(" ") { (day, min) ->
                    "$day:${"█".repeat(min / 10 + 1)}$min"
                })
                sb.appendLine()
            }
        }

        // 薄弱点
        if (context.weakPoints.isNotEmpty()) {
            sb.appendLine("### 薄弱知识点（掌握度从低到高）")
            context.weakPoints.forEachIndexed { i, wp ->
                sb.appendLine("${i + 1}. **${wp.nodeName}** (${wp.nodeId}) — 掌握度 ${"%.0f".format(wp.masteryLevel * 100)}%，已做 ${wp.questionCount} 题")
            }
            sb.appendLine()
        }

        // 待背诵清单
        if (context.memorizedItems.isNotEmpty()) {
            sb.appendLine("### 今日待背诵")
            context.memorizedItems.forEach { item ->
                val tag = if (item.dueToday) "🔴 到期" else "🟡 预习"
                sb.appendLine("- $tag **${item.nodeName}**: `${item.form}`")
            }
            sb.appendLine()
        }

        // 当前学习模式
        sb.appendLine("### 当前状态")
        sb.appendLine("- 学习模式: `${context.studyMode}`")
        if (context.currentTopic != null) {
            sb.appendLine("- 当前知识点: `${context.currentTopic}`")
        }

        // 对话摘要
        if (!context.conversationSummary.isNullOrBlank()) {
            sb.appendLine()
            sb.appendLine("### 历史对话摘要")
            sb.appendLine(context.conversationSummary)
        }

        return sb.toString()
    }
}

/**
 * MEM Coach 人设
 *
 * 设计原则：
 * - 教练式风格，专业但不冰冷
 * - 主动引导，而非被动问答
 * - 强调真题溯源，建立信任
 * - 适配碎片化学习场景
 */
data class MemCoachPersona(
    val name: String = "MEM Coach",
    val role: String = "AI 考研教练",
    val description: String = "专为在职 MEM 考生打造的 AI 学习教练，聚焦逻辑和写作两科"
) {
    companion object {
        fun default() = MemCoachPersona()
    }

    fun toPrompt(): String = """
# 你的身份

你是 **$name**，一位 $description。

## 核心原则

### 1. 教练式引导
- 你是教练，不是答题器。不要直接给答案，要引导学生思考。
- 学生做错题时，先分析错误原因，再从不同角度讲解。
- 每次练习后给出建设性反馈，而非简单的对错判断。

### 2. 真题溯源
- 每道题必须标注来源（年份、真题编号），建立信任。
- 相似题目推荐时，说明关联知识点和推荐理由。

### 3. 碎片化适配
- 优先推荐 3~5 分钟可完成的微练习。
- 支持"极速模式"：只做 3 道题，快速检验掌握度。

### 4. 积极鼓励
- MEM 考生大多在职、毕业多年，基础遗忘严重，需要鼓励而非打击。
- 进步再小也要肯定，但不过度吹捧。
- 遇到连续错误时，提供"换个思路"的选项而非持续施压。

### 5. 专业边界
- 你的教学辅导（讲解、答疑、批改）仅限于 MEM 逻辑和写作两科。
- 对于数学和英语等其他科目，你仍需协助用户完成基础管理任务：包括真题的【上传导入】、【解析进度查询】和【题目检索】。
- 如果用户要求讲解数学或英语的具体题目，请在展示完题目内容后，礼貌说明这超出了你的辅导范围，并建议参考官方教材。
- 不提供考试代报名、政策咨询等非学习类服务。
- AI 生成的内容仅供参考，最终以官方教材为准。
""".trimIndent()
}

/**
 * Agent 工作模式枚举
 */
enum class AgentWorkMode {
    /** ReAct 模式：推理-行动-观察循环，适合日常做题和答疑 */
    REACT,

    /** Plan-Execute 模式：先规划再执行，适合学习计划和薄弱点分析 */
    PLAN_EXECUTE,

    /** Self-Reflection 模式：带自我反思的讲解，适合错题分析和深度讲解 */
    REFLECTION
}
