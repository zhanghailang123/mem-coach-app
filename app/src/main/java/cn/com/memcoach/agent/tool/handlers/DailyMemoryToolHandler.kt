package cn.com.memcoach.agent.tool.handlers

import cn.com.memcoach.agent.memory.DailyMemoryService
import cn.com.memcoach.agent.tool.ToolDefinition
import cn.com.memcoach.agent.tool.ToolHandler
import org.json.JSONObject

/**
 * 短期记忆工具处理器 —— 提供当日学习摘要的查询和生成。
 *
 * 覆盖工具：
 * - memory_query_today   —— 查询今日学习摘要
 * - memory_generate_daily —— 生成并保存今日学习摘要
 * - memory_append         —— 追加一条记忆
 * - memory_recent_days    —— 获取最近 N 天的记忆
 * - memory_intelligent_rollup —— 智能归档（LLM 筛选长期记忆）
 */
class DailyMemoryToolHandler(
    private val dailyMemoryService: DailyMemoryService
) : ToolHandler {

    override val toolNames = setOf(
        "memory_query_today",
        "memory_generate_daily",
        "memory_append",
        "memory_recent_days",
        "memory_intelligent_rollup"
    )

    override suspend fun execute(toolName: String, arguments: String): String {
        return try {
            val args = JSONObject(arguments)
            when (toolName) {
                "memory_query_today" -> queryToday()
                "memory_generate_daily" -> generateDaily()
                "memory_append" -> appendMemory(args)
                "memory_recent_days" -> recentDays(args)
                "memory_intelligent_rollup" -> intelligentRollup(args)
                else -> errorJson("unknown tool: $toolName")
            }
        } catch (e: Exception) {
            errorJson("execute error: ${e.message?.replace("\"", "'")}")
        }
    }

    override fun getDefinitions(): List<ToolDefinition> = listOf(
        ToolDefinition(
            name = "memory_query_today",
            description = "查询今日学习摘要。返回今天的学习记录、做题数、正确率、薄弱知识点等信息。",
            parameters = """{"type": "object", "properties": {}}""".trimIndent()
        ),
        ToolDefinition(
            name = "memory_generate_daily",
            description = "生成并保存今日学习摘要。从数据库自动统计今日学习数据，生成结构化摘要。",
            parameters = """{"type": "object", "properties": {}}""".trimIndent()
        ),
        ToolDefinition(
            name = "memory_append",
            description = "追加一条记忆到今日摘要。用于记录用户的特殊要求、学习心得、重要笔记等。",
            parameters = """
{
  "type": "object",
  "properties": {
    "text": {
      "type": "string",
      "description": "要记录的记忆内容"
    }
  },
  "required": ["text"]
}
""".trimIndent()
        ),
        ToolDefinition(
            name = "memory_recent_days",
            description = "获取最近 N 天的学习记忆摘要。用于回顾近期学习情况。",
            parameters = """
{
  "type": "object",
  "properties": {
    "days": {
      "type": "integer",
      "default": 7,
      "description": "获取最近几天的记忆"
    }
  }
}
""".trimIndent()
        ),
        ToolDefinition(
            name = "memory_intelligent_rollup",
            description = "智能归档当日记忆。使用 LLM 分析学习记录，筛选值得长期保存的信息（学习偏好、易错模式、重要心得等）。",
            parameters = """
{
  "type": "object",
  "properties": {
    "date": {
      "type": "string",
      "description": "目标日期（格式：YYYY-MM-DD），默认今天"
    }
  }
}
""".trimIndent()
        )
    )

    // ─── 工具实现 ───

    private fun queryToday(): String {
        val content = dailyMemoryService.getToday()
        val json = JSONObject()
        json.put("date", java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(java.util.Date()))
        json.put("content", content.ifEmpty { "今日暂无记忆记录。" })
        json.put("has_content", content.isNotEmpty())
        return json.toString()
    }

    private suspend fun generateDaily(): String {
        val result = dailyMemoryService.rollupDay()
        val json = JSONObject()
        json.put("success", result["success"])
        json.put("date", result["date"])
        json.put("summary", result["summary"])
        return json.toString()
    }

    private suspend fun appendMemory(args: JSONObject): String {
        val text = args.optString("text", "").trim()
        if (text.isBlank()) return errorJson("text 不能为空")

        val file = dailyMemoryService.append(text)
        val json = JSONObject()
        json.put("success", true)
        json.put("path", file.absolutePath)
        json.put("message", "已记录到今日记忆。")
        return json.toString()
    }

    private fun recentDays(args: JSONObject): String {
        val days = args.optInt("days", 7).coerceIn(1, 30)
        val memories = dailyMemoryService.getRecentDays(days)

        val json = JSONObject()
        json.put("days", days)
        json.put("count", memories.size)
        json.put("memories", org.json.JSONArray().apply {
            memories.forEach { memory ->
                put(JSONObject().apply {
                    put("date", memory["date"])
                    put("content", memory["content"])
                })
            }
        })
        return json.toString()
    }

    private suspend fun intelligentRollup(args: JSONObject): String {
        val date = args.optString("date", "").trim().ifBlank { null }
        val result = dailyMemoryService.intelligentRollup(date)

        val json = JSONObject()
        json.put("success", result["success"])
        json.put("date", result["date"])
        
        if (result.containsKey("reason")) {
            json.put("reason", result["reason"])
        }
        
        if (result.containsKey("candidates_count")) {
            json.put("candidates_count", result["candidates_count"])
            json.put("inserted_count", result["inserted_count"])
            
            val entries = result["entries"] as? List<Map<String, String>>
            if (entries != null) {
                json.put("entries", org.json.JSONArray().apply {
                    entries.forEach { entry ->
                        put(JSONObject().apply {
                            put("text", entry["text"])
                            put("category", entry["category"])
                        })
                    }
                })
            }
        }
        
        if (result.containsKey("summary")) {
            json.put("summary", result["summary"])
        }
        
        if (result.containsKey("path")) {
            json.put("path", result["path"])
        }

        return json.toString()
    }

    private fun errorJson(msg: String): String {
        val escaped = msg.replace("\\", "\\\\").replace("\"", "\\\"")
        return """{"error":"$escaped"}"""
    }
}
