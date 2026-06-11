package cn.com.memcoach.agent.subagent

/**
 * 子 Agent 注册表
 */
object SubAgentRegistry {
    private val registry = mutableMapOf<String, SubAgentConfig>()

    fun register(config: SubAgentConfig) {
        registry[config.name] = config
    }

    fun get(name: String): SubAgentConfig? = registry[name]

    fun getAllNames(): Set<String> = registry.keys

    /**
     * 注册预定义专家
     */
    fun registerDefaults() {
        register(createMathTutorConfig())
        register(createEnglishTutorConfig())
        register(createVocabCoachConfig())
    }

    private fun createMathTutorConfig() = SubAgentConfig(
        name = "math-tutor",
        displayName = "数学导师",
        description = "专注于管综数学题讲解（条件充分性、排列组合、几何）",
        systemPrompt = MATH_TUTOR_PROMPT,
        mode = SubAgentMode.LIGHTWEIGHT,
        allowedTools = setOf(
            "exam_question_search",
            "exam_question_explain",
            "exam_similar_find",
            "propose_content_patch"
        )
    )

    private fun createEnglishTutorConfig() = SubAgentConfig(
        name = "english-tutor",
        displayName = "英语导师",
        description = "专注于考研英语讲解（阅读、翻译、作文）",
        systemPrompt = ENGLISH_TUTOR_PROMPT,
        mode = SubAgentMode.LIGHTWEIGHT,
        allowedTools = setOf(
            "exam_question_search",
            "exam_question_explain",
            "propose_content_patch"
        )
    )

    private fun createVocabCoachConfig() = SubAgentConfig(
        name = "vocabulary-coach",
        displayName = "单词管家",
        description = "专注于单词学习和记忆技巧",
        systemPrompt = VOCAB_COACH_PROMPT,
        mode = SubAgentMode.LIGHTWEIGHT,
        allowedTools = setOf(
            "vocabulary_detail",
            "vocabulary_search",
            "save_user_memo",
            "propose_content_patch"
        )
    )

    private const val MATH_TUTOR_PROMPT = """你是管综数学专家导师。

核心能力：
1. 条件充分性判断题（独特题型）
2. 排列组合、概率
3. 几何、解析几何

讲解原则：
- 公式用 LaTeX：行内 \(...\)，块级 \[...\]
- 分步骤讲解
- 对条件充分性题，分别判断条件(1)、(2)、联合充分性

输出 JSON 格式：
{
  "question_type": "条件充分性|求解题",
  "key_concepts": ["知识点"],
  "solution_steps": [{"step": 1, "description": "...", "formula": "..."}],
  "traps": ["易错点"],
  "content_patch_suggestion": "如果发现原解析不清晰，说明需要补充什么"
}"""

    private const val ENGLISH_TUTOR_PROMPT = """你是考研英语二专家导师。

核心能力：
1. 阅读理解（定位、拆解、选项分析）
2. 翻译（断句、关键词）
3. 作文（审题、结构）

输出 JSON 格式：
{
  "question_type": "阅读|翻译|作文",
  "analysis": {
    "key_sentences": ["定位句"],
    "vocabulary": [{"word": "...", "meaning": "..."}]
  },
  "answer_explanation": "...",
  "content_patch_suggestion": "如果发现原解析有误或不够，说明需要改进什么"
}"""

    private const val VOCAB_COACH_PROMPT = """你是单词学习专家。

核心能力：
1. 讲解单词用法
2. 生成记忆技巧
3. 识别易混词

输出 JSON 格式：
{
  "word_analysis": {
    "root_breakdown": "词根拆解",
    "memory_trick": "记忆技巧",
    "confusables": ["易混词"]
  },
  "example_sentences": ["例句"],
  "user_memo_suggestion": "为用户生成的个性化笔记（可选）",
  "content_patch_suggestion": "如果发现原讲解需要补充，说明什么（可选）"
}"""
}
