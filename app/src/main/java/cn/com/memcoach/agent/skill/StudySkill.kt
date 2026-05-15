package cn.com.memcoach.agent.skill

/**
 * 学习场景枚举
 * 
 * 定义 MEM Coach 中常见的学习场景，用于 Skill 匹配和激活
 */
enum class StudyScene {
    /** 解题场景："这道题怎么做"、"帮我解这道逻辑题" */
    PROBLEM_SOLVING,
    
    /** 概念讲解："什么是假言推理"、"解释一下这个概念" */
    CONCEPT_EXPLAIN,
    
    /** 错题分析："我为什么做错了"、"分析一下这道错题" */
    ERROR_ANALYSIS,
    
    /** 复习规划："帮我制定复习计划"、"安排一下本周复习" */
    REVIEW_PLANNING,
    
    /** 背诵辅助："帮我背诵这个公式"、"记忆这个知识点" */
    MEMORIZATION,
    
    /** 模拟考试："给我出一套模拟题"、"进行一次模拟测试" */
    MOCK_EXAM,
    
    /** 薄弱点分析："我哪里比较薄弱"、"分析我的弱项" */
    WEAKNESS_ANALYSIS
}

/**
 * 学习 Skill 数据模型
 * 
 * 代表一个可激活的学习策略或方法
 * 
 * @param id Skill 唯一标识符，如 "logic-problem-solving"
 * @param name Skill 名称，如 "逻辑解题策略"
 * @param description 简短描述
 * @param supportedScenes 支持的学习场景列表
 * @param priority 优先级（1-10），数值越高优先级越高
 * @param instructions 核心指令，将注入到 system prompt 中
 * @param toolPreferences 偏好使用的工具列表
 * @param successPatterns 成功模式列表（用于学习优化）
 * @param failurePatterns 失败模式列表（用于避免和改进）
 * @param isEnabled 是否启用
 * @param isBuiltin 是否为内置 Skill
 */
data class StudySkill(
    val id: String,
    val name: String,
    val description: String,
    val supportedScenes: List<StudyScene>,
    val priority: Int,
    val instructions: String,
    val toolPreferences: List<String> = emptyList(),
    val successPatterns: List<String> = emptyList(),
    val failurePatterns: List<String> = emptyList(),
    val isEnabled: Boolean = true,
    val isBuiltin: Boolean = true
) {
    /**
     * 检查 Skill 是否兼容当前上下文
     * 
     * @param context 学习上下文（可选）
     * @return 是否兼容
     */
    fun isCompatible(context: Any? = null): Boolean {
        // 基础兼容性检查，子类可以覆盖
        return isEnabled
    }
    
    /**
     * 计算与指定场景的匹配度
     * 
     * @param scene 目标场景
     * @return 匹配度分数（0.0 - 1.0）
     */
    fun calculateSceneMatchScore(scene: StudyScene): Double {
        return if (scene in supportedScenes) {
            // 基础匹配度 + 优先级加成
            0.7 + (priority.toDouble() / 10.0) * 0.3
        } else {
            0.0
        }
    }
}

/**
 * Skill 匹配结果
 * 
 * @param skill 匹配到的 Skill
 * @param confidence 匹配置信度（0.0 - 1.0）
 * @param triggerReason 触发原因描述
 */
data class StudySkillMatchResult(
    val skill: StudySkill,
    val confidence: Double,
    val triggerReason: String
)