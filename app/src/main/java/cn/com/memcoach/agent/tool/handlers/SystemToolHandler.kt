package cn.com.memcoach.agent.tool.handlers

import cn.com.memcoach.agent.tool.ToolDefinition
import cn.com.memcoach.agent.tool.ToolHandler
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 通用系统工具 (System Tool)
 * 
 * 提供获取当前时间、日期等系统级通用能力。
 */
class SystemToolHandler : ToolHandler {
    override val toolNames: Set<String> = setOf("get_current_time")

    override suspend fun execute(toolName: String, arguments: String): String {
        return try {
            when (toolName) {
                "get_current_time" -> {
                    val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss EEEE", Locale.CHINA)
                    val currentTime = dateFormat.format(Date())
                    """{"current_time": "$currentTime"}"""
                }
                else -> """{"error": "未知的工具: $toolName"}"""
            }
        } catch (e: Exception) {
            """{"error": "执行失败: ${e.message}"}"""
        }
    }

    override fun getDefinitions(): List<ToolDefinition> {
        return listOf(
            ToolDefinition(
                name = "get_current_time",
                description = "获取当前系统的时间和日期。在需要知道今天是哪一天、星期几时使用。",
                parameters = """
                    {
                        "type": "object",
                        "properties": {},
                        "required": []
                    }
                """.trimIndent()
            )
        )
    }
}
