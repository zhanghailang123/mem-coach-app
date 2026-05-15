package cn.com.memcoach.agent

import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

/**
 * Agent 结构化链路日志。
 *
 * 所有日志统一输出为单行 JSON，方便在 Logcat 中按 trace_id / event / tool_name 过滤。
 */
object AgentTraceLogger {
    private const val TAG = "MemCoachAgentTrace"
    private const val MAX_FIELD_LENGTH = 2_000
    private const val MAX_LOG_LINE_LENGTH = 3_600

    fun newTraceId(prefix: String = "agent"): String {
        return "${prefix}_${System.currentTimeMillis()}_${(1000..9999).random()}"
    }

    fun event(name: String, fields: Map<String, Any?> = emptyMap()) {
        val json = JSONObject()
        json.put("event", name)
        json.put("ts", System.currentTimeMillis())
        fields.forEach { (key, value) -> json.put(key, normalize(value)) }
        write(json.toString())
    }

    fun summarizeMessages(messages: List<ChatMessage>, maxMessages: Int = 8): JSONArray {
        val array = JSONArray()
        messages.takeLast(maxMessages).forEachIndexed { index, message ->
            array.put(JSONObject().apply {
                put("index", index)
                put("role", message.role)
                put("content_length", message.content.length)
                put("content_preview", preview(message.content, 500))
                put("reasoning_length", message.reasoningContent?.length ?: 0)
                put("tool_call_id", message.toolCallId ?: JSONObject.NULL)
                put("tool_calls", JSONArray(message.toolCalls.orEmpty().map { call ->
                    JSONObject().apply {
                        put("id", call.id)
                        put("name", call.name)
                        put("arguments_length", call.arguments.length)
                        put("arguments_preview", preview(call.arguments, 500))
                    }
                }))
            })
        }
        return array
    }

    fun summarizeTools(tools: List<Map<String, Any>>?): JSONArray {
        val array = JSONArray()
        tools.orEmpty().forEach { tool ->
            val function = tool["function"] as? Map<*, *>
            array.put(JSONObject().apply {
                put("name", function?.get("name")?.toString() ?: "")
                put("description_preview", preview(function?.get("description")?.toString().orEmpty(), 240))
            })
        }
        return array
    }

    fun preview(value: String?, maxLength: Int = MAX_FIELD_LENGTH): String {
        if (value.isNullOrBlank()) return ""
        val compact = value.lineSequence().joinToString("\\n") { it.trim() }
        return if (compact.length <= maxLength) compact else compact.take(maxLength) + "...[truncated:${compact.length}]"
    }

    fun sha256(value: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(value.toByteArray())
        return digest.joinToString("") { "%02x".format(it) }
    }

    private fun normalize(value: Any?): Any {
        return when (value) {
            null -> JSONObject.NULL
            is JSONObject -> value
            is JSONArray -> value
            is String -> preview(value)
            is Number -> value
            is Boolean -> value
            is Map<*, *> -> JSONObject().apply {
                value.forEach { (k, v) -> put(k?.toString() ?: "null", normalize(v)) }
            }
            is Iterable<*> -> JSONArray().apply { value.forEach { put(normalize(it)) } }
            else -> preview(value.toString())
        }
    }

    private fun write(message: String) {
        if (message.length <= MAX_LOG_LINE_LENGTH) {
            Log.d(TAG, message)
            return
        }
        var start = 0
        var part = 1
        val total = (message.length + MAX_LOG_LINE_LENGTH - 1) / MAX_LOG_LINE_LENGTH
        while (start < message.length) {
            val end = minOf(start + MAX_LOG_LINE_LENGTH, message.length)
            Log.d(TAG, "[$part/$total] ${message.substring(start, end)}")
            start = end
            part++
        }
    }
}
