package cn.com.memcoach

import cn.com.memcoach.agent.AgentContextCompactor
import cn.com.memcoach.agent.AgentOrchestrator
import cn.com.memcoach.agent.AgentSystemPrompt
import cn.com.memcoach.agent.AgentToolRouter
import cn.com.memcoach.agent.ModelTier
import cn.com.memcoach.agent.StudyStateMachine
import cn.com.memcoach.agent.llm.AgentLlmRouter
import cn.com.memcoach.agent.llm.OpenAICompatibleAgentLlmClient
import cn.com.memcoach.agent.memory.DailyMemoryService
import cn.com.memcoach.agent.memory.LongTermMemoryService
import cn.com.memcoach.agent.tool.handlers.DailyMemoryToolHandler
import cn.com.memcoach.agent.tool.handlers.ExamToolHandler
import cn.com.memcoach.agent.tool.handlers.KnowledgeToolHandler
import cn.com.memcoach.agent.tool.handlers.LongTermMemoryToolHandler
import cn.com.memcoach.agent.tool.handlers.MemoryToolHandler
import cn.com.memcoach.agent.tool.handlers.PDFToolHandler
import cn.com.memcoach.agent.tool.handlers.SystemToolHandler
import cn.com.memcoach.agent.tool.handlers.WebSearchToolHandler
import cn.com.memcoach.agent.tool.mcp.RemoteMcpClient
import cn.com.memcoach.channel.MemCoachChannelBridge
import cn.com.memcoach.channel.NativeEventSink
import cn.com.memcoach.data.AppDatabase
import cn.com.memcoach.pdf.PdfDocumentRepository
import cn.com.memcoach.pipeline.PdfPipelineService
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
        val pdfRepository = PdfDocumentRepository(applicationContext, database.pdfDocumentDao())
        val llmConfig = defaultLlmConfig()
        val llmClient = OpenAICompatibleAgentLlmClient(
            baseUrl = llmConfig.baseUrl,
            apiKey = llmConfig.apiKey,
            defaultModel = llmConfig.defaultModel
        )

        val pipelineService = PdfPipelineService(
            context = applicationContext,
            questionDao = database.examQuestionDao(),
            llmClient = llmClient
        )

        // 初始化记忆服务
        val memoryDir = java.io.File(applicationContext.filesDir, "memory")
        val dailyMemoryService = DailyMemoryService(
            memoryDir = memoryDir,
            studyRecordDao = database.studyRecordDao(),
            userMasteryDao = database.userMasteryDao(),
            knowledgeNodeDao = database.knowledgeNodeDao()
        )
        val longTermMemoryService = LongTermMemoryService(memoryDir)

        val toolRouter = AgentToolRouter().apply {
            register(ExamToolHandler(database.examQuestionDao(), database.studyRecordDao(), database.userMasteryDao()))
            register(KnowledgeToolHandler(database.knowledgeNodeDao(), database.knowledgeEdgeDao()))
            register(MemoryToolHandler(database.userMasteryDao(), database.knowledgeNodeDao()))
            register(PDFToolHandler(pipelineService, pdfRepository, activityScope))
            register(DailyMemoryToolHandler(dailyMemoryService))
            register(LongTermMemoryToolHandler(longTermMemoryService))
            
            // 注册通用基础工具
            register(WebSearchToolHandler())
            register(SystemToolHandler())
            
            // 注册 Remote MCP Client
            // 实际应用中，服务器地址应该从配置或用户设置中获取
            val mcpClient = RemoteMcpClient("http://localhost:8080")
            activityScope.launch(Dispatchers.IO) {
                mcpClient.initialize()
            }
            register(mcpClient)
        }

        val contextCompactor = AgentContextCompactor(llmClient)
        val studyStateMachine = StudyStateMachine()

        // 初始化 LLM 分层路由器（当前单模型配置，后续可扩展多模型）
        val llmRouter = AgentLlmRouter(
            clients = mapOf(
                ModelTier.LIGHT to llmClient,
                ModelTier.STANDARD to llmClient,
                ModelTier.ADVANCED to llmClient
            ),
            defaultTier = ModelTier.STANDARD
        )

        val orchestrator = AgentOrchestrator(
            llmClient = llmClient,
            toolRouter = toolRouter,
            systemPrompt = AgentSystemPrompt(),
            contextCompactor = contextCompactor,
            stateMachine = studyStateMachine,
            llmRouter = llmRouter,
            dailyMemoryService = dailyMemoryService,
            orchestratorScope = activityScope
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
            },
            studyRecordDao = database.studyRecordDao(),
            userMasteryDao = database.userMasteryDao(),
            pdfRepository = pdfRepository,
            examQuestionDao = database.examQuestionDao(),
            knowledgeNodeDao = database.knowledgeNodeDao(),
            conversationDao = database.conversationDao(),
            chatMessageDao = database.chatMessageDao(),
            pipelineService = pipelineService,
            dailyMemoryService = dailyMemoryService,
            longTermMemoryService = longTermMemoryService
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
        baseUrl = "https://api.deepseek.com/v1",
        apiKey = "sk-5128e904815840ebaaa819d395da66c1",
        defaultModel = "deepseek-v4-flash"
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
