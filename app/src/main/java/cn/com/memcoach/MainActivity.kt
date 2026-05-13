package cn.com.memcoach

import cn.com.memcoach.agent.AgentOrchestrator
import cn.com.memcoach.agent.AgentSystemPrompt
import cn.com.memcoach.agent.AgentToolRouter
import cn.com.memcoach.agent.llm.EchoAgentLlmClient
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
        val orchestrator = AgentOrchestrator(
            llmClient = EchoAgentLlmClient(),

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
                val args = call.arguments as? Map<String, Any?> ?: emptyMap()
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

    override fun onDestroy() {
        activityScope.cancel()
        super.onDestroy()
    }
}
