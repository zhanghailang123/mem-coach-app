package cn.com.memcoach.agent.memory

import cn.com.memcoach.agent.AgentLlmClient
import cn.com.memcoach.agent.ChatMessage
import cn.com.memcoach.data.dao.StudyRecordDao
import cn.com.memcoach.data.dao.UserMasteryDao
import cn.com.memcoach.data.dao.KnowledgeNodeDao
import cn.com.memcoach.data.entity.UserMastery
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * 短期记忆服务 —— 管理当日学习摘要，支持自动归档。
 *
 * 设计借鉴：OpenOmniBot WorkspaceMemoryService 的短期记忆机制。
 *
 * 核心功能：
 * 1. 记录当日学习摘要（手动或自动生成）
 * 2. 查询当日记忆
 * 3. 智能归档旧日记忆（调用 LLM 筛选长期记忆候选）
 *
 * 存储格式：纯文本文件，按日期组织
 *   /data/data/.../memory/daily/2026-05-14.md
 */
class DailyMemoryService(
    private val memoryDir: File,
    private val studyRecordDao: StudyRecordDao,
    private val userMasteryDao: UserMasteryDao,
    private val knowledgeNodeDao: KnowledgeNodeDao,
    private val longTermMemoryService: LongTermMemoryService? = null,
    private val llmClient: AgentLlmClient? = null
) {
    companion object {
        /** 智能 Rollup 的 System Prompt */
        private val ROLLUP_SYSTEM_PROMPT = """你是一个学习记忆管理助手。你的任务是从短期学习记录中筛选出值得长期保存的信息。

筛选标准：
1. **学习偏好**：用户的学习习惯、时间偏好、方法偏好
2. **易错模式**：反复出错的知识点、错误类型、错误原因
3. **重要心得**：用户总结的学习技巧、理解难点的方法
4. **关键概念**：重要的定义、公式、定理
5. **成就里程碑**：连续学习天数、突破性进步

输出格式（JSON数组）：
```json
[
  {
    "text": "记忆内容",
    "category": "preference|mistake|note|concept|formula|achievement",
    "tags": ["标签1", "标签2"],
    "importance": 7
  }
]
```

重要性等级（1-10）：
- 1-3：可选保存
- 4-6：建议保存
- 7-9：强烈建议保存
- 10：必须保存

注意事项：
- 只筛选有长期价值的信息，不要保存临时性内容
- 每条记忆要简洁明了，不超过100字
- 标签要简洁，用于后续搜索
- 如果没有值得保存的内容，返回空数组 []"""
    }
    private val dateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)
    private val dailyDir = File(memoryDir, "daily")

    init {
        dailyDir.mkdirs()
    }

    /**
     * 追加当日记忆
     */
    suspend fun append(text: String): File {
        val today = dateFormat.format(Calendar.getInstance().time)
        val file = File(dailyDir, "$today.md")

        val timestamp = SimpleDateFormat("HH:mm", Locale.US).format(Calendar.getInstance().time)
        val entry = "[$timestamp] $text\n"

        file.appendText(entry)
        return file
    }

    /**
     * 获取当日记忆内容
     */
    fun getToday(): String {
        val today = dateFormat.format(Calendar.getInstance().time)
        val file = File(dailyDir, "$today.md")
        return if (file.exists()) file.readText() else ""
    }

    /**
     * 获取指定日期的记忆内容
     */
    fun getForDate(date: String): String {
        val file = File(dailyDir, "$date.md")
        return if (file.exists()) file.readText() else ""
    }

    /**
     * 生成当日学习摘要 —— 从数据库自动生成
     */
    suspend fun generateDailySummary(): String {
        val now = System.currentTimeMillis()
        val todayStart = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis

        val todayRecords = studyRecordDao.getByDateRange(
            startTime = todayStart,
            endTime = now
        )

        if (todayRecords.isEmpty()) {
            return "今日暂无学习记录。"
        }

        val totalCount = todayRecords.size
        val correctCount = todayRecords.count { it.isCorrect == true }
        val accuracy = if (totalCount > 0) correctCount.toDouble() / totalCount else 0.0
        val totalTime = todayRecords.sumOf { it.timeSpentSeconds }

        // 按知识点分组统计
        val validRecords = todayRecords.filter { it.knowledgeId != null }
        val byKnowledge = validRecords.groupBy { it.knowledgeId!! }

        val weakTopics = byKnowledge.filter { (_, records) ->
            records.count { it.isCorrect == true }.toDouble() / records.size < 0.6
        }.keys.take(3)

        val strongTopics = byKnowledge.filter { (_, records) ->
            records.count { it.isCorrect == true }.toDouble() / records.size >= 0.8
        }.keys.take(3)

        return buildString {
            appendLine("## 今日学习摘要")
            appendLine()
            appendLine("- 做题数: $totalCount")
            appendLine("- 正确数: $correctCount")
            appendLine("- 正确率: ${(accuracy * 100).toInt()}%")
            appendLine("- 学习时长: ${totalTime / 60} 分钟")
            appendLine()

            if (weakTopics.isNotEmpty()) {
                appendLine("### 薄弱知识点")
                weakTopics.forEach { topic ->
                    val node = knowledgeNodeDao.getById(topic)
                    appendLine("- ${node?.name ?: topic}")
                }
                appendLine()
            }

            if (strongTopics.isNotEmpty()) {
                appendLine("### 掌握良好")
                strongTopics.forEach { topic ->
                    val node = knowledgeNodeDao.getById(topic)
                    appendLine("- ${node?.name ?: topic}")
                }
            }
        }
    }

    /**
     * 归档当日记忆 —— 生成摘要并保存
     */
    suspend fun rollupDay(date: String? = null): Map<String, Any?> {
        val targetDate = date ?: dateFormat.format(Calendar.getInstance().time)
        val summary = generateDailySummary()

        // 保存摘要
        val file = File(dailyDir, "$targetDate.md")
        file.writeText(summary)

        return mapOf(
            "success" to true,
            "date" to targetDate,
            "path" to file.absolutePath,
            "summary" to summary.take(200) + if (summary.length > 200) "..." else ""
        )
    }

    /**
     * 智能归档当日记忆 —— LLM 辅助筛选长期记忆候选
     *
     * 与 rollupDay 的区别：
     * - rollupDay：简单生成摘要
     * - intelligentRollup：LLM 分析短期记忆，筛选值得长期保存的信息
     *
     * @param date 目标日期，默认今天
     * @return 归档结果，包含筛选出的长期记忆候选
     */
    suspend fun intelligentRollup(date: String? = null): Map<String, Any?> {
        val targetDate = date ?: dateFormat.format(Calendar.getInstance().time)
        val dailyContent = getForDate(targetDate)

        if (dailyContent.isBlank()) {
            return mapOf(
                "success" to false,
                "reason" to "无记忆内容",
                "date" to targetDate
            )
        }

        // 检查依赖是否可用
        if (longTermMemoryService == null || llmClient == null) {
            // 降级为简单归档
            return rollupDay(date)
        }

        return try {
            // 调用 LLM 筛选长期记忆候选
            val candidates = requestLLMRollup(dailyContent, targetDate)

            // 解析 LLM 返回的 JSON，写入长期记忆
            val entries = parseRollupCandidates(candidates)
            var insertedCount = 0

            entries.forEach { entry ->
                val inserted = longTermMemoryService.upsert(
                    text = entry.text,
                    category = entry.category,
                    tags = entry.tags,
                    importance = entry.importance
                )
                if (inserted) insertedCount++
            }

            // 生成并保存当日摘要
            val summary = generateDailySummary()
            val file = File(dailyDir, "$targetDate.md")
            file.writeText(summary)

            mapOf(
                "success" to true,
                "date" to targetDate,
                "path" to file.absolutePath,
                "candidates_count" to entries.size,
                "inserted_count" to insertedCount,
                "entries" to entries.map { mapOf("text" to it.text, "category" to it.category) },
                "summary" to summary.take(200) + if (summary.length > 200) "..." else ""
            )
        } catch (e: Exception) {
            // LLM 调用失败，降级为简单归档
            System.err.println("[DailyMemoryService] 智能归档失败，降级为简单归档: ${e.message}")
            rollupDay(date)
        }
    }

    /**
     * 调用 LLM 筛选长期记忆候选
     */
    private suspend fun requestLLMRollup(dailyContent: String, date: String): String {
        val requestMessages = mutableListOf<ChatMessage>()

        // System prompt
        requestMessages.add(ChatMessage(
            role = "system",
            content = ROLLUP_SYSTEM_PROMPT
        ))

        // User prompt
        requestMessages.add(ChatMessage(
            role = "user",
            content = """请从以下 $date 的学习记录中筛选值得长期保存的信息：

$dailyContent

请返回 JSON 数组格式，如果没有值得保存的内容，返回空数组 []。"""
        ))

        // 调用 LLM
        val result = llmClient!!.completeTurn(
            messages = requestMessages,
            tools = null
        )

        return result.content.trim()
    }

    /**
     * 解析 LLM 返回的长期记忆候选
     */
    private fun parseRollupCandidates(llmResponse: String): List<RollupCandidate> {
        return try {
            // 提取 JSON 数组（可能被包裹在 ```json ... ``` 中）
            val jsonStr = extractJsonArray(llmResponse)
            val jsonArray = JSONArray(jsonStr)
            val candidates = mutableListOf<RollupCandidate>()

            for (i in 0 until jsonArray.length()) {
                val obj = jsonArray.getJSONObject(i)
                val text = obj.optString("text", "").trim()
                if (text.isBlank()) continue

                val category = obj.optString("category", "note")
                val tagsArray = obj.optJSONArray("tags")
                val tags = mutableListOf<String>()
                if (tagsArray != null) {
                    for (j in 0 until tagsArray.length()) {
                        tags.add(tagsArray.getString(j))
                    }
                }
                val importance = obj.optInt("importance", 5).coerceIn(1, 10)

                candidates.add(RollupCandidate(text, category, tags, importance))
            }

            candidates
        } catch (e: Exception) {
            System.err.println("[DailyMemoryService] 解析 Rollup 候选失败: ${e.message}")
            emptyList()
        }
    }

    /**
     * 从 LLM 响应中提取 JSON 数组
     */
    private fun extractJsonArray(response: String): String {
        // 尝试直接解析
        val trimmed = response.trim()
        if (trimmed.startsWith("[")) {
            return trimmed
        }

        // 尝试提取 ```json ... ``` 中的内容
        val codeBlockRegex = "```(?:json)?\\s*\\n?([\\s\\S]*?)\\n?```".toRegex()
        val match = codeBlockRegex.find(trimmed)
        if (match != null) {
            return match.groupValues[1].trim()
        }

        // 尝试提取 [ ... ] 部分
        val arrayRegex = "\\[\\s*\\{[\\s\\S]*\\}\\s*\\]".toRegex()
        val arrayMatch = arrayRegex.find(trimmed)
        if (arrayMatch != null) {
            return arrayMatch.value
        }

        return "[]"
    }

    /**
     * Rollup 候选条目
     */
    private data class RollupCandidate(
        val text: String,
        val category: String,
        val tags: List<String>,
        val importance: Int
    )

    /**
     * 获取最近 N 天的记忆摘要
     */
    fun getRecentDays(days: Int = 7): List<Map<String, String>> {
        val result = mutableListOf<Map<String, String>>()
        val cal = Calendar.getInstance()

        for (i in 0 until days) {
            val date = dateFormat.format(cal.time)
            val file = File(dailyDir, "$date.md")
            if (file.exists()) {
                result.add(mapOf(
                    "date" to date,
                    "content" to file.readText()
                ))
            }
            cal.add(Calendar.DAY_OF_YEAR, -1)
        }

        return result
    }

    /**
     * 获取所有记忆文件列表
     */
    fun listAll(): List<String> {
        return dailyDir.listFiles()
            ?.filter { it.extension == "md" }
            ?.map { it.nameWithoutExtension }
            ?.sortedDescending()
            ?: emptyList()
    }
}
