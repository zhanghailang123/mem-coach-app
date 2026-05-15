package cn.com.memcoach.agent.skill

import cn.com.memcoach.agent.AgentPromptContext

/**
 * 学习 Skill 匹配器
 * 
 * 基于学习场景和用户上下文，匹配最合适的 Skill
 * 实现动态激活和智能推荐
 */
class StudySkillMatcher(
    private val skillRegistry: StudySkillRegistry
) {
    companion object {
        /** 最大匹配 Skill 数量 */
        private const val MAX_MATCHED_SKILLS = 2
        
        /** 最小匹配阈值 */
        private const val MIN_MATCH_THRESHOLD = 0.3
    }
    
    /**
     * 匹配最合适的 Skill
     * 
     * @param scene 识别出的学习场景
     * @param context 学习上下文
     * @return 匹配结果列表，按匹配度降序排列
     */
    fun match(scene: StudyScene, context: AgentPromptContext? = null): List<StudySkillMatchResult> {
        val allSkills = skillRegistry.getAllEnabledSkills()
        
        if (allSkills.isEmpty()) {
            return emptyList()
        }
        
        // 计算每个 Skill 的匹配分数
        val matchResults = allSkills.mapNotNull { skill ->
            val confidence = calculateConfidence(skill, scene, context)
            
            if (confidence >= MIN_MATCH_THRESHOLD) {
                StudySkillMatchResult(
                    skill = skill,
                    confidence = confidence,
                    triggerReason = generateTriggerReason(skill, scene, context)
                )
            } else {
                null
            }
        }
        
        // 按匹配度降序排序，返回前 N 个
        return matchResults
            .sortedByDescending { it.confidence }
            .take(MAX_MATCHED_SKILLS)
    }
    
    /**
     * 批量匹配（用于多个场景）
     * 
     * @param scenes 场景列表
     * @param context 学习上下文
     * @return 每个场景对应的匹配结果
     */
    fun matchBatch(scenes: List<StudyScene>, context: AgentPromptContext? = null): Map<StudyScene, List<StudySkillMatchResult>> {
        return scenes.associateWith { scene ->
            match(scene, context)
        }
    }
    
    /**
     * 计算 Skill 与场景的匹配度
     * 
     * @param skill 学习 Skill
     * @param scene 目标场景
     * @param context 学习上下文
     * @return 匹配置信度（0.0 - 1.0）
     */
    private fun calculateConfidence(
        skill: StudySkill,
        scene: StudyScene,
        context: AgentPromptContext?
    ): Double {
        // 1. 场景匹配度（基础分）
        val sceneScore = skill.calculateSceneMatchScore(scene)
        
        // 2. 上下文适配度
        val contextScore = calculateContextScore(skill, context)
        
        // 3. 工具偏好匹配度
        val toolScore = calculateToolScore(skill, context)
        
        // 综合评分（加权平均）
        val weights = doubleArrayOf(0.6, 0.3, 0.1) // 场景、上下文、工具
        val scores = doubleArrayOf(sceneScore, contextScore, toolScore)
        
        return weights.zip(scores).sumOf { (weight, score) -> weight * score }
    }
    
    /**
     * 计算上下文适配度
     * 
     * @param skill 学习 Skill
     * @param context 学习上下文
     * @return 上下文适配度（0.0 - 1.0）
     */
    private fun calculateContextScore(skill: StudySkill, context: AgentPromptContext?): Double {
        if (context == null) return 0.5
        
        var score = 0.5 // 基础分
        
        when (skill.id) {
            "logic-problem-solving" -> {
                // 如果用户逻辑题正确率低，逻辑解题 Skill 更有价值
                val correctRate = context.learningContext?.correctRate ?: 0.5f
                if (correctRate < 0.7f) {
                    score += 0.3
                }
            }
            "writing-essay-scoring" -> {
                // 如果用户写作相关知识点薄弱，写作 Skill 更有价值
                val hasWritingWeakness = context.weakPoints.any { 
                    it.nodeName.contains("写作") || it.nodeName.contains("论证") 
                }
                if (hasWritingWeakness) {
                    score += 0.4
                }
            }
            "spaced-repetition" -> {
                // 如果有待背诵内容，间隔重复 Skill 更有价值
                if (context.memorizedItems.isNotEmpty()) {
                    score += 0.5
                }
            }
            "weakness-analysis" -> {
                // 如果有明确的薄弱点，薄弱点分析 Skill 更有价值
                if (context.weakPoints.isNotEmpty()) {
                    score += 0.4
                }
            }
        }
        
        return score.coerceIn(0.0, 1.0)
    }
    
    /**
     * 计算工具偏好匹配度
     * 
     * @param skill 学习 Skill
     * @param context 学习上下文
     * @return 工具匹配度（0.0 - 1.0）
     */
    private fun calculateToolScore(skill: StudySkill, context: AgentPromptContext?): Double {
        // 目前简化处理，后续可以根据可用工具进行匹配
        return 0.5
    }
    
    /**
     * 生成触发原因描述
     * 
     * @param skill 匹配到的 Skill
     * @param scene 触发场景
     * @param context 学习上下文
     * @return 触发原因描述
     */
    private fun generateTriggerReason(
        skill: StudySkill,
        scene: StudyScene,
        context: AgentPromptContext?
    ): String {
        val reasons = mutableListOf<String>()
        
        // 场景匹配原因
        when (scene) {
            StudyScene.PROBLEM_SOLVING -> reasons.add("用户请求解题帮助")
            StudyScene.CONCEPT_EXPLAIN -> reasons.add("用户请求概念讲解")
            StudyScene.ERROR_ANALYSIS -> reasons.add("用户请求错题分析")
            StudyScene.REVIEW_PLANNING -> reasons.add("用户请求复习规划")
            StudyScene.MEMORIZATION -> reasons.add("用户请求背诵辅助")
            StudyScene.MOCK_EXAM -> reasons.add("用户请求模拟考试")
            StudyScene.WEAKNESS_ANALYSIS -> reasons.add("用户请求薄弱点分析")
        }
        
        // 上下文匹配原因
        if (context != null) {
            when (skill.id) {
                "logic-problem-solving" -> {
                    val correctRate = context.learningContext?.correctRate ?: 0.5f
                    if (correctRate < 0.7f) {
                        reasons.add("用户逻辑题正确率较低（${"%.0f".format(correctRate * 100)}%）")
                    }
                }
                "spaced-repetition" -> {
                    if (context.memorizedItems.isNotEmpty()) {
                        reasons.add("用户有待背诵内容（${context.memorizedItems.size}项）")
                    }
                }
                "weakness-analysis" -> {
                    if (context.weakPoints.isNotEmpty()) {
                        reasons.add("用户有明确的薄弱点（${context.weakPoints.size}个）")
                    }
                }
            }
        }
        
        return reasons.joinToString("；")
    }
    
    /**
     * 获取推荐的 Skill（用于 UI 展示）
     * 
     * @param scene 学习场景
     * @param context 学习上下文
     * @return 推荐的 Skill 列表（最多 3 个）
     */
    fun getRecommendedSkills(scene: StudyScene, context: AgentPromptContext? = null): List<StudySkill> {
        return match(scene, context)
            .take(3)
            .map { it.skill }
    }
    
    /**
     * 检查是否有可用的 Skill
     * 
     * @param scene 学习场景
     * @return 是否有可用的 Skill
     */
    fun hasAvailableSkills(scene: StudyScene): Boolean {
        return skillRegistry.getAllEnabledSkills().any { skill ->
            scene in skill.supportedScenes
        }
    }
}