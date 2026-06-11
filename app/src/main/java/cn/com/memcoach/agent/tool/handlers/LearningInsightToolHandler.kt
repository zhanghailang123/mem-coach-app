package cn.com.memcoach.agent.tool.handlers

import cn.com.memcoach.agent.tool.ToolDefinition
import cn.com.memcoach.agent.tool.ToolHandler
import cn.com.memcoach.data.dao.LearningInsightDao
import cn.com.memcoach.data.entity.LearningInsight
import kotlinx.serialization.json.*

/**
 * 学习洞察工具
 *
 * Agent 通过分析错题本等数据，挖掘出用户的薄弱点、错误模式。
 */
class LearningInsightToolHandler(
    private val learningInsightDao: LearningInsightDao
) : ToolHandler {

    override val toolNames = setOf(
        "propose_learning_insight",
        "list_learning_insights"
    )

    override suspend fun execute(toolName: String, arguments: String): String {
        val args = try { Json.parseToJsonElement(arguments).jsonObject } catch (_: Exception) { JsonObject(emptyMap()) }
        return when (toolName) {
            "propose_learning_insight" -> proposeLearningInsight(args)
            "list_learning_insights" -> listLearningInsights(args)
            else -> """{"error":"unknown tool: $toolName"}"""
        }
    }

    override fun getDefinitions() = listOf(
        ToolDefinition(
            name = "propose_learning_insight",
            description = "提交学习洞察（薄弱点、错误模式、有效策略）",
            parameters = """
            {
              "type": "object",
              "properties": {
                "category": {
                  "type": "string",
                  "enum": ["weak_point", "mistake_pattern", "strategy", "progress"],
                  "description": "洞察类别"
                },
                "content": {
                  "type": "string",
                  "description": "洞察内容，如'条件充分性联合判断薄弱'"
                },
                "confidence": {
                  "type": "string",
                  "enum": ["low", "medium", "high"],
                  "description": "置信度"
                },
                "evidence": {
                  "type": "array",
                  "items": {"type": "string"},
                  "description": "支撑证据，如题目ID列表"
                },
                "suggestion": {
                  "type": "string",
                  "description": "改进建议"
                }
              },
              "required": ["category", "content", "confidence", "evidence", "suggestion"]
            }
            """.trimIndent()
        ),
        ToolDefinition(
            name = "list_learning_insights",
            description = "查看学习洞察列表",
            parameters = """{"type":"object","properties":{"status":{"type":"string"},"category":{"type":"string"}}}"""
        )
    )

    private suspend fun proposeLearningInsight(args: JsonObject): String {
        val category = args["category"]?.jsonPrimitive?.content
            ?: return """{"error":"category required"}"""
        val content = args["content"]?.jsonPrimitive?.content
            ?: return """{"error":"content required"}"""
        val confidence = args["confidence"]?.jsonPrimitive?.content
            ?: return """{"error":"confidence required"}"""
        val evidenceArray = args["evidence"]?.jsonArray?.map { it.jsonPrimitive.content } ?: emptyList()
        val evidenceJson = buildJsonArray { evidenceArray.forEach { add(it) } }.toString()
        val suggestion = args["suggestion"]?.jsonPrimitive?.content
            ?: return """{"error":"suggestion required"}"""

        val insight = LearningInsight(
            category = category,
            content = content,
            confidence = confidence,
            evidence = evidenceJson,
            suggestion = suggestion,
            status = "pending"
        )

        val id = learningInsightDao.insert(insight)

        return buildJsonObject {
            put("success", true)
            put("insight_id", id)
            put("message", "学习洞察已提交，等待用户确认")
        }.toString()
    }

    private suspend fun listLearningInsights(args: JsonObject): String {
        val status = args["status"]?.jsonPrimitive?.contentOrNull
        val category = args["category"]?.jsonPrimitive?.contentOrNull

        val insights = when {
            status != null -> learningInsightDao.getByStatus(status)
            category != null -> learningInsightDao.getByCategory(category)
            else -> learningInsightDao.getConfirmed()
        }

        return buildJsonObject {
            put("count", insights.size)
            put("insights", buildJsonArray {
                insights.forEach { i ->
                    add(buildJsonObject {
                        put("id", i.id)
                        put("category", i.category)
                        put("content", i.content)
                        put("confidence", i.confidence)
                        put("suggestion", i.suggestion)
                        put("status", i.status)
                    })
                }
            })
        }.toString()
    }
}
