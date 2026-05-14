package cn.com.memcoach

import cn.com.memcoach.agent.AgentOrchestrator
import cn.com.memcoach.agent.AgentSystemPrompt
import cn.com.memcoach.agent.AgentToolRouter
import cn.com.memcoach.agent.llm.OpenAICompatibleAgentLlmClient
import cn.com.memcoach.agent.tool.handlers.ExamToolHandler
import cn.com.memcoach.agent.tool.handlers.KnowledgeToolHandler
import cn.com.memcoach.agent.tool.handlers.MemoryToolHandler
import cn.com.memcoach.agent.tool.handlers.PDFToolHandler
import cn.com.memcoach.channel.MemCoachChannelBridge
import cn.com.memcoach.channel.NativeEventSink
import cn.com.memcoach.data.AppDatabase

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {
    private val activityScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var eventSink: EventChannel.EventSink? = null
    private lateinit var bridge: MemCoachChannelBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val database = AppDatabase.getInstance(applicationContext)
        val toolRouter = AgentToolRouter().apply {
            register(ExamToolHandler(database.examQuestionDao(), database.studyRecordDao(), database.userMasteryDao()))
            register(KnowledgeToolHandler(database.knowledgeNodeDao(), database.knowledgeEdgeDao()))
            register(MemoryToolHandler(database.userMasteryDao(), database.knowledgeNodeDao()))
            register(PDFToolHandler())
        }
        val llmConfig = defaultLlmConfig()
        val orchestrator = AgentOrchestrator(
            llmClient = OpenAICompatibleAgentLlmClient(
                baseUrl = llmConfig.baseUrl,
                apiKey = llmConfig.apiKey,
                defaultModel = llmConfig.defaultModel
            ),
            toolRouter = toolRouter,
            systemPrompt = AgentSystemPrompt()
        )

        bridge = MemCoachChannelBridge(
            orchestrator = orchestrator,
            scope = activityScope,
            eventSink = object : NativeEventSink {
                override fun success(event: Map<String, Any?>) {
                    activityScope.launch(Dispatchers.Main.immediate) {
                        eventSink?.success(event)
                    }
                }

                override fun error(code: String, message: String?, details: Any?) {
                    activityScope.launch(Dispatchers.Main.immediate) {
                        eventSink?.error(code, message, details)
                    }
                }

                override fun endOfStream() {
                    activityScope.launch(Dispatchers.Main.immediate) {
                        eventSink?.endOfStream()
                    }
                }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mem_coach/native")
            .setMethodCallHandler { call, result ->
                val args = call.arguments.toStringKeyMap()
                activityScope.launch {
                    try {
                        result.success(bridge.handleMethodCall(call.method, args))
                    } catch (e: Throwable) {
                        result.error("NATIVE_ERROR", e.message, null)
                    }
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "mem_coach/agent_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        database.openHelper.writableDatabase
    }

    private fun defaultLlmConfig(): LlmConfig = LlmConfig(
        baseUrl = "https://token-plan-cn.xiaomimimo.com/v1",
        apiKey = "tp-cs8d8m6mm5p27npmgzedhzutk8dadawugl6lzvp7ipn1ogwv",
        defaultModel = "mimo-v2.5-pro"
    )

    private data class LlmConfig(
        val baseUrl: String,
        val apiKey: String,
        val defaultModel: String
    )

    override fun onDestroy() {
        activityScope.cancel()
        super.onDestroy()
    }
}

private fun Any?.toStringKeyMap(): Map<String, Any?> {
    val source = this as? Map<*, *> ?: return emptyMap()
    return source.mapNotNull { (key, value) ->
        (key as? String)?.let { it to value }
    }.toMap()
}
