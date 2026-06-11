package cn.com.memcoach.agent.tool.handlers

import cn.com.memcoach.agent.tool.ToolDefinition
import cn.com.memcoach.agent.tool.ToolHandler
import cn.com.memcoach.data.dao.UserMemoDao
import cn.com.memcoach.data.entity.UserMemo
import kotlinx.serialization.json.*

/**
 * 用户笔记工具
 *
 * Agent 为用户生成个性化学习笔记。
 */
class UserMemoToolHandler(
    private val userMemoDao: UserMemoDao
) : ToolHandler {

    override val toolNames = setOf(
        "save_user_memo",
        "get_user_memos"
    )

    override suspend fun execute(toolName: String, arguments: String): String {
        val args = try { Json.parseToJsonElement(arguments).jsonObject } catch (_: Exception) { JsonObject(emptyMap()) }
        return when (toolName) {
            "save_user_memo" -> saveUserMemo(args)
            "get_user_memos" -> getUserMemos(args)
            else -> """{"error":"unknown tool: $toolName"}"""
        }
    }

    override fun getDefinitions() = listOf(
        ToolDefinition(
            name = "save_user_memo",
            description = "保存用户笔记（个性化记忆技巧、易混概念对比等）",
            parameters = """
            {
              "type": "object",
              "properties": {
                "type": {
                  "type": "string",
                  "enum": ["word", "question", "concept"],
                  "description": "笔记类型"
                },
                "target_id": {
                  "type": "string",
                  "description": "关联ID"
                },
                "content": {
                  "type": "string",
                  "description": "笔记内容（Markdown）"
                },
                "tags": {
                  "type": "array",
                  "items": {"type": "string"},
                  "description": "标签，如 ['易混词', '记忆技巧']"
                }
              },
              "required": ["type", "target_id", "content"]
            }
            """.trimIndent()
        ),
        ToolDefinition(
            name = "get_user_memos",
            description = "获取用户笔记",
            parameters = """
            {
              "type":"object",
              "properties":{
                "type":{"type":"string"},
                "target_id":{"type":"string"}
              }
            }
            """.trimIndent()
        )
    )

    private suspend fun saveUserMemo(args: JsonObject): String {
        val type = args["type"]?.jsonPrimitive?.content ?: return """{"error":"type required"}"""
        val targetId = args["target_id"]?.jsonPrimitive?.content ?: return """{"error":"target_id required"}"""
        val content = args["content"]?.jsonPrimitive?.content ?: return """{"error":"content required"}"""
        val tagsArray = args["tags"]?.jsonArray?.map { it.jsonPrimitive.content } ?: emptyList()
        val tagsJson = buildJsonArray { tagsArray.forEach { add(it) } }.toString()

        val memo = UserMemo(
            type = type,
            targetId = targetId,
            content = content,
            tags = tagsJson
        )

        val id = userMemoDao.insert(memo)

        return buildJsonObject {
            put("success", true)
            put("memo_id", id)
            put("message", "笔记已保存")
        }.toString()
    }

    private suspend fun getUserMemos(args: JsonObject): String {
        val type = args["type"]?.jsonPrimitive?.contentOrNull
        val targetId = args["target_id"]?.jsonPrimitive?.contentOrNull

        val memos = if (type != null && targetId != null) {
            userMemoDao.getByTarget(type, targetId)
        } else if (type != null) {
            userMemoDao.getByType(type, limit = 50)
        } else {
            userMemoDao.getRecent(limit = 50)
        }

        return buildJsonObject {
            put("count", memos.size)
            put("memos", buildJsonArray {
                memos.forEach { m ->
                    add(buildJsonObject {
                        put("id", m.id)
                        put("type", m.type)
                        put("target_id", m.targetId)
                        put("content", m.content)
                        put("tags", Json.parseToJsonElement(m.tags))
                    })
                }
            })
        }.toString()
    }
}
