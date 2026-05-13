package cn.com.memcoach.channel

import cn.com.memcoach.agent.AgentInput
import cn.com.memcoach.agent.AgentOrchestrator
import cn.com.memcoach.agent.AgentPromptContext
import cn.com.memcoach.agent.ConversationMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * Flutter-Native 通信桥。
 *
 * 该类只定义通道边界，不依赖具体 Activity，后续 Android 壳工程补齐后在 FlutterEngine 中注册：
 * - MethodChannel: mem_coach/native
 * - EventChannel: mem_coach/agent_events
 */
class MemCoachChannelBridge(
    private val orchestrator: AgentOrchestrator,
    private val scope: CoroutineScope,
    private val eventSink: NativeEventSink
) {
    private var currentAgentJob: Job? = null

    suspend fun handleMethodCall(method: String, arguments: Map<String, Any?>): Any? {
        return when (method) {
            "agent.startTurn" -> startAgentTurn(arguments)
            "agent.cancelTurn" -> cancelAgentTurn()
            "pdf.upload" -> uploadPdf(arguments)
            else -> error("Unsupported native method: $method")
        }
    }

    private suspend fun startAgentTurn(arguments: Map<String, Any?>): String {
        val message = arguments["message"] as? String ?: return ""
        val history = parseHistory(arguments["history"])
        val context = AgentPromptContext()

        currentAgentJob?.cancel()
        currentAgentJob = scope.launch {
            orchestrator.run(
                AgentInput(
                    userMessage = message,
                    conversationHistory = history,
                    context = context
                )
            ).collect { event ->
                eventSink.success(AgentEventMapper.toMap(event))
            }
        }

        return "started"
    }

    private fun cancelAgentTurn(): String {
        currentAgentJob?.cancel()
        currentAgentJob = null
        return "cancelled"
    }

    private fun uploadPdf(arguments: Map<String, Any?>): String {
        val path = arguments["path"] as? String ?: return ""
        return path
    }

    private fun parseHistory(raw: Any?): List<ConversationMessage> {
        val items = raw as? List<*> ?: return emptyList()
        return items.mapNotNull { item ->
            val map = item as? Map<*, *> ?: return@mapNotNull null
            ConversationMessage(
                role = map["role"] as? String ?: return@mapNotNull null,
                content = map["content"] as? String ?: ""
            )
        }
    }
}

interface NativeEventSink {
    fun success(event: Map<String, Any?>)
    fun error(code: String, message: String?, details: Any? = null)
    fun endOfStream()
}
