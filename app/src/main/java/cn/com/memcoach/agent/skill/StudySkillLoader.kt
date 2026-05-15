package cn.com.memcoach.agent.skill

import cn.com.memcoach.agent.AgentTraceLogger

/**
 * 学习 Skill 加载器
 * 
 * 负责加载 Skill 内容，并将其格式化为可注入到 system prompt 的文本
 * 支持内置 Skill 和用户自定义 Skill
 */
class StudySkillLoader {
    
    companion object {
        /** Skill 内容的最大长度（字符数） */
        private const val MAX_SKILL_CONTENT_LENGTH = 1500
        
        /** Skill 指令的截断后缀 */
        private const val TRUNCATION_SUFFIX = "\n\n[... 内容已截断，完整内容请查看 Skill 详情]"
    }
    
    /**
     * 加载 Skill 指令内容
     * 
     * @param skill 要加载的 Skill
     * @return 格式化后的指令文本
     */
    fun loadInstructions(skill: StudySkill): String {
        val traceId = AgentTraceLogger.newTraceId("skill_load")
        val content = skill.instructions
        AgentTraceLogger.event(
            "skill_load_start",
            mapOf(
                "trace_id" to traceId,
                "skill_id" to skill.id,
                "skill_name" to skill.name,
                "enabled" to skill.isEnabled,
                "builtin" to skill.isBuiltin,
                "priority" to skill.priority,
                "instructions_length" to content.length,
                "supported_scenes" to skill.supportedScenes.map { it.name },
                "tool_preferences" to skill.toolPreferences
            )
        )
        
        // 如果内容为空，返回空字符串
        if (content.isBlank()) {
            AgentTraceLogger.event(
                "skill_load_empty",
                mapOf(
                    "trace_id" to traceId,
                    "skill_id" to skill.id,
                    "skill_name" to skill.name
                )
            )
            return ""
        }
        
        // 截断过长的内容
        val truncatedContent = if (content.length > MAX_SKILL_CONTENT_LENGTH) {
            content.take(MAX_SKILL_CONTENT_LENGTH) + TRUNCATION_SUFFIX
        } else {
            content
        }
        
        // 格式化为 system prompt 片段
        val formatted = formatSkillForPrompt(skill, truncatedContent)
        AgentTraceLogger.event(
            "skill_load_success",
            mapOf(
                "trace_id" to traceId,
                "skill_id" to skill.id,
                "skill_name" to skill.name,
                "truncated" to (content.length > MAX_SKILL_CONTENT_LENGTH),
                "formatted_length" to formatted.length,
                "formatted_preview" to formatted
            )
        )
        return formatted
    }
    
    /**
     * 批量加载多个 Skill 的指令
     * 
     * @param skills Skill 列表
     * @return 格式化后的指令文本（合并）
     */
    fun loadMultipleInstructions(skills: List<StudySkill>): String {
        if (skills.isEmpty()) {
            return ""
        }
        
        return skills.joinToString("\n\n---\n\n") { skill ->
            loadInstructions(skill)
        }
    }
    
    /**
     * 格式化 Skill 为 system prompt 片段
     * 
     * @param skill Skill 对象
     * @param content Skill 内容
     * @return 格式化后的文本
     */
    private fun formatSkillForPrompt(skill: StudySkill, content: String): String {
        val sb = StringBuilder()
        
        // Skill 标题
        sb.appendLine("## 学习策略：${skill.name}")
        sb.appendLine()
        
        // Skill 描述
        if (skill.description.isNotBlank()) {
            sb.appendLine("**策略说明**：${skill.description}")
            sb.appendLine()
        }
        
        // 支持的场景
        val sceneNames = skill.supportedScenes.map { scene ->
            when (scene) {
                StudyScene.PROBLEM_SOLVING -> "解题"
                StudyScene.CONCEPT_EXPLAIN -> "讲解"
                StudyScene.ERROR_ANALYSIS -> "错题分析"
                StudyScene.REVIEW_PLANNING -> "复习规划"
                StudyScene.MEMORIZATION -> "背诵"
                StudyScene.MOCK_EXAM -> "模拟考试"
                StudyScene.WEAKNESS_ANALYSIS -> "薄弱点分析"
            }
        }
        sb.appendLine("**适用场景**：${sceneNames.joinToString("、")}")
        sb.appendLine()
        
        // 工具偏好
        if (skill.toolPreferences.isNotEmpty()) {
            sb.appendLine("**推荐工具**：${skill.toolPreferences.joinToString("、") { "`$it`" }}")
            sb.appendLine()
        }
        
        // 核心指令
        sb.appendLine("**核心指令**：")
        sb.appendLine(content)
        
        return sb.toString()
    }
    
    /**
     * 加载 Skill 的摘要信息（用于 UI 展示）
     * 
     * @param skill Skill 对象
     * @return 摘要文本
     */
    fun loadSummary(skill: StudySkill): String {
        val sb = StringBuilder()
        
        sb.appendLine("### ${skill.name}")
        sb.appendLine()
        
        if (skill.description.isNotBlank()) {
            sb.appendLine(skill.description)
            sb.appendLine()
        }
        
        val sceneNames = skill.supportedScenes.map { scene ->
            when (scene) {
                StudyScene.PROBLEM_SOLVING -> "解题"
                StudyScene.CONCEPT_EXPLAIN -> "讲解"
                StudyScene.ERROR_ANALYSIS -> "错题分析"
                StudyScene.REVIEW_PLANNING -> "复习规划"
                StudyScene.MEMORIZATION -> "背诵"
                StudyScene.MOCK_EXAM -> "模拟考试"
                StudyScene.WEAKNESS_ANALYSIS -> "薄弱点分析"
            }
        }
        sb.appendLine("**适用场景**：${sceneNames.joinToString("、")}")
        sb.appendLine("**优先级**：${skill.priority}/10")
        sb.appendLine("**状态**：${if (skill.isEnabled) "已启用" else "已禁用"}")
        
        return sb.toString()
    }
    
    /**
     * 加载 Skill 的详细信息（用于详情页面）
     * 
     * @param skill Skill 对象
     * @return 详细信息文本
     */
    fun loadDetails(skill: StudySkill): String {
        val sb = StringBuilder()
        
        sb.appendLine("# ${skill.name}")
        sb.appendLine()
        sb.appendLine("## 基本信息")
        sb.appendLine("- **ID**：${skill.id}")
        sb.appendLine("- **描述**：${skill.description}")
        sb.appendLine("- **优先级**：${skill.priority}/10")
        sb.appendLine("- **类型**：${if (skill.isBuiltin) "内置" else "用户自定义"}")
        sb.appendLine("- **状态**：${if (skill.isEnabled) "已启用" else "已禁用"}")
        sb.appendLine()
        
        sb.appendLine("## 支持场景")
        skill.supportedScenes.forEach { scene ->
            val sceneName = when (scene) {
                StudyScene.PROBLEM_SOLVING -> "解题模式"
                StudyScene.CONCEPT_EXPLAIN -> "概念讲解"
                StudyScene.ERROR_ANALYSIS -> "错题分析"
                StudyScene.REVIEW_PLANNING -> "复习规划"
                StudyScene.MEMORIZATION -> "背诵辅助"
                StudyScene.MOCK_EXAM -> "模拟考试"
                StudyScene.WEAKNESS_ANALYSIS -> "薄弱点分析"
            }
            sb.appendLine("- $sceneName")
        }
        sb.appendLine()
        
        if (skill.toolPreferences.isNotEmpty()) {
            sb.appendLine("## 推荐工具")
            skill.toolPreferences.forEach { tool ->
                sb.appendLine("- `$tool`")
            }
            sb.appendLine()
        }
        
        if (skill.successPatterns.isNotEmpty()) {
            sb.appendLine("## 成功模式")
            skill.successPatterns.forEach { pattern ->
                sb.appendLine("- $pattern")
            }
            sb.appendLine()
        }
        
        if (skill.failurePatterns.isNotEmpty()) {
            sb.appendLine("## 失败模式")
            skill.failurePatterns.forEach { pattern ->
                sb.appendLine("- $pattern")
            }
            sb.appendLine()
        }
        
        sb.appendLine("## 核心指令")
        sb.appendLine()
        sb.appendLine(skill.instructions)
        
        return sb.toString()
    }
    
    /**
     * 从文件加载 Skill 内容（用于用户自定义 Skill）
     * 
     * @param filePath 文件路径
     * @return Skill 内容，如果加载失败返回 null
     */
    fun loadFromFile(filePath: String): String? {
        return try {
            val file = java.io.File(filePath)
            if (file.exists() && file.isFile) {
                file.readText()
            } else {
                null
            }
        } catch (e: Exception) {
            null
        }
    }
    
    /**
     * 解析 Skill 文件内容
     * 
     * @param content 文件内容
     * @return 解析后的 Skill 数据，如果解析失败返回 null
     */
    fun parseSkillFile(content: String): StudySkill? {
        // 简单的 Markdown frontmatter 解析
        val lines = content.lines()
        if (lines.isEmpty() || lines[0].trim() != "---") {
            return null
        }
        
        val frontmatterEnd = lines.drop(1).indexOf("---") + 1
        if (frontmatterEnd <= 0) {
            return null
        }
        
        val frontmatterLines = lines.subList(1, frontmatterEnd)
        val bodyLines = lines.subList(frontmatterEnd + 1, lines.size)
        
        // 解析 frontmatter
        val frontmatter = mutableMapOf<String, String>()
        for (line in frontmatterLines) {
            val colonIndex = line.indexOf(':')
            if (colonIndex > 0) {
                val key = line.substring(0, colonIndex).trim()
                val value = line.substring(colonIndex + 1).trim()
                frontmatter[key] = value
            }
        }
        
        // 提取字段
        val name = frontmatter["name"] ?: return null
        val description = frontmatter["description"] ?: ""
        val scenesStr = frontmatter["scenes"] ?: ""
        val priorityStr = frontmatter["priority"] ?: "5"
        
        // 解析场景
        val scenes = scenesStr.split(",").mapNotNull { sceneStr ->
            when (sceneStr.trim().uppercase()) {
                "PROBLEM_SOLVING" -> StudyScene.PROBLEM_SOLVING
                "CONCEPT_EXPLAIN" -> StudyScene.CONCEPT_EXPLAIN
                "ERROR_ANALYSIS" -> StudyScene.ERROR_ANALYSIS
                "REVIEW_PLANNING" -> StudyScene.REVIEW_PLANNING
                "MEMORIZATION" -> StudyScene.MEMORIZATION
                "MOCK_EXAM" -> StudyScene.MOCK_EXAM
                "WEAKNESS_ANALYSIS" -> StudyScene.WEAKNESS_ANALYSIS
                else -> null
            }
        }
        
        // 解析优先级
        val priority = priorityStr.toIntOrNull() ?: 5
        
        // 提取正文
        val body = bodyLines.joinToString("\n").trim()
        
        return StudySkill(
            id = name.lowercase().replace(Regex("[^a-z0-9]+"), "-"),
            name = name,
            description = description,
            supportedScenes = scenes,
            priority = priority,
            instructions = body,
            isEnabled = true,
            isBuiltin = false
        )
    }
}