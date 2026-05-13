package cn.com.memcoach.agent.tool.handlers

import cn.com.memcoach.agent.tool.ToolDefinition
import cn.com.memcoach.agent.tool.ToolHandler
import cn.com.memcoach.data.dao.KnowledgeNodeDao
import cn.com.memcoach.data.dao.UserMasteryDao
import cn.com.memcoach.data.entity.UserMastery
import org.json.JSONArray
import org.json.JSONObject

/**
 * 记忆工具处理器 —— 提供间隔重复背诵查询、背诵结果记录、知识笔记生成等工具。
 *
 * 覆盖工具：
 * - memorize_query        —— 查询今日待背诵的知识点列表（基于 SM-2 间隔重复排期）
 * - memorize_record       —— 记录背诵结果，更新 SM-2 参数和下次复习时间
 * - memorize_note_generate —— 生成个性化知识笔记（Agent 调用后拼入上下文）
 *
 * SM-2 算法简化版实现：根据用户的回忆质量（0-5）更新难度因子(easeFactor)
 * 和复习间隔(intervalDays)，质量 < 3 则重置复习进度。
 */
class MemoryToolHandler(
    private val userMasteryDao: UserMasteryDao,
    private val knowledgeNodeDao: KnowledgeNodeDao
) : ToolHandler {

    override val toolNames = setOf(
        "memorize_query",
        "memorize_record",
        "memorize_note_generate"
    )

    override suspend fun execute(toolName: String, arguments: String): String {
        return try {
            val args = JSONObject(arguments)
            when (toolName) {
                "memorize_query" -> queryDueItems(args)
                "memorize_record" -> recordMemorization(args)
                "memorize_note_generate" -> generateNote(args)
                else -> errorJson("unknown tool: $toolName")
            }
        } catch (e: Exception) {
            errorJson("execute error: ${e.message?.replace("\"", "'")}")
        }
    }

    override fun getDefinitions(): List<ToolDefinition> = listOf(
        ToolDefinition(
            name = "memorize_query",
            description = "查询今日待背诵的知识点列表。基于 SM-2 间隔重复算法，返回到期需要复习的知识点及其核心内容。",
            parameters = """
{
  "type": "object",
  "properties": {
    "subject": {
      "type": "string",
      "description": "科目过滤：logic/writing/math/english",
      "enum": ["logic", "writing", "math", "english"]
    },
    "limit": {
      "type": "integer",
      "default": 10,
      "description": "返回数量上限"
    }
  }
}
""".trimIndent()
        ),
        ToolDefinition(
            name = "memorize_record",
            description = "记录用户对某个知识点的背诵/回忆结果，更新 SM-2 间隔重复参数和下次复习时间。quality 0-5 表示回忆质量：0=完全忘记，3=勉强想起，5=完美回忆。",
            parameters = """
{
  "type": "object",
  "properties": {
    "knowledge_id": {
      "type": "string",
      "description": "知识点ID，如 logic_conditional_inference"
    },
    "quality": {
      "type": "integer",
      "description": "回忆质量 0-5：0=完全忘记，1-2=部分想起，3=勉强正确，4=基本正确，5=完美",
      "minimum": 0,
      "maximum": 5
    }
  },
  "required": ["knowledge_id", "quality"]
}
""".trimIndent()
        ),
        ToolDefinition(
            name = "memorize_note_generate",
            description = "为指定知识点生成个性化知识笔记上下文。包含知识点定义、用户的易错点（来自学习记录）、相关高频考题。由 Agent 调用后拼入讲解上下文。",
            parameters = """
{
  "type": "object",
  "properties": {
    "topic": {
      "type": "string",
      "description": "知识点名称或ID"
    },
    "include_weakness": {
      "type": "boolean",
      "default": true,
      "description": "是否包含用户的易错点"
    },
    "format": {
      "type": "string",
      "default": "markdown",
      "description": "输出格式：markdown/json"
    }
  },
  "required": ["topic"]
}
""".trimIndent()
        )
    )

    // ─── 工具实现 ───

    /**
     * 查询今日待背诵知识点
     */
    private suspend fun queryDueItems(args: JSONObject): String {
        val now = System.currentTimeMillis()
        val limit = args.optInt("limit", 10)
        val subject = args.optString("subject", null)

        val dueItems = userMasteryDao.getDueForReview(now = now, limit = limit)

        val json = JSONObject()
        val items = JSONArray()

        for (mastery in dueItems) {
            val node = knowledgeNodeDao.getById(mastery.knowledgeId) ?: continue

            // 如果指定了科目，过滤
            if (subject != null && node.subject != subject) continue

            val item = JSONObject()
            item.put("knowledge_id", mastery.knowledgeId)
            item.put("knowledge_name", node.name)
            item.put("subject", node.subject)
            item.put("mastery_level", mastery.masteryLevel)
            item.put("ease_factor", mastery.easeFactor)
            item.put("interval_days", mastery.intervalDays)
            item.put("review_count", mastery.reviewCount)
            item.put("correct_count", mastery.correctCount)
            item.put("last_review_date", mastery.lastReviewDate)
            item.put("next_review_date", mastery.nextReviewDate)
            item.put("due_now", mastery.nextReviewDate <= now)
            item.put("form", node.description ?: "")
            item.put("content", node.content ?: "")
            items.put(item)

            if (items.length() >= limit) break
        }

        json.put("count", items.length())
        json.put("total_due", userMasteryDao.countDueForReview())
        json.put("items", items)
        return json.toString()
    }

    /**
     * 记录背诵结果，更新 SM-2 参数
     * 
     * SM-2 简化算法：
     * - quality < 3: 重置复习进度，间隔设为 1 天
     * - quality >= 3:
     *   - repetitions==0: interval = 1
     *   - repetitions==1: interval = 6
     *   - else: interval = previous_interval * easeFactor
     * - easeFactor: EF' = max(1.3, EF + (0.1 - (5-q) * (0.08 + (5-q) * 0.02)))
     */
    private suspend fun recordMemorization(args: JSONObject): String {
        val knowledgeId = args.optString("knowledge_id", "")
        if (knowledgeId.isBlank()) return errorJson("knowledge_id 必填")
        val quality = args.optInt("quality", -1)
        if (quality !in 0..5) return errorJson("quality 必须是 0-5 的整数")

        val now = System.currentTimeMillis()
        val existing = userMasteryDao.getByUserAndKnowledge(knowledgeId = knowledgeId)

        val node = knowledgeNodeDao.getById(knowledgeId)
            ?: return errorJson("知识点不存在: $knowledgeId")

        // 计算新的 SM-2 参数
        val oldEaseFactor = existing?.easeFactor ?: 2.5f
        val oldInterval = existing?.intervalDays ?: 0
        val oldRepetitions = if (quality >= 3) (existing?.reviewCount ?: 0) else 0

        // 更新难度因子
        val newEaseFactor = maxOf(1.3f, oldEaseFactor + (0.1f - (5 - quality) * (0.08f + (5 - quality) * 0.02f)))

        // 计算新间隔
        val newInterval = if (quality < 3) {
            1  // 忘记，重置为 1 天
        } else {
            when (oldRepetitions) {
                0 -> 1
                1 -> 6
                else -> maxOf(1, (oldInterval * newEaseFactor).toInt())
            }
        }

        // 计算下次复习时间
        val nextReviewDate = now + newInterval * 24L * 60 * 60 * 1000L

        // 计算新掌握度（基于质量映射到 0-1）
        val newMasteryLevel = when (quality) {
            0, 1 -> maxOf(0.1f, (existing?.masteryLevel ?: 0.2f) - 0.2f)
            2 -> maxOf(0.1f, (existing?.masteryLevel ?: 0.2f) - 0.1f)
            3 -> minOf(1f, (existing?.masteryLevel ?: 0.2f) + 0.05f)
            4 -> minOf(1f, (existing?.masteryLevel ?: 0.2f) + 0.1f)
            5 -> minOf(1f, (existing?.masteryLevel ?: 0.2f) + 0.15f)
            else -> existing?.masteryLevel ?: 0.2f
        }

        val updated = UserMastery(
            knowledgeId = knowledgeId,
            masteryLevel = newMasteryLevel,
            reviewCount = (existing?.reviewCount ?: 0) + 1,
            correctCount = (existing?.correctCount ?: 0) + (if (quality >= 3) 1 else 0),
            easeFactor = newEaseFactor,
            intervalDays = newInterval,
            lastReviewDate = now,
            nextReviewDate = nextReviewDate,
            updatedAt = now
        )
        userMasteryDao.upsert(updated)

        val json = JSONObject()
        json.put("updated", true)
        json.put("knowledge_id", knowledgeId)
        json.put("knowledge_name", node.name)
        json.put("quality", quality)
        json.put("mastery_level", newMasteryLevel)
        json.put("ease_factor", newEaseFactor)
        json.put("interval_days", newInterval)
        json.put("next_review_date", nextReviewDate)
        json.put("level_label", UserMastery.getLevelLabel(newMasteryLevel))
        return json.toString()
    }

    /**
     * 生成知识笔记上下文
     */
    private suspend fun generateNote(args: JSONObject): String {
        val topic = args.optString("topic", "")
        if (topic.isBlank()) return errorJson("topic 必填")
        val includeWeakness = args.optBoolean("include_weakness", true)

        // 尝试按 ID 查找
        var node = knowledgeNodeDao.getById(topic)
        if (node == null) {
            // 按名称搜索
            val candidates = knowledgeNodeDao.searchByName(topic, limit = 1)
            node = candidates.firstOrNull()
        }
        if (node == null) return errorJson("未找到知识点: $topic")

        val json = JSONObject()
        json.put("topic", node.name)
        json.put("knowledge_id", node.id)
        json.put("subject", node.subject)
        json.put("description", node.description ?: "")
        json.put("content", node.content ?: "")
        json.put("exam_frequency", node.examFrequency)

        if (includeWeakness) {
            val mastery = userMasteryDao.getByUserAndKnowledge(knowledgeId = node.id)
            if (mastery != null) {
                json.put("mastery_level", mastery.masteryLevel)
                json.put("review_count", mastery.reviewCount)
                json.put("correct_count", mastery.correctCount)
                json.put("level_label", UserMastery.getLevelLabel(mastery.masteryLevel))

                // 提示易错点（如果掌握度低）
                if (mastery.masteryLevel < 0.6f) {
                    json.put("weakness_note", "该知识点是你的薄弱环节，已练习 ${mastery.reviewCount} 次，正确率 ${
                        if (mastery.reviewCount > 0) "%.0f".format(mastery.correctCount.toFloat() / mastery.reviewCount * 100) else "0"
                    }%。建议重点复习核心概念和典型例题。")
                } else {
                    json.put("weakness_note", "该知识点掌握良好，继续巩固即可。")
                }
            }
        }

        return json.toString()
    }

    private fun errorJson(msg: String): String {
        val escaped = msg.replace("\\", "\\\\").replace("\"", "\\\"")
        return """{"error":"$escaped"}"""
    }
}
