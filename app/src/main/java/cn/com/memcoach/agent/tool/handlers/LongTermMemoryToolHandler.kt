package cn.com.memcoach.agent.tool.handlers

import cn.com.memcoach.agent.memory.LongTermMemoryService
import cn.com.memcoach.agent.tool.ToolDefinition
import cn.com.memcoach.agent.tool.ToolHandler
import org.json.JSONObject

/**
 * 长期记忆工具处理器 —— 提供用户偏好、易错模式、重要笔记的存储和检索。
 *
 * 覆盖工具：
 * - memory_search        —— 搜索长期记忆
 * - memory_write_longterm —— 写入长期记忆
 * - memory_update         —— 更新长期记忆
 * - memory_delete         —— 删除长期记忆
 * - memory_stats          —— 获取记忆统计
 * - memory_search_by_tag  —— 按标签搜索记忆
 * - memory_search_by_importance —— 按重要性搜索记忆
 * - memory_get_tags       —— 获取所有标签
 */
class LongTermMemoryToolHandler(
    private val longTermMemoryService: LongTermMemoryService
) : ToolHandler {

    override val toolNames = setOf(
        "memory_search",
        "memory_write_longterm",
        "memory_update",
        "memory_delete",
        "memory_stats",
        "memory_search_by_tag",
        "memory_search_by_importance",
        "memory_get_tags"
    )

    override suspend fun execute(toolName: String, arguments: String): String {
        return try {
            val args = JSONObject(arguments)
            when (toolName) {
                "memory_search" -> searchMemory(args)
                "memory_write_longterm" -> writeLongTerm(args)
                "memory_update" -> updateMemory(args)
                "memory_delete" -> deleteMemory(args)
                "memory_stats" -> getStats()
                "memory_search_by_tag" -> searchByTag(args)
                "memory_search_by_importance" -> searchByImportance(args)
                "memory_get_tags" -> getTags()
                else -> errorJson("unknown tool: $toolName")
            }
        } catch (e: Exception) {
            errorJson("execute error: ${e.message?.replace("\"", "'")}")
        }
    }

    override fun getDefinitions(): List<ToolDefinition> = listOf(
        ToolDefinition(
            name = "memory_search",
            description = "搜索长期记忆。用于查找用户的学习偏好、易错模式、重要笔记等。",
            parameters = """
{
  "type": "object",
  "properties": {
    "query": {
      "type": "string",
      "description": "搜索关键词"
    },
    "limit": {
      "type": "integer",
      "default": 5,
      "description": "返回数量上限"
    }
  },
  "required": ["query"]
}
""".trimIndent()
        ),
        ToolDefinition(
            name = "memory_write_longterm",
            description = "写入长期记忆。用于保存用户的学习偏好、易错模式、重要心得等。会自动去重。",
            parameters = """
{
  "type": "object",
  "properties": {
    "text": {
      "type": "string",
      "description": "要保存的记忆内容"
    },
    "category": {
      "type": "string",
      "enum": ["preference", "mistake", "note", "achievement", "concept", "formula"],
      "default": "note",
      "description": "记忆分类：preference=偏好, mistake=易错点, note=笔记, achievement=成就, concept=概念, formula=公式"
    },
    "tags": {
      "type": "array",
      "items": {"type": "string"},
      "description": "标签列表，用于分类和搜索"
    },
    "importance": {
      "type": "integer",
      "default": 5,
      "description": "重要性等级（1-10），7以上为高重要性"
    }
  },
  "required": ["text"]
}
""".trimIndent()
        ),
        ToolDefinition(
            name = "memory_update",
            description = "更新长期记忆。修改已有记忆的内容。",
            parameters = """
{
  "type": "object",
  "properties": {
    "id": {
      "type": "string",
      "description": "记忆 ID"
    },
    "text": {
      "type": "string",
      "description": "新的记忆内容"
    }
  },
  "required": ["id", "text"]
}
""".trimIndent()
        ),
        ToolDefinition(
            name = "memory_delete",
            description = "删除长期记忆。",
            parameters = """
{
  "type": "object",
  "properties": {
    "id": {
      "type": "string",
      "description": "要删除的记忆 ID"
    }
  },
  "required": ["id"]
}
""".trimIndent()
        ),
        ToolDefinition(
            name = "memory_stats",
            description = "获取记忆统计信息。返回总记忆数、按分类统计等。",
            parameters = """{"type": "object", "properties": {}}""".trimIndent()
        ),
        ToolDefinition(
            name = "memory_search_by_tag",
            description = "按标签搜索长期记忆。用于查找特定标签的记忆。",
            parameters = """
{
  "type": "object",
  "properties": {
    "tag": {
      "type": "string",
      "description": "要搜索的标签"
    },
    "limit": {
      "type": "integer",
      "default": 5,
      "description": "返回数量上限"
    }
  },
  "required": ["tag"]
}
""".trimIndent()
        ),
        ToolDefinition(
            name = "memory_search_by_importance",
            description = "按重要性搜索长期记忆。用于查找高重要性的记忆。",
            parameters = """
{
  "type": "object",
  "properties": {
    "min_importance": {
      "type": "integer",
      "default": 7,
      "description": "最低重要性阈值（1-10）"
    },
    "limit": {
      "type": "integer",
      "default": 5,
      "description": "返回数量上限"
    }
  }
}
""".trimIndent()
        ),
        ToolDefinition(
            name = "memory_get_tags",
            description = "获取所有标签列表。用于了解记忆的分类情况。",
            parameters = """{"type": "object", "properties": {}}""".trimIndent()
        )
    )

    // ─── 工具实现 ───

    private fun searchMemory(args: JSONObject): String {
        val query = args.optString("query", "").trim()
        if (query.isBlank()) return errorJson("query 不能为空")

        val limit = args.optInt("limit", 5).coerceIn(1, 20)
        val results = longTermMemoryService.search(query, limit)

        val json = JSONObject()
        json.put("query", query)
        json.put("count", results.size)
        json.put("results", org.json.JSONArray().apply {
            results.forEach { entry ->
                put(JSONObject().apply {
                    put("id", entry.id)
                    put("text", entry.text)
                    put("category", entry.category)
                    put("tags", org.json.JSONArray(entry.tags))
                    put("importance", entry.importance)
                    put("created_at", entry.createdAt)
                    put("updated_at", entry.updatedAt)
                })
            }
        })
        return json.toString()
    }

    private fun writeLongTerm(args: JSONObject): String {
        val text = args.optString("text", "").trim()
        if (text.isBlank()) return errorJson("text 不能为空")

        val category = args.optString("category", "note").trim()
        val tagsArray = args.optJSONArray("tags")
        val tags = mutableListOf<String>()
        if (tagsArray != null) {
            for (i in 0 until tagsArray.length()) {
                tags.add(tagsArray.getString(i))
            }
        }
        val importance = args.optInt("importance", 5).coerceIn(1, 10)
        
        val inserted = longTermMemoryService.upsert(text, category, tags, importance)

        val json = JSONObject()
        json.put("inserted", inserted)
        json.put("message", if (inserted) "已保存到长期记忆。" else "记忆已存在，跳过写入。")
        return json.toString()
    }

    private fun updateMemory(args: JSONObject): String {
        val id = args.optString("id", "").trim()
        if (id.isBlank()) return errorJson("id 不能为空")

        val text = args.optString("text", "").trim()
        if (text.isBlank()) return errorJson("text 不能为空")

        val updated = longTermMemoryService.update(id, text)

        val json = JSONObject()
        json.put("updated", updated)
        json.put("message", if (updated) "记忆已更新。" else "未找到指定记忆。")
        return json.toString()
    }

    private fun deleteMemory(args: JSONObject): String {
        val id = args.optString("id", "").trim()
        if (id.isBlank()) return errorJson("id 不能为空")

        val deleted = longTermMemoryService.delete(id)

        val json = JSONObject()
        json.put("deleted", deleted)
        json.put("message", if (deleted) "记忆已删除。" else "未找到指定记忆。")
        return json.toString()
    }

    private fun getStats(): String {
        val stats = longTermMemoryService.getStats()

        val json = JSONObject()
        json.put("total", stats["total"])
        val byCategory = stats["by_category"] as? Map<*, *>
        if (byCategory != null) {
            json.put("by_category", JSONObject().apply {
                byCategory.forEach { (key, value) ->
                    put(key.toString(), value)
                }
            })
        }
        return json.toString()
    }

    private fun searchByTag(args: JSONObject): String {
        val tag = args.optString("tag", "").trim()
        if (tag.isBlank()) return errorJson("tag 不能为空")

        val limit = args.optInt("limit", 5).coerceIn(1, 20)
        val results = longTermMemoryService.searchByTag(tag, limit)

        val json = JSONObject()
        json.put("tag", tag)
        json.put("count", results.size)
        json.put("results", org.json.JSONArray().apply {
            results.forEach { entry ->
                put(JSONObject().apply {
                    put("id", entry.id)
                    put("text", entry.text)
                    put("category", entry.category)
                    put("tags", org.json.JSONArray(entry.tags))
                    put("importance", entry.importance)
                    put("created_at", entry.createdAt)
                    put("updated_at", entry.updatedAt)
                })
            }
        })
        return json.toString()
    }

    private fun searchByImportance(args: JSONObject): String {
        val minImportance = args.optInt("min_importance", 7).coerceIn(1, 10)
        val limit = args.optInt("limit", 5).coerceIn(1, 20)
        val results = longTermMemoryService.searchByImportance(minImportance, limit)

        val json = JSONObject()
        json.put("min_importance", minImportance)
        json.put("count", results.size)
        json.put("results", org.json.JSONArray().apply {
            results.forEach { entry ->
                put(JSONObject().apply {
                    put("id", entry.id)
                    put("text", entry.text)
                    put("category", entry.category)
                    put("tags", org.json.JSONArray(entry.tags))
                    put("importance", entry.importance)
                    put("created_at", entry.createdAt)
                    put("updated_at", entry.updatedAt)
                })
            }
        })
        return json.toString()
    }

    private fun getTags(): String {
        val tags = longTermMemoryService.getAllTags()

        val json = JSONObject()
        json.put("count", tags.size)
        json.put("tags", org.json.JSONArray(tags))
        return json.toString()
    }

    private fun errorJson(msg: String): String {
        val escaped = msg.replace("\\", "\\\\").replace("\"", "\\\"")
        return """{"error":"$escaped"}"""
    }
}
