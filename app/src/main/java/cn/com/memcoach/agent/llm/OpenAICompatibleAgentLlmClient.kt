package cn.com.memcoach.agent.llm

import cn.com.memcoach.agent.AgentLlmClient
import cn.com.memcoach.agent.ChatMessage
import cn.com.memcoach.agent.LlmModelInfo
import cn.com.memcoach.agent.LlmStreamChunk
import cn.com.memcoach.agent.LlmTokenUsage
import cn.com.memcoach.agent.LlmToolCallChunk
import cn.com.memcoach.agent.LlmToolCallFunction
import cn.com.memcoach.agent.LlmTurnResult
import cn.com.memcoach.agent.ModelTier
import cn.com.memcoach.agent.ToolCall
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

/** OpenAI Chat Completions 兼容客户端，适配 OpenAI、DeepSeek、通义千问兼容接口等。 */
class OpenAICompatibleAgentLlmClient(
    private val baseUrl: String,
    private val apiKey: String,
    private val defaultModel: String
) : AgentLlmClient {
    override suspend fun streamTurn(
        messages: List<ChatMessage>,
        tools: List<Map<String, Any>>?,
        modelId: String?,
        onChunk: suspend (LlmStreamChunk) -> Unit
    ): LlmTurnResult {
        return withContext(Dispatchers.IO) {
            var response: HttpURLConnection? = null
            try {
                response = postChat(messages, tools, modelId, stream = true)
                val content = StringBuilder()
                val toolCalls = mutableMapOf<Int, ToolCallBuilder>()
                var finishReason: String? = null
                var usage: LlmTokenUsage? = null

                val reader = BufferedReader(InputStreamReader(response.inputStream))
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    val currentLine = line ?: continue
                    val chunk = parseStreamLine(currentLine, toolCalls) ?: continue
                    chunk.usage?.let { usage = it }
                    chunk.finishReason?.let { finishReason = it }
                    chunk.content?.let { content.append(it) }
                    onChunk(chunk)
                }

                LlmTurnResult(
                    content = content.toString(),
                    toolCalls = toolCalls.toSortedMap().values.mapNotNull { it.toToolCallOrNull() },
                    finishReason = finishReason,
                    modelId = modelId ?: defaultModel,
                    usage = usage
                )
            } catch (e: Exception) {
                val message = friendlyError(e)
                onChunk(LlmStreamChunk(content = "\n[$message]", finishReason = "error"))
                LlmTurnResult(
                    content = "\n[$message]",
                    finishReason = "error",
                    modelId = modelId ?: defaultModel
                )
            } finally {
                response?.disconnect()
            }
        }
    }

    override suspend fun completeTurn(messages: List<ChatMessage>, tools: List<Map<String, Any>>?, modelId: String?): LlmTurnResult = withContext(Dispatchers.IO) {
        var response: HttpURLConnection? = null
        try {
            response = postChat(messages, tools, modelId, stream = false)
            val body = response.inputStream.bufferedReader().use { it.readText() }
            val json = JSONObject(body)
            val choice = json.optJSONArray("choices")?.optJSONObject(0)
                ?: error("LLM 返回为空：choices 缺失")
            val message = choice.optJSONObject("message") ?: JSONObject()
            val toolCalls = parseToolCalls(message.optJSONArray("tool_calls"))
            LlmTurnResult(
                content = message.optString("content", ""),
                toolCalls = toolCalls,
                finishReason = choice.optString("finish_reason").takeIf { it.isNotBlank() && it != "null" },
                modelId = json.optString("model", modelId ?: defaultModel),
                usage = json.optJSONObject("usage")?.toUsage()
            )
        } catch (e: Exception) {
            LlmTurnResult(
                content = "[${friendlyError(e)}]",
                finishReason = "error",
                modelId = modelId ?: defaultModel
            )
        } finally {
            response?.disconnect()
        }
    }

    override fun getAvailableModels(): List<LlmModelInfo> = listOf(
        LlmModelInfo(defaultModel, defaultModel, ModelTier.STANDARD, isDefault = true)
    )

    override fun getModelDisplayName(modelId: String): String = modelId

    private fun postChat(messages: List<ChatMessage>, tools: List<Map<String, Any>>?, modelId: String?, stream: Boolean): HttpURLConnection {
        val normalizedBaseUrl = baseUrl.trim().trimEnd('/')
        require(normalizedBaseUrl.isNotBlank()) { "LLM baseUrl 不能为空" }
        require(defaultModel.isNotBlank()) { "LLM defaultModel 不能为空" }

        val url = URL("$normalizedBaseUrl/chat/completions")
        val connection = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 30_000
            readTimeout = 120_000
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("Accept", if (stream) "text/event-stream" else "application/json")
            apiKey.trim().takeIf { it.isNotBlank() }?.let {
                setRequestProperty("Authorization", "Bearer $it")
            }
        }
        val payload = JSONObject().apply {
            put("model", modelId?.takeIf { it.isNotBlank() } ?: defaultModel)
            put("stream", stream)
            put("messages", JSONArray(messages.map { it.toJson() }))
            if (!tools.isNullOrEmpty()) put("tools", JSONArray(tools.map { JSONObject(it) }))
        }
        OutputStreamWriter(connection.outputStream).use { it.write(payload.toString()) }
        val code = connection.responseCode
        if (code !in 200..299) {
            val body = connection.errorStream?.bufferedReader()?.use { it.readText() }
                ?: connection.inputStreamOrNull()?.bufferedReader()?.use { it.readText() }
                ?: ""
            connection.disconnect()
            error("LLM 请求失败：HTTP $code ${body.compactForLog()}")
        }
        return connection
    }

    private fun parseStreamLine(line: String, toolCalls: MutableMap<Int, ToolCallBuilder>): LlmStreamChunk? {
        if (!line.startsWith("data:")) return null
        val data = line.removePrefix("data:").trim()
        if (data == "[DONE]" || data.isBlank()) return null
        val json = runCatching { JSONObject(data) }.getOrNull() ?: return null
        val usage = json.optJSONObject("usage")?.toUsage()
        val choice = json.optJSONArray("choices")?.optJSONObject(0) ?: return LlmStreamChunk(usage = usage)
        val finishReason = choice.optString("finish_reason").takeIf { it.isNotBlank() && it != "null" }
        val delta = choice.optJSONObject("delta") ?: JSONObject()
        val text = delta.optString("content").takeIf { it.isNotEmpty() }
        val chunks = mutableListOf<LlmToolCallChunk>()
        val toolArray = delta.optJSONArray("tool_calls")
        if (toolArray != null) {
            for (i in 0 until toolArray.length()) {
                val item = toolArray.optJSONObject(i) ?: continue
                val index = item.optInt("index", i)
                val fn = item.optJSONObject("function")
                val id = item.optString("id").takeIf { it.isNotBlank() }
                val name = fn?.optString("name")?.takeIf { it.isNotBlank() }
                val arguments = fn?.optString("arguments")?.takeIf { it.isNotEmpty() }
                val builder = toolCalls.getOrPut(index) { ToolCallBuilder() }
                id?.let { builder.id = it }
                name?.let { builder.name = it }
                arguments?.let { builder.arguments.append(it) }
                chunks.add(
                    LlmToolCallChunk(
                        index = index,
                        id = id,
                        function = LlmToolCallFunction(name = name, arguments = arguments)
                    )
                )
            }
        }
        return LlmStreamChunk(
            content = text,
            finishReason = finishReason,
            toolCalls = chunks.ifEmpty { null },
            usage = usage
        )
    }

    private fun ChatMessage.toJson(): JSONObject = JSONObject().apply {
        put("role", role)
        put("content", content)
        if (role == "tool") put("tool_call_id", toolCallId)
        if (!toolCalls.isNullOrEmpty()) {
            put("tool_calls", JSONArray(toolCalls.map { call ->
                JSONObject().apply {
                    put("id", call.id)
                    put("type", "function")
                    put("function", JSONObject().apply {
                        put("name", call.name)
                        put("arguments", call.arguments)
                    })
                }
            }))
        }
    }

    private fun parseToolCalls(array: JSONArray?): List<ToolCall> {
        if (array == null) return emptyList()
        return List(array.length()) { i ->
            val item = array.getJSONObject(i)
            val fn = item.getJSONObject("function")
            ToolCall(item.optString("id"), fn.optString("name"), fn.optString("arguments", "{}"))
        }
    }

    private fun JSONObject.toUsage(): LlmTokenUsage = LlmTokenUsage(
        promptTokens = optInt("prompt_tokens").takeIf { has("prompt_tokens") },
        completionTokens = optInt("completion_tokens").takeIf { has("completion_tokens") }
    )

    private fun HttpURLConnection.inputStreamOrNull() = runCatching { inputStream }.getOrNull()

    private fun String.compactForLog(maxLength: Int = 800): String =
        lineSequence().joinToString(" ") { it.trim() }.take(maxLength)

    private fun friendlyError(error: Exception): String {
        val message = error.message?.takeIf { it.isNotBlank() } ?: error::class.java.simpleName
        return "LLM 请求失败：$message"
    }

    private class ToolCallBuilder {
        var id: String = ""
        var name: String = ""
        val arguments = StringBuilder()
        fun toToolCallOrNull(): ToolCall? {
            if (name.isBlank()) return null
            return ToolCall(
                id = id.ifBlank { "tool_${name}_${hashCode()}" },
                name = name,
                arguments = arguments.toString().ifBlank { "{}" }
            )
        }
    }
}
