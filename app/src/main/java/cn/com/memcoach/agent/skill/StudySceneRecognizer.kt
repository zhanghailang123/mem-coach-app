package cn.com.memcoach.agent.skill

import cn.com.memcoach.agent.AgentPromptContext

/**
 * 学习场景识别器
 * 
 * 基于用户消息内容和学习上下文，识别当前的学习场景类型
 * 用于 Skill 匹配和激活
 */
class StudySceneRecognizer {
    
    companion object {
        // 场景识别的关键词映射
        private val SCENE_KEYWORDS = mapOf(
            StudyScene.PROBLEM_SOLVING to listOf(
                "做题", "解题", "题目", "不会", "怎么做", "解答", "答案", "选什么", "哪个",
                "帮我做", "帮我解", "这道题", "一道题", "练习", "习题", "例题"
            ),
            StudyScene.CONCEPT_EXPLAIN to listOf(
                "讲解", "解释", "什么是", "原理", "概念", "定义", "含义", "意思",
                "怎么理解", "如何理解", "是什么", "啥意思", "啥叫"
            ),
            StudyScene.ERROR_ANALYSIS to listOf(
                "错", "错误", "为什么错", "做错", "分析", "错因", "错在哪里",
                "为什么不对", "哪里错了", "分析错误", "错题"
            ),
            StudyScene.REVIEW_PLANNING to listOf(
                "计划", "规划", "安排", "复习", "备考", "学习计划", "复习计划",
                "怎么复习", "如何备考", "时间安排", "进度"
            ),
            StudyScene.MEMORIZATION to listOf(
                "背", "记忆", "公式", "口诀", "背诵", "记住", "默写",
                "怎么记", "如何背", "记忆方法", "背诵方法"
            ),
            StudyScene.MOCK_EXAM to listOf(
                "模拟", "考试", "测试", "真题", "模拟题", "模拟考试", "模考",
                "出题", "出一套", "练习题", "测试题"
            ),
            StudyScene.WEAKNESS_ANALYSIS to listOf(
                "薄弱", "弱项", "不足", "提高", "弱点", "薄弱点", "短板",
                "哪里弱", "哪些不足", "需要提高", "改进"
            )
        )
        
        // 场景权重（用于优先级排序）
        private val SCENE_WEIGHTS = mapOf(
            StudyScene.PROBLEM_SOLVING to 1.0,  // 默认场景
            StudyScene.CONCEPT_EXPLAIN to 0.9,
            StudyScene.ERROR_ANALYSIS to 0.95,
            StudyScene.REVIEW_PLANNING to 0.85,
            StudyScene.MEMORIZATION to 0.8,
            StudyScene.MOCK_EXAM to 0.88,
            StudyScene.WEAKNESS_ANALYSIS to 0.92
        )
    }
    
    /**
     * 识别用户消息对应的学习场景
     * 
     * @param userMessage 用户消息内容
     * @param context 学习上下文（可选，用于更精确的识别）
     * @return 识别出的学习场景
     */
    fun recognize(userMessage: String, context: AgentPromptContext? = null): StudyScene {
        val message = userMessage.lowercase().trim()
        
        // 如果消息为空，默认返回解题场景
        if (message.isBlank()) {
            return StudyScene.PROBLEM_SOLVING
        }
        
        // 计算每个场景的匹配分数
        val sceneScores = mutableMapOf<StudyScene, Double>()
        
        for ((scene, keywords) in SCENE_KEYWORDS) {
            var score = 0.0
            
            // 关键词匹配
            for (keyword in keywords) {
                if (message.contains(keyword)) {
                    // 关键词长度越长，匹配度越高
                    score += keyword.length.toDouble() / message.length.toDouble() * 2.0
                }
            }
            
            // 应用场景权重
            score *= SCENE_WEIGHTS[scene] ?: 1.0
            
            // 根据上下文调整分数
            if (context != null) {
                score *= calculateContextBoost(scene, context)
            }
            
            sceneScores[scene] = score
        }
        
        // 返回分数最高的场景，如果所有分数都为0，则返回默认场景
        return sceneScores.maxByOrNull { it.value }?.key ?: StudyScene.PROBLEM_SOLVING
    }
    
    /**
     * 批量识别多个消息的场景（用于历史分析）
     * 
     * @param messages 消息列表
     * @param context 学习上下文
     * @return 场景分布统计
     */
    fun recognizeBatch(messages: List<String>, context: AgentPromptContext? = null): Map<StudyScene, Int> {
        val distribution = mutableMapOf<StudyScene, Int>()
        
        for (message in messages) {
            val scene = recognize(message, context)
            distribution[scene] = (distribution[scene] ?: 0) + 1
        }
        
        return distribution
    }
    
    /**
     * 根据上下文计算场景加成
     * 
     * @param scene 场景类型
     * @param context 学习上下文
     * @return 加成系数（0.5 - 2.0）
     */
    private fun calculateContextBoost(scene: StudyScene, context: AgentPromptContext): Double {
        var boost = 1.0
        
        when (scene) {
            StudyScene.ERROR_ANALYSIS -> {
                // 如果用户最近正确率较低，错题分析场景加成
                val correctRate = context.learningContext?.correctRate ?: 0.5f
                if (correctRate < 0.6f) {
                    boost *= 1.5
                }
            }
            StudyScene.WEAKNESS_ANALYSIS -> {
                // 如果用户有明确的薄弱点，薄弱点分析场景加成
                if (context.weakPoints.isNotEmpty()) {
                    boost *= 1.3
                }
            }
            StudyScene.MEMORIZATION -> {
                // 如果有待背诵内容，背诵场景加成
                if (context.memorizedItems.isNotEmpty()) {
                    boost *= 1.4
                }
            }
            StudyScene.REVIEW_PLANNING -> {
                // 如果连续学习天数较多，复习规划场景加成
                val streak = context.learningContext?.studyStreakDays ?: 0
                if (streak > 7) {
                    boost *= 1.2
                }
            }
            else -> {
                // 其他场景无特殊加成
            }
        }
        
        return boost.coerceIn(0.5, 2.0)
    }
    
    /**
     * 获取场景的中文显示名称
     * 
     * @param scene 场景类型
     * @return 中文名称
     */
    fun getSceneDisplayName(scene: StudyScene): String {
        return when (scene) {
            StudyScene.PROBLEM_SOLVING -> "解题模式"
            StudyScene.CONCEPT_EXPLAIN -> "概念讲解"
            StudyScene.ERROR_ANALYSIS -> "错题分析"
            StudyScene.REVIEW_PLANNING -> "复习规划"
            StudyScene.MEMORIZATION -> "背诵辅助"
            StudyScene.MOCK_EXAM -> "模拟考试"
            StudyScene.WEAKNESS_ANALYSIS -> "薄弱点分析"
        }
    }
    
    /**
     * 获取场景的图标（用于 UI 显示）
     * 
     * @param scene 场景类型
     * @return 图标名称（可映射到 Flutter Icons）
     */
    fun getSceneIcon(scene: StudyScene): String {
        return when (scene) {
            StudyScene.PROBLEM_SOLVING -> "edit_note"
            StudyScene.CONCEPT_EXPLAIN -> "school"
            StudyScene.ERROR_ANALYSIS -> "error_outline"
            StudyScene.REVIEW_PLANNING -> "calendar_today"
            StudyScene.MEMORIZATION -> "psychology"
            StudyScene.MOCK_EXAM -> "quiz"
            StudyScene.WEAKNESS_ANALYSIS -> "analytics"
        }
    }
}