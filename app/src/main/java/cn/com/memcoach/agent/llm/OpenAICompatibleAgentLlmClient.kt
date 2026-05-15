package cn.com.memcoach.agent.llm

import cn.com.memcoach.agent.AgentLlmClient
import cn.com.memcoach.agent.AgentTraceLogger
import cn.com.memcoach.agent.ChatMessage
import cn.com.memcoach.agent.LlmModelInfo
import cn.com.memcoach.agent.LlmStreamChunk
import cn.com.memcoach.agent.LlmTokenUsage
import cn.com.memcoach.agent.LlmToolCallChunk
import cn.com.memcoach.agent.LlmToolCallFunction
import cn.com.memcoach.agent.LlmTurnResult
import cn.com.memcoach.agent.ModelTier
import cn.com.memcoach.agent.ToolCall
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.TimeUnit

/** OpenAI Chat Completions 兼容客户端，适配 OpenAI、DeepSeek、通义千问兼容接口等。 */
class OpenAICompatibleAgentLlmClient(
    private val baseUrl: String,
    private val apiKey: String,
    private val defaultModel: String
) : AgentLlmClient {
    companion object {
        private const val TAG = "LLM_CLIENT"
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
        private val SSE_MEDIA_TYPE = "text/event-stream; charset=utf-8".toMediaType()
    }

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(300, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .connectionPool(okhttp3.ConnectionPool(5, 1, TimeUnit.MINUTES))
        .build()

    override suspend fun streamTurn(
        messages: List<ChatMessage>,
        tools: List<Map<String, Any>>?,
        modelId: String?,
        onChunk: suspend (LlmStreamChunk) -> Unit
    ): LlmTurnResult = withContext(Dispatchers.IO) {
        val traceId = AgentTraceLogger.newTraceId("llm_stream")
        val startedAt = System.currentTimeMillis()
        try {
            val request = buildRequest(messages, tools, modelId, stream = true, traceId = traceId)
            val response = client.newCall(request).execute()
            val content = StringBuilder()
            val reasoning = StringBuilder()
            val toolCalls = mutableMapOf<Int, ToolCallBuilder>()
            var finishReason: String? = null
            var usage: LlmTokenUsage? = null

            response.use { resp ->
                if (!resp.isSuccessful) {
                    val errorBody = resp.body?.string()?.compactForLog() ?: ""
                    Log.e(TAG, "LLM HTTP 错误: ${resp.code}, Body: $errorBody")
                    error("LLM 请求失败：HTTP ${resp.code} $errorBody")
                }

                val reader = BufferedReader(InputStreamReader(resp.body?.byteStream()))
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    val currentLine = line ?: continue
                    val chunk = parseStreamLine(currentLine, toolCalls) ?: continue
                    chunk.usage?.let { usage = it }
                    chunk.finishReason?.let { finishReason = it }
                    chunk.content?.let { content.append(it) }
                    chunk.reasoningContent?.let { reasoning.append(it) }
                    if (!chunk.content.isNullOrBlank() || !chunk.reasoningContent.isNullOrBlank() || !chunk.toolCalls.isNullOrEmpty() || !chunk.finishReason.isNullOrBlank()) {
                        AgentTraceLogger.event(
                            "llm_stream_chunk",
                            mapOf(
                                "trace_id" to traceId,
                                "model" to (modelId ?: defaultModel),
                                "content_delta" to chunk.content,
                                "reasoning_delta" to chunk.reasoningContent,
                                "finish_reason" to chunk.finishReason,
                                "tool_calls" to chunk.toolCalls.orEmpty().map { tc ->
                                    mapOf(
                                        "index" to tc.index,
                                        "id" to tc.id,
                                        "name" to tc.function?.name,
                                        "arguments_delta" to tc.function?.arguments
                                    )
                                }
                            )
                        )
                    }
                    onChunk(chunk)
                }
            }

            val finalToolCalls = toolCalls.toSortedMap().values.mapNotNull { it.toToolCallOrNull() }
            AgentTraceLogger.event(
                "llm_stream_response",
                mapOf(
                    "trace_id" to traceId,
                    "model" to (modelId ?: defaultModel),
                    "duration_ms" to (System.currentTimeMillis() - startedAt),
                    "finish_reason" to finishReason,
                    "content_length" to content.length,
                    "content_preview" to content.toString(),
                    "reasoning_length" to reasoning.length,
                    "reasoning_preview" to reasoning.toString(),
                    "tool_calls" to finalToolCalls.map { call ->
                        mapOf(
                            "id" to call.id,
                            "name" to call.name,
                            "arguments_length" to call.arguments.length,
                            "arguments_preview" to call.arguments
                        )
                    },
                    "prompt_tokens" to usage?.promptTokens,
                    "completion_tokens" to usage?.completionTokens
                )
            )
            LlmTurnResult(
                content = content.toString(),
                toolCalls = finalToolCalls,
                finishReason = finishReason,
                modelId = modelId ?: defaultModel,
                usage = usage
            )
        } catch (e: Exception) {
            Log.e(TAG, "streamTurn 异常", e)
            val message = friendlyError(e)
            onChunk(LlmStreamChunk(content = "\n[$message]", finishReason = "error"))
            LlmTurnResult(
                content = "\n[$message]",
                finishReason = "error",
                modelId = modelId ?: defaultModel
            )
        }
    }

    override suspend fun completeTurn(messages: List<ChatMessage>, tools: List<Map<String, Any>>?, modelId: String?): LlmTurnResult = withContext(Dispatchers.IO) {
        try {
            val request = buildRequest(messages, tools, modelId, stream = false)
            val response = client.newCall(request).execute()

            response.use { resp ->
                if (!resp.isSuccessful) {
                    val errorBody = resp.body?.string()?.compactForLog() ?: ""
                    Log.e(TAG, "LLM HTTP 错误: ${resp.code}, Body: $errorBody")
                    error("LLM 请求失败：HTTP ${resp.code} $errorBody")
                }

                val body = resp.body?.string() ?: error("LLM 返回为空")
                val json = JSONObject(body)
                val choice = json.optJSONArray("choices")?.optJSONObject(0)
                    ?: error("LLM 返回为空：choices 缺失")
                val message = choice.optJSONObject("message") ?: JSONObject()
                val toolCalls = parseToolCalls(message.optJSONArray("tool_calls"))
                LlmTurnResult(
                    content = message.optStringSafe("content", ""),
                    toolCalls = toolCalls,
                    finishReason = message.optStringSafe("finish_reason").takeIf { it.isNotBlank() },
                    modelId = json.optStringSafe("model", modelId ?: defaultModel),
                    usage = json.optJSONObject("usage")?.toUsage()
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "completeTurn 异常", e)
            LlmTurnResult(
                content = "[${friendlyError(e)}]",
                finishReason = "error",
                modelId = modelId ?: defaultModel
            )
        }
    }

    override fun getAvailableModels(): List<LlmModelInfo> = listOf(
        LlmModelInfo(defaultModel, defaultModel, ModelTier.STANDARD, isDefault = true)
    )

    override fun getModelDisplayName(modelId: String): String = modelId

    private fun buildRequest(messages: List<ChatMessage>, tools: List<Map<String, Any>>?, modelId: String?, stream: Boolean): Request {
        val normalizedBaseUrl = baseUrl.trim().trimEnd('/')
        require(normalizedBaseUrl.isNotBlank()) { "LLM baseUrl 不能为空" }
        require(defaultModel.isNotBlank()) { "LLM defaultModel 不能为空" }

        val url = "$normalizedBaseUrl/chat/completions"
        Log.d(TAG, "请求 URL: $url")

        val payload = JSONObject().apply {
            put("model", modelId?.takeIf { it.isNotBlank() } ?: defaultModel)
            put("stream", stream)
            put("messages", JSONArray(messages.map { it.toJson() }))
            if (!tools.isNullOrEmpty()) {
                put("tools", JSONArray(tools.map { tool ->
                    JSONObject(tool).apply {
                        val fn = optJSONObject("function")
                        if (fn != null && fn.has("parameters")) {
                            val params = fn.opt("parameters")
                            if (params is String && params.isNotBlank()) {
                                try {
                                    fn.put("parameters", JSONObject(params))
                                } catch (e: Exception) {
                                    Log.e(TAG, "Failed to parse tool parameters as JSON: $params", e)
                                }
                            }
                        }
                    }
                }))
            }
        }

        val payloadStr = payload.toString()
        Log.d(TAG, "请求 Payload: $payloadStr")

        return Request.Builder()
            .url(url)
            .post(payloadStr.toRequestBody(JSON_MEDIA_TYPE))
            .header("Content-Type", "application/json")
            .header("Accept", if (stream) "text/event-stream" else "application/json")
            .apply {
                apiKey.trim().takeIf { it.isNotBlank() }?.let {
                    header("Authorization", "Bearer $it")
                }
            }
            .build()
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
        
        // 关键修复：同时支持 content 和 reasoning_content，并严格过滤 "null" 字符串
        val text = delta.optStringSafe("content").takeIf { it.isNotEmpty() }
        val reasoning = delta.optStringSafe("reasoning_content").takeIf { it.isNotEmpty() }
        
        val chunks = mutableListOf<LlmToolCallChunk>()
        val toolArray = delta.optJSONArray("tool_calls")
        if (toolArray != null) {
            for (i in 0 until toolArray.length()) {
                val item = toolArray.optJSONObject(i) ?: continue
                val index = item.optInt("index", i)
                val id = item.optStringSafe("id").takeIf { it.isNotBlank() }
                val fn = item.optJSONObject("function")
                val name = fn?.optStringSafe("name")?.takeIf { it.isNotBlank() }
                val arguments = fn?.optStringSafe("arguments")?.takeIf { it.isNotEmpty() }
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
            reasoningContent = reasoning,
            finishReason = finishReason,
            toolCalls = chunks.ifEmpty { null },
            usage = usage
        )
    }

    private fun ChatMessage.toJson(): JSONObject = JSONObject().apply {
        put("role", role)
        put("content", content)
        if (reasoningContent != null) {
            put("reasoning_content", reasoningContent)
        }
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
        val result = mutableListOf<ToolCall>()
        for (i in 0 until array.length()) {
            val item = array.getJSONObject(i)
            val fn = item.getJSONObject("function")
            val id = item.optStringSafe("id").takeIf { it.isNotBlank() } ?: "call_${System.currentTimeMillis()}_$i"
            val name = fn.optStringSafe("name").takeIf { it.isNotBlank() } ?: continue
            val args = fn.optStringSafe("arguments", "{}").ifBlank { "{}" }
            result.add(ToolCall(id, name, args))
        }
        return result
    }

    private fun JSONObject.optStringSafe(name: String, fallback: String = ""): String {
        if (!this.has(name)) return fallback
        val value = opt(name)
        return if (value == null || value == JSONObject.NULL || value.toString() == "null") {
            fallback
        } else {
            value.toString()
        }
    }

    private fun JSONObject.toUsage(): LlmTokenUsage = LlmTokenUsage(
        promptTokens = optInt("prompt_tokens").takeIf { has("prompt_tokens") },
        completionTokens = optInt("completion_tokens").takeIf { has("completion_tokens") }
    )

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