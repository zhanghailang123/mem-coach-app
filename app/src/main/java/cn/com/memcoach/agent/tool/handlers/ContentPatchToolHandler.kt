package cn.com.memcoach.agent.tool.handlers

import cn.com.memcoach.agent.tool.ToolDefinition
import cn.com.memcoach.agent.tool.ToolHandler
import cn.com.memcoach.data.dao.ContentPatchDao
import cn.com.memcoach.data.entity.ContentPatch
import kotlinx.serialization.json.*

/**
 * 内容改进提案工具
 *
 * Agent 发现真题解析、单词讲解等内容可以优化时，提交改进提案。
 */
class ContentPatchToolHandler(
    private val contentPatchDao: ContentPatchDao
) : ToolHandler {

    override val toolNames = setOf(
        "propose_content_patch",
        "list_content_patches"
    )

    override suspend fun execute(toolName: String, arguments: String): String {
        val args = try { Json.parseToJsonElement(arguments).jsonObject } catch (_: Exception) { JsonObject(emptyMap()) }
        return when (toolName) {
            "propose_content_patch" -> proposeContentPatch(args)
            "list_content_patches" -> listContentPatches(args)
            else -> """{"error":"unknown tool: $toolName"}"""
        }
    }

    override fun getDefinitions() = listOf(
        ToolDefinition(
            name = "propose_content_patch",
            description = "提议内容改进（真题解析、单词讲解等）。Agent 发现内容不清晰或有误时调用。",
            parameters = """
            {
              "type": "object",
              "properties": {
                "target_type": {
                  "type": "string",
                  "enum": ["question", "vocabulary", "knowledge"],
                  "description": "目标类型"
                },
                "target_id": {
                  "type": "string",
                  "description": "目标ID，如 logic_2023_5"
                },
                "operation": {
                  "type": "string",
                  "enum": ["append", "replace", "clarify"],
                  "description": "操作类型：append=追加, replace=替换, clarify=澄清"
                },
                "patch_content": {
                  "type": "string",
                  "description": "改进内容（Markdown格式）"
                },
                "reason": {
                  "type": "string",
                  "description": "改进理由"
                },
                "risk_level": {
                  "type": "string",
                  "enum": ["low", "medium", "high"],
                  "description": "风险等级，默认 low"
                }
              },
              "required": ["target_type", "target_id", "operation", "patch_content", "reason"]
            }
            """.trimIndent()
        ),
        ToolDefinition(
            name = "list_content_patches",
            description = "查看内容改进提案列表",
            parameters = """{"type":"object","properties":{"status":{"type":"string"}}}"""
        )
    )

    private suspend fun proposeContentPatch(args: JsonObject): String {
        val targetType = args["target_type"]?.jsonPrimitive?.content
            ?: return """{"error":"target_type required"}"""
        val targetId = args["target_id"]?.jsonPrimitive?.content
            ?: return """{"error":"target_id required"}"""
        val operation = args["operation"]?.jsonPrimitive?.content
            ?: return """{"error":"operation required"}"""
        val patchContent = args["patch_content"]?.jsonPrimitive?.content
            ?: return """{"error":"patch_content required"}"""
        val reason = args["reason"]?.jsonPrimitive?.content
            ?: return """{"error":"reason required"}"""
        val riskLevel = args["risk_level"]?.jsonPrimitive?.contentOrNull ?: "low"

        val patch = ContentPatch(
            targetType = targetType,
            targetId = targetId,
            operation = operation,
            patchContent = patchContent,
            reason = reason,
            riskLevel = riskLevel,
            status = "pending"
        )

        val id = contentPatchDao.insert(patch)

        return buildJsonObject {
            put("success", true)
            put("patch_id", id)
            put("message", "改进提案已提交，等待用户审核")
        }.toString()
    }

    private suspend fun listContentPatches(args: JsonObject): String {
        val status = args["status"]?.jsonPrimitive?.contentOrNull ?: "pending"
        val patches = contentPatchDao.getByStatus(status)

        return buildJsonObject {
            put("count", patches.size)
            put("patches", buildJsonArray {
                patches.forEach { p ->
                    add(buildJsonObject {
                        put("id", p.id)
                        put("target_type", p.targetType)
                        put("target_id", p.targetId)
                        put("operation", p.operation)
                        put("reason", p.reason)
                        put("status", p.status)
                    })
                }
            })
        }.toString()
    }
}
