package cn.com.memcoach.agent.tool.handlers

import cn.com.memcoach.agent.AgentLlmClient
import cn.com.memcoach.agent.ChatMessage
import cn.com.memcoach.agent.subagent.SubAgentConfig
import cn.com.memcoach.agent.subagent.SubAgentMode
import cn.com.memcoach.agent.subagent.SubAgentRegistry
import cn.com.memcoach.agent.tool.ToolDefinition
import cn.com.memcoach.agent.tool.ToolHandler
import kotlinx.serialization.json.*

/**
 * 子 Agent 委派工具处理器
 */
class SubAgentDelegateToolHandler(
    private val llmClient: AgentLlmClient
) : ToolHandler {

    override val toolNames = setOf(
        "delegate_to_math_tutor",
        "delegate_to_english_tutor",
        "delegate_to_vocabulary_coach"
    )

    override suspend fun execute(toolName: String, arguments: String): String {
        val subAgentName = toolName.removePrefix("delegate_to_").replace('_', '-')
        val config = SubAgentRegistry.get(subAgentName)
            ?: return """{"error": "子 Agent 不存在: $subAgentName"}"""

        return when (config.mode) {
            SubAgentMode.LIGHTWEIGHT -> executeLightweight(config, arguments)
            SubAgentMode.FULL_REACT -> """{"error": "完整 ReAct 模式暂未实现"}"""
        }
    }

    override fun getDefinitions() = listOf(
        ToolDefinition(
            name = "delegate_to_math_tutor",
            description = "委派给数学导师（讲解管综数学题：条件充分性、排列组合、几何等）",
            parameters = """
            {
              "type": "object",
              "properties": {
                "task": {"type": "string", "description": "具体任务，如'讲解这道题'"},
                "context": {"type": "string", "description": "上下文（题目内容、用户疑问等）"}
              },
              "required": ["task", "context"]
            }
            """.trimIndent()
        ),
        ToolDefinition(
            name = "delegate_to_english_tutor",
            description = "委派给英语导师（讲解考研英语：阅读、翻译、作文）",
            parameters = """
            {
              "type": "object",
              "properties": {
                "task": {"type": "string"},
                "context": {"type": "string"}
              },
              "required": ["task", "context"]
            }
            """.trimIndent()
        ),
        ToolDefinition(
            name = "delegate_to_vocabulary_coach",
            description = "委派给单词管家（讲解单词、生成记忆技巧、识别易混词）",
            parameters = """
            {
              "type": "object",
              "properties": {
                "task": {"type": "string"},
                "context": {"type": "string"}
              },
              "required": ["task", "context"]
            }
            """.trimIndent()
        )
    )

    private suspend fun executeLightweight(
        config: SubAgentConfig,
        arguments: String
    ): String {
        val args = try {
            Json.parseToJsonElement(arguments).jsonObject
        } catch (_: Exception) {
            return """{"error":"参数解析失败"}"""
        }

        val task = args["task"]?.jsonPrimitive?.content
            ?: return """{"error":"缺少 task 参数"}"""
        val context = args["context"]?.jsonPrimitive?.contentOrNull ?: ""

        val userPrompt = buildString {
            append("**任务**: $task\n\n")
            if (context.isNotBlank()) {
                append("**上下文**:\n$context\n\n")
            }
            append("请按照你的专家角色分析并输出 JSON 格式结果。")
        }

        val messages = listOf(
            ChatMessage(role = "system", content = config.systemPrompt),
            ChatMessage(role = "user", content = userPrompt)
        )

        val result = try {
            llmClient.completeTurn(messages, tools = null)
        } catch (e: Exception) {
            return buildJsonObject {
                put("success", false)
                put("error", "LLM调用失败: ${e.message}")
            }.toString()
        }

        return buildJsonObject {
            put("success", true)
            put("subagent", config.name)
            put("result", result.content ?: "")
        }.toString()
    }
}
