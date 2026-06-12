package cn.com.memcoach.channel

import cn.com.memcoach.agent.AgentInput
import cn.com.memcoach.agent.AgentEvent
import cn.com.memcoach.agent.AgentOrchestrator
import cn.com.memcoach.agent.AgentPromptContext
import cn.com.memcoach.agent.AgentReasoningEffort
import cn.com.memcoach.agent.AgentToolRouter
import cn.com.memcoach.agent.ConversationMessage

import cn.com.memcoach.pdf.PdfDocumentRepository
import cn.com.memcoach.pdf.toMap
import cn.com.memcoach.study.AnswerSubmissionRecorder
import cn.com.memcoach.data.entity.AgentEventEntity
import cn.com.memcoach.data.entity.ChatMessageEntity
import cn.com.memcoach.data.entity.ConversationEntity
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * Flutter-Native 通信桥。
 *
 * 该类只定义通道边界，不依赖具体 Activity，后续 Android 壳工程补齐后在 FlutterEngine 中注册：
 * - MethodChannel: mem_coach/native
 * - EventChannel: mem_coach/agent_events
 */
class MemCoachChannelBridge(
    private val orchestrator: AgentOrchestrator,
    private val toolRouter: AgentToolRouter,
    private val scope: CoroutineScope,
    private val eventSink: NativeEventSink,
    private val studyRecordDao: cn.com.memcoach.data.dao.StudyRecordDao,
    private val userMasteryDao: cn.com.memcoach.data.dao.UserMasteryDao,
    private val answerSubmissionRecorder: AnswerSubmissionRecorder,
    private val pdfRepository: PdfDocumentRepository,
    private val examQuestionDao: cn.com.memcoach.data.dao.ExamQuestionDao,
    private val knowledgeNodeDao: cn.com.memcoach.data.dao.KnowledgeNodeDao,
    private val conversationDao: cn.com.memcoach.data.dao.ConversationDao,
    private val chatMessageDao: cn.com.memcoach.data.dao.ChatMessageDao,
    private val agentEventDao: cn.com.memcoach.data.dao.AgentEventDao,
    private val pipelineService: cn.com.memcoach.pipeline.PdfPipelineService,
    private val dailyMemoryService: cn.com.memcoach.agent.memory.DailyMemoryService? = null,
    private val longTermMemoryService: cn.com.memcoach.agent.memory.LongTermMemoryService? = null
) {
    private var currentAgentJob: Job? = null
    private var currentAgentConversationId: Long? = null
    private var currentAgentRunId: String? = null

    suspend fun handleMethodCall(method: String, arguments: Map<String, Any?>): Any? {
        return when (method) {
            "agent.startTurn" -> startAgentTurn(arguments)
            "agent.cancelTurn" -> cancelAgentTurn(arguments)
            "agent.isRunning" -> isAgentRunning(arguments)
            "agent.compactContext" -> compactContext(arguments)
            "agent.setReasoningEffort" -> setReasoningEffort(arguments)
            "pdf.upload" -> uploadPdf(arguments)
            "pdf.parseStatus" -> getPdfParseStatus(arguments)
            "pdf.list" -> listPdfs()
            "pdf.questions" -> listPdfQuestions(arguments)
            "pdf.deleteQuestions" -> deletePdfQuestions(arguments)
            "insight.getSummary" -> getInsightSummary()
            "exam.getRandomQuestions" -> getRandomQuestions(arguments)
            "exam.submitAnswer" -> submitAnswer(arguments)
            "knowledge.getTree" -> getKnowledgeTree(arguments)
            "home.getData" -> getHomeData()
            "tool.call" -> callAgentTool(arguments)
            "conversation.create" -> createConversation(arguments)
            "conversation.list" -> listConversations()
            "conversation.getMessages" -> getConversationMessages(arguments)
            "conversation.addMessage" -> addChatMessage(arguments)
            "conversation.updateMessageCount" -> updateConversationMessageCount(arguments)
            "conversation.updateTitle" -> updateConversationTitle(arguments)
            "conversation.delete" -> deleteConversation(arguments)
            "pdf.delete" -> deletePdf(arguments)
            "pdf.getActiveJobs" -> getActivePdfJobs()
            else -> error("Unsupported native method: $method")
        }
    }

    private suspend fun callAgentTool(arguments: Map<String, Any?>): Map<String, Any?> {
        return try {
            val toolName = arguments["tool_name"] as? String ?: return mapOf("error" to "tool_name required")
            val toolArgs = arguments["arguments"] as? Map<*, *> ?: emptyMap<String, Any?>()

            // 简单 JSON 构造
            val argsJson = "{" + toolArgs.entries.joinToString(",") { (k, v) ->
                val value = when (v) {
                    is String -> "\"${v.replace("\"", "\\\"")}\""
                    is Number -> v.toString()
                    is Boolean -> v.toString()
                    null -> "null"
                    else -> "\"$v\""
                }
                "\"$k\":$value"
            } + "}"

            // 调用工具
            val resultJson = toolRouter.execute(toolName, argsJson)

            // 返回
            mapOf("success" to true, "data" to resultJson)
        } catch (e: Exception) {
            mapOf("error" to (e.message ?: "Unknown error"))
        }
    }

    private suspend fun deletePdf(arguments: Map<String, Any?>): Map<String, Any?> {
        val id = arguments["id"] as? String ?: return mapOf("error" to "id is required")
        val deleteQuestions = arguments["delete_questions"] as? Boolean ?: true
        val document = pdfRepository.getDocument(id)
        val deletedQuestionCount = if (deleteQuestions) {
            deleteQuestionsForDocument(id, document?.fileName)
        } else {
            0
        }
        pdfRepository.deleteDocument(id)
        return mapOf("id" to id, "deleted" to true, "deleted_question_count" to deletedQuestionCount)
    }

    private suspend fun listPdfQuestions(arguments: Map<String, Any?>): List<Map<String, Any?>> {
        val id = arguments["id"] as? String ?: return emptyList()
        val document = pdfRepository.getDocument(id)
        val questions = examQuestionDao.getBySourceDocumentId(id).ifEmpty {
            document?.fileName?.let { examQuestionDao.getBySourceFile(it) } ?: emptyList()
        }
        return questions.map { it.toQuestionMap() }
    }

    private suspend fun deletePdfQuestions(arguments: Map<String, Any?>): Map<String, Any?> {
        val id = arguments["id"] as? String ?: return mapOf("error" to "id is required")
        val document = pdfRepository.getDocument(id)
        val deletedCount = deleteQuestionsForDocument(id, document?.fileName)
        return mapOf("id" to id, "deleted_question_count" to deletedCount)
    }

    private suspend fun deleteQuestionsForDocument(documentId: String, sourceFile: String?): Int {
        val byDocumentId = examQuestionDao.deleteBySourceDocumentId(documentId)
        val bySourceFile = sourceFile?.takeIf { it.isNotBlank() }?.let { examQuestionDao.deleteBySourceFile(it) } ?: 0
        return byDocumentId + bySourceFile
    }


    private fun getActivePdfJobs(): List<String> {
        return pipelineService.getActiveJobIds()
    }

    private suspend fun getInsightSummary(): Map<String, Any?> {
        val now = System.currentTimeMillis()
        val oneWeekAgo = now - 7 * 24 * 60 * 60 * 1000L
        
        val totalTime = studyRecordDao.getTotalTimeSpent() ?: 0
        val totalCount = studyRecordDao.getTotalCountSince(startTime = 0)
        val correctCount = studyRecordDao.getCorrectCountSince(startTime = 0)
        val accuracy = if (totalCount > 0) correctCount.toDouble() / totalCount else 0.0
        
        val dailyCounts = studyRecordDao.getDailyCountSince(startTime = oneWeekAgo)
        val dailyAccuracyByDate = studyRecordDao.getDailyAccuracySince(startTime = oneWeekAgo).associateBy { it.date }
        val modeCounts = studyRecordDao.getCountByMode(startTime = oneWeekAgo)
        val subjectProgress = listOf(
            "math" to "数学",
            "logic" to "逻辑",
            "writing" to "写作",
            "english" to "英语"
        ).map { (subject, label) ->
            val tracked = userMasteryDao.getProgressBySubject(subject = subject)
            val totalNodes = knowledgeNodeDao.countBySubject(subject)
            val total = if (totalNodes > 0) totalNodes else tracked.total
            mapOf(
                "subject" to subject,
                "label" to label,
                "learned" to tracked.total,
                "mastered" to tracked.mastered,
                "total" to total,
                "progress" to if (total > 0) tracked.mastered.toDouble() / total else 0.0
            )
        }.filter { (it["total"] as Int) > 0 || (it["learned"] as Int) > 0 }
        val weakPoints = userMasteryDao.getWeakest(limit = 3)
        
        return mapOf(
            "total_study_time_seconds" to totalTime,
            "total_questions" to totalCount,
            "overall_accuracy" to accuracy,
            "daily_stats" to dailyCounts.map { it: cn.com.memcoach.data.dao.DailyStudyCount ->
                val dayAccuracy = dailyAccuracyByDate[it.date]
                val dayTotal = dayAccuracy?.total ?: it.count
                val dayCorrect = dayAccuracy?.correct ?: 0
                mapOf(
                    "date" to it.date,
                    "count" to it.count,
                    "total" to dayTotal,
                    "correct" to dayCorrect,
                    "accuracy" to if (dayTotal > 0) dayCorrect.toDouble() / dayTotal else 0.0
                )
            },
            "mode_counts" to modeCounts.map {
                mapOf(
                    "mode" to it.studyMode,
                    "label" to when (it.studyMode) {
                        cn.com.memcoach.data.entity.StudyRecord.MODE_REVIEW -> "复习"
                        cn.com.memcoach.data.entity.StudyRecord.MODE_MOCK -> "模考"
                        cn.com.memcoach.data.entity.StudyRecord.MODE_MEMORIZE -> "背诵"
                        else -> "练习"
                    },
                    "count" to it.count
                )
            },
            "subject_progress" to subjectProgress,
            "weak_points" to weakPoints.map { mastery: cn.com.memcoach.data.entity.UserMastery ->
                val node = knowledgeNodeDao.getById(mastery.knowledgeId)
                mapOf(
                    "knowledge_id" to mastery.knowledgeId,
                    "name" to (node?.name ?: mastery.knowledgeId),
                    "subject" to (node?.subject ?: ""),
                    "chapter" to (node?.chapter ?: ""),
                    "mastery" to mastery.masteryLevel,
                    "review_count" to mastery.reviewCount,
                    "correct_count" to mastery.correctCount
                )
            }
        )

    }



    private suspend fun startAgentTurn(arguments: Map<String, Any?>): String {
        val message = arguments["message"] as? String ?: return ""
        val history = parseHistory(arguments["history"])
        val pageContext = arguments["context"] as? Map<*, *>
        val context = buildAgentContext(pageContext)
        val conversationId = (arguments["conversationId"] as? Number)?.toLong()
        val runId = "run_${System.currentTimeMillis()}"
        val startedAt = System.currentTimeMillis()

        markCurrentAgentRunCancelled("新的 Agent 请求已开始")
        currentAgentJob?.cancel()
        currentAgentConversationId = conversationId
        currentAgentRunId = runId
        conversationId?.let { id ->
            conversationDao.updateAgentRunState(
                id = id,
                runId = runId,
                status = ConversationEntity.AGENT_STATUS_RUNNING,
                startedAt = startedAt,
                finishedAt = null,
                lastSeq = 0,
                error = null,
                updatedAt = startedAt
            )
        }
        currentAgentJob = scope.launch {
            val toolCalls = mutableListOf<ToolCallSnapshot>()
            val toolResults = mutableListOf<ToolResultSnapshot>()
            val reasoningBuffer = StringBuilder()
            var assistantContent = ""
            var eventSeq = 0L
            var activeRound = 0
            var activeThinkingEntryId: String? = null
            var activeAssistantEntryId: String? = null
            var toolEntrySequence = 0
            val toolEntryIds = mutableMapOf<String, String>()
            val activeIdlessToolEntries = mutableMapOf<String, MutableList<String>>()
            val toolArgsByEntryId = mutableMapOf<String, String>()

            fun nextEventSeq(): Long {
                eventSeq += 1
                return eventSeq
            }

            fun nextToolEntryId(): String {
                toolEntrySequence += 1
                return "$runId-tool-$toolEntrySequence"
            }

            fun toolEntryIdForStart(toolName: String, toolCallId: String?): String {
                val normalizedId = toolCallId?.trim().orEmpty()
                if (normalizedId.isNotBlank()) {
                    return toolEntryIds.getOrPut(normalizedId) { nextToolEntryId() }
                }
                val entryId = nextToolEntryId()
                activeIdlessToolEntries.getOrPut(toolName) { mutableListOf() }.add(entryId)
                return entryId
            }

            fun toolEntryIdForFollowup(
                toolName: String,
                toolCallId: String?,
                consume: Boolean
            ): String {
                val normalizedId = toolCallId?.trim().orEmpty()
                if (normalizedId.isNotBlank()) {
                    return toolEntryIds.getOrPut(normalizedId) { nextToolEntryId() }
                }

                val entries = activeIdlessToolEntries[toolName]
                val entryId = entries?.firstOrNull() ?: nextToolEntryId()
                if (consume && entries != null && entries.isNotEmpty()) {
                    entries.removeAt(0)
                    if (entries.isEmpty()) activeIdlessToolEntries.remove(toolName)
                }
                return entryId
            }

            fun resolvedToolCallId(toolCallId: String?, entryId: String): String {
                return toolCallId?.trim()?.takeIf { it.isNotBlank() } ?: entryId
            }

            fun streamMeta(entryId: String, roundIndex: Int, kind: String): Map<String, Any?> {
                return mapOf(
                    "entryId" to entryId,
                    "roundIndex" to roundIndex.coerceAtLeast(1),
                    "kind" to kind,
                    "parentTaskId" to runId
                )
            }

            fun enrichEventMap(event: AgentEvent): Map<String, Any?> {
                val base = AgentEventMapper.toMap(event).toMutableMap()
                val seq = nextEventSeq()
                val kind = base["type"]?.toString().orEmpty()
                val now = System.currentTimeMillis()
                base["seq"] = seq
                base["taskId"] = runId
                base["runId"] = runId
                base["createdAt"] = now
                base["kind"] = kind

                when (event) {
                    is AgentEvent.ThinkingStart -> {
                        activeRound = event.round
                        activeThinkingEntryId = if (event.round <= 1) {
                            "$runId-thinking"
                        } else {
                            "$runId-thinking-${event.round}"
                        }
                        activeAssistantEntryId = null
                        val entryId = activeThinkingEntryId.orEmpty()
                        base["entryId"] = entryId
                        base["roundIndex"] = activeRound
                        base["streamMeta"] = streamMeta(entryId, activeRound, kind)
                    }

                    is AgentEvent.ThinkingUpdate -> {
                        val entryId = activeThinkingEntryId ?: "$runId-thinking"
                        base["entryId"] = entryId
                        base["roundIndex"] = activeRound.coerceAtLeast(1)
                        base["streamMeta"] = streamMeta(entryId, activeRound, kind)
                    }

                    is AgentEvent.ChatMessage -> {
                        if (activeAssistantEntryId == null) {
                            activeAssistantEntryId = if (activeRound <= 1) {
                                "$runId-text"
                            } else {
                                "$runId-text-$activeRound"
                            }
                        }
                        val entryId = activeAssistantEntryId.orEmpty()
                        base["entryId"] = entryId
                        base["roundIndex"] = activeRound.coerceAtLeast(1)
                        base["streamMeta"] = streamMeta(entryId, activeRound, kind) +
                            mapOf("isFinal" to event.isFinal)
                    }

                    is AgentEvent.ToolCallStart -> {
                        val entryId = toolEntryIdForStart(event.toolName, event.toolCallId)
                        val resolvedToolCallId = resolvedToolCallId(event.toolCallId, entryId)
                        val argsJson = event.arguments
                        toolArgsByEntryId[entryId] = argsJson
                        base["toolCallId"] = resolvedToolCallId
                        base["entryId"] = entryId
                        base["cardId"] = entryId
                        base["roundIndex"] = activeRound.coerceAtLeast(1)
                        base["args"] = argsJson
                        base["argsJson"] = argsJson
                        base["displayName"] = displayNameForTool(event.toolName)
                        base["toolType"] = toolTypeForTool(event.toolName)
                        base["toolTitle"] = extractToolTitle(argsJson)
                            ?: displayNameForTool(event.toolName)
                        base["summary"] = base["toolTitle"]
                        base["status"] = "running"
                        base["success"] = true
                        base["streamMeta"] = streamMeta(entryId, activeRound, kind)
                    }

                    is AgentEvent.ToolCallComplete -> {
                        val entryId = toolEntryIdForFollowup(
                            event.toolName,
                            event.toolCallId,
                            consume = true
                        )
                        val resolvedToolCallId = resolvedToolCallId(event.toolCallId, entryId)
                        val argsJson = toolArgsByEntryId[entryId].orEmpty()
                        val resultJson = normalizeToolJsonPayload(event.result)
                        base["toolCallId"] = resolvedToolCallId
                        base["entryId"] = entryId
                        base["cardId"] = entryId
                        base["roundIndex"] = activeRound.coerceAtLeast(1)
                        base["args"] = argsJson
                        base["argsJson"] = argsJson
                        base["displayName"] = displayNameForTool(event.toolName)
                        base["toolType"] = toolTypeForTool(event.toolName)
                        base["toolTitle"] = extractToolTitle(argsJson)
                            ?: displayNameForTool(event.toolName)
                        base["status"] = "success"
                        base["success"] = true
                        base["summary"] = summarizeToolResult(event.result)
                        base["resultPreviewJson"] = resultJson
                        base["rawResultJson"] = resultJson
                        base["streamMeta"] = streamMeta(entryId, activeRound, kind)
                    }

                    is AgentEvent.ToolCallError -> {
                        val entryId = toolEntryIdForFollowup(
                            event.toolName,
                            event.toolCallId,
                            consume = true
                        )
                        val resolvedToolCallId = resolvedToolCallId(event.toolCallId, entryId)
                        val argsJson = toolArgsByEntryId[entryId].orEmpty()
                        val errorJson = JSONObject().apply {
                            put("error", event.error)
                            put("toolName", event.toolName)
                        }.toString()
                        base["toolCallId"] = resolvedToolCallId
                        base["entryId"] = entryId
                        base["cardId"] = entryId
                        base["roundIndex"] = activeRound.coerceAtLeast(1)
                        base["args"] = argsJson
                        base["argsJson"] = argsJson
                        base["displayName"] = displayNameForTool(event.toolName)
                        base["toolType"] = toolTypeForTool(event.toolName)
                        base["toolTitle"] = extractToolTitle(argsJson)
                            ?: displayNameForTool(event.toolName)
                        base["status"] = "error"
                        base["success"] = false
                        base["summary"] = event.error
                        base["resultPreviewJson"] = errorJson
                        base["rawResultJson"] = errorJson
                        base["streamMeta"] = streamMeta(entryId, activeRound, kind)
                    }

                    is AgentEvent.ToolCallRetry -> {
                        val entryId = toolEntryIdForFollowup(
                            event.toolName,
                            event.toolCallId,
                            consume = false
                        )
                        val resolvedToolCallId = resolvedToolCallId(event.toolCallId, entryId)
                        base["toolCallId"] = resolvedToolCallId
                        base["entryId"] = entryId
                        base["cardId"] = entryId
                        base["roundIndex"] = activeRound.coerceAtLeast(1)
                        base["displayName"] = displayNameForTool(event.toolName)
                        base["toolType"] = toolTypeForTool(event.toolName)
                        base["status"] = "running"
                        base["success"] = true
                        base["progress"] = "第 ${event.attempt} 次调用失败，正在重试：${event.error}"
                        base["streamMeta"] = streamMeta(entryId, activeRound, kind)
                    }

                    is AgentEvent.SkillActivated -> {
                        val entryId = "$runId-skill-${event.skillId}"
                        base["entryId"] = entryId
                        base["roundIndex"] = activeRound.coerceAtLeast(1)
                        base["streamMeta"] = streamMeta(entryId, activeRound, kind)
                    }

                    is AgentEvent.StateChanged,
                    is AgentEvent.ReflectionCheck,
                    is AgentEvent.ContextCompacted,
                    is AgentEvent.Complete,
                    is AgentEvent.Error -> {
                        val entryId = "$runId-event-$seq"
                        base["entryId"] = entryId
                        base["roundIndex"] = activeRound.coerceAtLeast(1)
                        base["streamMeta"] = streamMeta(entryId, activeRound, kind)
                    }
                }
                return base
            }

            try {
                orchestrator.run(
                    AgentInput(
                        userMessage = message,
                        conversationHistory = history,
                        context = context
                    )
                ).collect { event ->
                    val eventMap = enrichEventMap(event)
                    persistAgentEvent(conversationId, runId, eventMap)
                    when (event) {
                        is AgentEvent.ThinkingUpdate -> reasoningBuffer.append(event.content)
                        is AgentEvent.ToolCallStart -> {
                            val toolCallId = eventMap["toolCallId"]?.toString()
                                ?: "tool_${toolCalls.size}_${System.currentTimeMillis()}"
                            toolCalls.add(
                                ToolCallSnapshot(
                                    id = toolCallId,
                                    name = event.toolName,
                                    arguments = event.arguments
                                )
                            )
                        }
                        is AgentEvent.ToolCallComplete -> {
                            toolResults.add(
                                ToolResultSnapshot(
                                    id = eventMap["toolCallId"]?.toString().orEmpty(),
                                    name = event.toolName,
                                    result = event.result
                                )
                            )
                        }
                        is AgentEvent.ChatMessage -> {
                            assistantContent = event.content
                            if (event.isFinal) {
                                persistAgentTurnMessages(
                                    conversationId = conversationId,
                                    runId = runId,
                                    userMessage = message,
                                    assistantContent = assistantContent,
                                    reasoningContent = reasoningBuffer.toString().takeIf { it.isNotBlank() },
                                    toolCalls = toolCalls,
                                    toolResults = toolResults
                                )
                            }
                        }
                        is AgentEvent.Complete -> {
                            markAgentRunFinished(
                                conversationId,
                                runId,
                                ConversationEntity.AGENT_STATUS_COMPLETED,
                                null
                            )
                        }
                        is AgentEvent.Error -> {
                            persistAgentTurnMessages(
                                conversationId = conversationId,
                                runId = runId,
                                userMessage = message,
                                assistantContent = event.message,
                                reasoningContent = reasoningBuffer.toString().takeIf { it.isNotBlank() },
                                toolCalls = toolCalls,
                                toolResults = toolResults
                            )
                            markAgentRunFinished(
                                conversationId,
                                runId,
                                ConversationEntity.AGENT_STATUS_ERROR,
                                event.message
                            )
                        }
                        else -> Unit
                    }
                    eventSink.success(eventMap)
                }
            } catch (e: CancellationException) {
                markAgentRunFinished(
                    conversationId,
                    runId,
                    ConversationEntity.AGENT_STATUS_CANCELLED,
                    null
                )
                throw e
            } catch (e: Exception) {
                val errorMessage = e.message ?: "Agent 运行失败"
                val errorEvent = AgentEvent.Error(errorMessage)
                val eventMap = enrichEventMap(errorEvent)
                persistAgentEvent(conversationId, runId, eventMap)
                persistAgentTurnMessages(
                    conversationId = conversationId,
                    runId = runId,
                    userMessage = message,
                    assistantContent = errorMessage,
                    reasoningContent = reasoningBuffer.toString().takeIf { it.isNotBlank() },
                    toolCalls = toolCalls,
                    toolResults = toolResults
                )
                markAgentRunFinished(
                    conversationId,
                    runId,
                    ConversationEntity.AGENT_STATUS_ERROR,
                    errorMessage
                )
                eventSink.success(eventMap)
            } finally {
                if (currentAgentRunId == runId) {
                    currentAgentJob = null
                    currentAgentConversationId = null
                    currentAgentRunId = null
                }
            }
        }

        return "started"
    }

    private suspend fun markAgentRunFinished(
        conversationId: Long?,
        runId: String,
        status: String,
        error: String?
    ) {
        if (conversationId == null) return
        try {
            conversationDao.finishAgentRun(
                id = conversationId,
                runId = runId,
                status = status,
                error = error
            )
        } catch (e: Exception) {
            android.util.Log.w("MemCoachChannelBridge", "更新 Agent run 状态失败", e)
        }
    }

    private suspend fun markCurrentAgentRunCancelled(reason: String?) {
        val conversationId = currentAgentConversationId ?: return
        val runId = currentAgentRunId ?: return
        markAgentRunFinished(
            conversationId = conversationId,
            runId = runId,
            status = ConversationEntity.AGENT_STATUS_CANCELLED,
            error = reason
        )
    }

    private suspend fun persistAgentEvent(
        conversationId: Long?,
        runId: String,
        event: Map<String, Any?>
    ) {
        if (conversationId == null) return
        val type = event["type"]?.toString() ?: return
        val seq = event["seq"].asLongOrNull() ?: 0L
        val entryId = event["entryId"]?.toString()?.takeIf { it.isNotBlank() && it != "null" }
        val roundIndex = event["roundIndex"].asIntOrNull()
        val status = event["status"]?.toString()?.takeIf { it.isNotBlank() && it != "null" }
        try {
            agentEventDao.insert(
                AgentEventEntity(
                    conversationId = conversationId,
                    runId = runId,
                    eventType = type,
                    payloadJson = mapToJson(event).toString(),
                    seq = seq,
                    entryId = entryId,
                    roundIndex = roundIndex,
                    status = status,
                    createdAt = System.currentTimeMillis()
                )
            )
            if (seq > 0) {
                conversationDao.updateAgentLastSeq(conversationId, runId, seq)
            }
        } catch (e: Exception) {
            android.util.Log.w("MemCoachChannelBridge", "保存 Agent 事件失败", e)
        }
    }

    private suspend fun persistAgentTurnMessages(
        conversationId: Long?,
        runId: String,
        userMessage: String,
        assistantContent: String,
        reasoningContent: String?,
        toolCalls: List<ToolCallSnapshot>,
        toolResults: List<ToolResultSnapshot>
    ) {
        if (conversationId == null) return
        if (assistantContent.isBlank() && toolCalls.isEmpty() && toolResults.isEmpty()) return

        try {
            val now = System.currentTimeMillis()
            val toolCallsJson = buildToolCallsJson(toolCalls)
            chatMessageDao.insert(
                ChatMessageEntity(
                    conversationId = conversationId,
                    role = ChatMessageEntity.ROLE_ASSISTANT,
                    content = assistantContent,
                    thinkingContent = reasoningContent,
                    toolCallsJson = toolCallsJson,
                    runId = runId,
                    entryId = "$runId-text",
                    messageStatus = "completed",
                    createdAt = now
                )
            )
            toolResults.forEachIndexed { index, result ->
                chatMessageDao.insert(
                    ChatMessageEntity(
                        conversationId = conversationId,
                        role = ChatMessageEntity.ROLE_TOOL,
                        content = result.result,
                        toolName = result.name,
                        toolStatus = ChatMessageEntity.TOOL_STATUS_SUCCESS,
                        toolResult = result.result,
                        toolCallId = result.id.takeIf { it.isNotBlank() },
                        runId = runId,
                        entryId = result.id.takeIf { it.isNotBlank() },
                        messageStatus = "completed",
                        createdAt = now + index + 1
                    )
                )
            }

            val count = chatMessageDao.getCountByConversationId(conversationId)
            conversationDao.updateMessageCount(conversationId, count)
            conversationDao.updateTimestamp(conversationId, System.currentTimeMillis())
            updateDefaultConversationTitle(conversationId, userMessage)
        } catch (e: Exception) {
            android.util.Log.w("MemCoachChannelBridge", "保存 Agent 回复失败", e)
        }
    }

    private suspend fun updateDefaultConversationTitle(conversationId: Long, userMessage: String) {
        val conversation = conversationDao.getById(conversationId) ?: return
        if (conversation.title != "新对话") return
        val title = userMessage.trim().let { text ->
            if (text.length > 20) "${text.take(20)}..." else text
        }
        if (title.isNotBlank()) {
            conversationDao.updateTitle(conversationId, title)
        }
    }

    private fun buildToolCallsJson(toolCalls: List<ToolCallSnapshot>): String? {
        if (toolCalls.isEmpty()) return null
        val array = org.json.JSONArray()
        toolCalls.forEach { call ->
            array.put(JSONObject().apply {
                put("id", call.id)
                put("name", call.name)
                put("arguments", call.arguments)
            })
        }
        return array.toString()
    }

    private fun mapToJson(map: Map<String, Any?>): JSONObject {
        return JSONObject().apply {
            map.forEach { (key, value) ->
                put(key, value)
            }
        }
    }

    private fun displayNameForTool(toolName: String): String {
        return when (toolName) {
            "exam_question_search" -> "检索真题"
            "exam_question_get" -> "读取真题"
            "exam_question_explain" -> "解析真题"
            "exam_similar_find" -> "查找相似题"
            "knowledge_search" -> "检索知识点"
            "knowledge_get" -> "读取知识点"
            "learning_insight_get" -> "读取学情"
            "vocabulary_search" -> "检索单词"
            "vocabulary_add" -> "添加单词"
            "vocabulary_parse" -> "解析单词"
            "pdf_query" -> "查询 PDF"
            else -> toolName.replace('_', ' ')
        }
    }

    private fun toolTypeForTool(toolName: String): String {
        return when {
            toolName.startsWith("exam_") -> "exam"
            toolName.startsWith("knowledge_") -> "knowledge"
            toolName.startsWith("vocabulary_") -> "vocabulary"
            toolName.startsWith("learning_") -> "insight"
            toolName.startsWith("pdf_") -> "pdf"
            else -> "builtin"
        }
    }

    private fun extractToolTitle(argsJson: String): String? {
        if (argsJson.isBlank()) return null
        return try {
            JSONObject(argsJson).optString("tool_title").trim().takeIf { it.isNotBlank() }
        } catch (_: Exception) {
            null
        }
    }

    private fun normalizeToolJsonPayload(raw: String): String {
        val text = raw.trim()
        if (text.isEmpty()) return JSONObject().toString()
        return try {
            when {
                text.startsWith("{") -> JSONObject(text).toString()
                text.startsWith("[") -> org.json.JSONArray(text).toString()
                else -> JSONObject().apply { put("text", text) }.toString()
            }
        } catch (_: Exception) {
            JSONObject().apply { put("text", text) }.toString()
        }
    }

    private fun summarizeToolResult(raw: String): String {
        val text = raw.trim()
        if (text.isEmpty()) return "工具执行完成"
        val summary = try {
            val obj = JSONObject(text)
            obj.optString("summary")
                .ifBlank { obj.optString("message") }
                .ifBlank { obj.optString("error") }
                .ifBlank { obj.optString("title") }
        } catch (_: Exception) {
            ""
        }.ifBlank { text }

        return summary
            .replace(Regex("\\s+"), " ")
            .let { if (it.length > 120) it.take(117) + "..." else it }
    }

    /**
     * 构建 Agent 的动态上下文 —— 注入真实学情、薄弱点、待复习知识点、记忆数据。
     *
     * 这是「记忆」的第一层：会话内上下文。Agent 每次启动时都能看到用户的最新学习状态。
     */
    private suspend fun buildAgentContext(pageContext: Map<*, *>? = null): AgentPromptContext {
        val now = System.currentTimeMillis()
        val oneWeekAgo = now - 7 * 24 * 60 * 60 * 1000L

        // 学情摘要
        val totalCount = studyRecordDao.getTotalCountSince(startTime = 0)
        val correctCount = studyRecordDao.getCorrectCountSince(startTime = 0)
        val accuracy = if (totalCount > 0) correctCount.toFloat() / totalCount else 0f
        val totalTime = studyRecordDao.getTotalTimeSpent() ?: 0
        val streak = calculateStreak()
        val dailyCounts = studyRecordDao.getDailyCountSince(startTime = oneWeekAgo)
        val weeklyHeatmap = dailyCounts.associate { it.date to it.count }

        val learningContext = cn.com.memcoach.agent.LearningContext(
            totalQuestions = totalCount,
            correctRate = accuracy,
            studyStreakDays = streak,
            totalStudyHours = totalTime / 3600f,
            weeklyHeatmap = weeklyHeatmap,
            predictedScore = (130 + accuracy * 40 + if (totalCount > 0) 6 else 0).toInt(),
            targetScore = 170
        )

        // 薄弱知识点
        val weakMasteries = userMasteryDao.getWeakest(limit = 5)
        val weakPoints = weakMasteries.mapNotNull { m ->
            val node = knowledgeNodeDao.getById(m.knowledgeId) ?: return@mapNotNull null
            cn.com.memcoach.agent.WeakPoint(
                nodeId = m.knowledgeId,
                nodeName = node.name,
                masteryLevel = m.masteryLevel,
                questionCount = m.reviewCount
            )
        }

        // 今日待复习知识点
        val dueItems = userMasteryDao.getDueForReview(now = now, limit = 10)
        val memorizedItems = dueItems.mapNotNull { m ->
            val node = knowledgeNodeDao.getById(m.knowledgeId) ?: return@mapNotNull null
            cn.com.memcoach.agent.MemorizedItem(
                nodeId = m.knowledgeId,
                nodeName = node.name,
                form = node.content?.take(100) ?: node.description ?: "",
                dueToday = m.nextReviewDate <= now
            )
        }

        // ── 注入记忆数据 ──
        val memoryContext = buildMemoryContext()

        // ── 注入页面上下文 ──
        val pageContextPrompt = buildPageContextPrompt(pageContext)

        return cn.com.memcoach.agent.AgentPromptContext(
            learningContext = learningContext,
            weakPoints = weakPoints,
            memorizedItems = memorizedItems,
            conversationSummary = memoryContext,
            studyMode = "practice",
            currentTopic = pageContextPrompt
        )
    }

    private fun buildPageContextPrompt(context: Map<*, *>?): String? {
        if (context == null || context.isEmpty()) return null

        return when (context["type"]) {
            "question" -> """
                ## 当前页面上下文
                用户正在查看真题：${context["question_id"]}
                - 年份：${context["year"]}
                - 科目：${context["subject"]}
                - 题型/分区：${context["section"]}
                - 考点：${context["topic"]}
                - 难度：${context["difficulty"]}
                - 题干：${context["stem"]}
                - 选项：${context["options"]}
                - 答案：${context["answer"]}
                - 解析：${context["explanation"]}

                用户问你关于这道题的问题时，无需让用户重复输入题目ID，直接基于此题回答。
            """.trimIndent()

            "vocabulary" -> """
                ## 当前页面上下文
                用户正在查看单词：${context["word"]}
                - 音标：${context["phonetic"]}
                - 释义：${context["definitions"]}

                用户问你关于这个单词的问题时，无需让用户重复输入单词，直接基于此单词回答。
            """.trimIndent()

            else -> null
        }
    }

    /**
     * 构建记忆上下文 —— 从短期记忆和长期记忆中提取关键信息
     */
    private fun buildMemoryContext(): String? {
        val sb = StringBuilder()
        
        // 读取今日短期记忆
        val todayMemory = dailyMemoryService?.getToday()
        if (!todayMemory.isNullOrBlank()) {
            sb.appendLine("### 今日学习记忆")
            sb.appendLine(if (todayMemory.length > 500) todayMemory.take(500) else todayMemory) // 限制长度
            sb.appendLine()
        }
        
        // 读取长期记忆中的高重要性条目
        val importantMemories = longTermMemoryService?.searchByImportance(minImportance = 7, limit = 5)
        if (!importantMemories.isNullOrEmpty()) {
            sb.appendLine("### 重要长期记忆")
            importantMemories.forEach { entry ->
                sb.appendLine("- [${entry.category}] ${entry.text.take(100)}")
            }
            sb.appendLine()
        }
        
        return if (sb.isNotEmpty()) sb.toString().trim() else null
    }

    private suspend fun cancelAgentTurn(arguments: Map<String, Any?>): String {
        val requestedConversationId = (arguments["conversationId"] as? Number)?.toLong()
        val conversationId = currentAgentConversationId ?: requestedConversationId
        val runId = currentAgentRunId ?: conversationId?.let { id ->
            conversationDao.getById(id)?.agentRunId
        }
        if (conversationId != null && !runId.isNullOrBlank()) {
            markAgentRunFinished(
                conversationId = conversationId,
                runId = runId,
                status = ConversationEntity.AGENT_STATUS_CANCELLED,
                error = "用户取消"
            )
        }
        currentAgentJob?.cancel()
        currentAgentJob = null
        currentAgentConversationId = null
        currentAgentRunId = null
        return "cancelled"
    }

    private suspend fun isAgentRunning(arguments: Map<String, Any?>): Map<String, Any?> {
        val conversationId = (arguments["conversationId"] as? Number)?.toLong()
        val inMemoryRunning = currentAgentJob?.isActive == true &&
            (conversationId == null || currentAgentConversationId == conversationId)
        val conversation = conversationId?.let { id -> conversationDao.getById(id) }
        val storedStatus = conversation?.agentStatus
        val storedRunId = conversation?.agentRunId

        if (
            conversation != null &&
            storedStatus == ConversationEntity.AGENT_STATUS_RUNNING &&
            !inMemoryRunning &&
            !storedRunId.isNullOrBlank()
        ) {
            conversationDao.finishAgentRun(
                id = conversation.id,
                runId = storedRunId,
                status = ConversationEntity.AGENT_STATUS_INTERRUPTED,
                error = "Agent 任务已不在内存，可能是应用进程被系统回收或运行被中断。"
            )
        }

        return mapOf(
            "running" to inMemoryRunning,
            "conversation_id" to conversationId,
            "run_id" to storedRunId,
            "status" to if (
                storedStatus == ConversationEntity.AGENT_STATUS_RUNNING &&
                !inMemoryRunning
            ) {
                ConversationEntity.AGENT_STATUS_INTERRUPTED
            } else {
                storedStatus
            },
            "last_seq" to (conversation?.agentLastSeq ?: 0L),
            "started_at" to conversation?.agentStartedAt,
            "finished_at" to conversation?.agentFinishedAt,
            "error" to conversation?.agentError
        )
    }

    private suspend fun compactContext(arguments: Map<String, Any?>): Map<String, Any?> {
        val history = parseHistory(arguments["history"])
        val result = orchestrator.manualCompact(
            history = history,
            context = buildAgentContext()
        )
        return mapOf(
            "compacted" to result.compacted,
            "summary" to result.summary,
            "message_count_before" to result.messageCountBefore,
            "message_count_after" to result.messageCountAfter
        )
    }

    private fun setReasoningEffort(arguments: Map<String, Any?>): Map<String, Any?> {
        val rawLevel = arguments["level"]?.toString()?.lowercase()?.trim().orEmpty()
        val effort = when (rawLevel) {
            "low", "低" -> AgentReasoningEffort.LOW
            "high", "高" -> AgentReasoningEffort.HIGH
            else -> AgentReasoningEffort.MEDIUM
        }
        orchestrator.setReasoningEffort(effort)
        return mapOf(
            "level" to effort.name.lowercase(),
            "label" to when (effort) {
                AgentReasoningEffort.LOW -> "低"
                AgentReasoningEffort.MEDIUM -> "中"
                AgentReasoningEffort.HIGH -> "高"
            }
        )
    }

    private suspend fun uploadPdf(arguments: Map<String, Any?>): Map<String, Any?> {

        val path = arguments["file_path"] as? String ?: return mapOf("error" to "file_path is required")
        val subject = normalizeSubject(arguments["subject"] as? String)
        val year = when (val rawYear = arguments["year"]) {
            is Int -> rawYear
            is Long -> rawYear.toInt()
            is Double -> rawYear.toInt()
            is String -> rawYear.toIntOrNull()
            else -> null
        }
        val document = pdfRepository.importPdf(path, subject, year)
        val jobId = "pdf_job_${System.currentTimeMillis()}"

        scope.launch(kotlinx.coroutines.Dispatchers.IO) {
            pipelineService.processPdf(
                pdfFile = java.io.File(document.localPath),
                subject = subject,
                year = year ?: 0,
                jobId = jobId,
                sourceDocumentId = document.id
            )

        }

        return document.toMap().toMutableMap().apply {
            put("job_id", jobId)
            put("status", "pending")
        }
    }

    private suspend fun listPdfs(): List<Map<String, Any?>> {
        return pdfRepository.listDocuments().map { it.toMap() }
    }

    private fun getPdfParseStatus(arguments: Map<String, Any?>): Map<String, Any?> {
        val jobId = arguments["job_id"] as? String ?: return mapOf("error" to "job_id is required")
        val status = pipelineService.getJobStatus(jobId) ?: return mapOf(
            "job_id" to jobId,
            "status" to "not_found",
            "progress" to 0
        )
        return status.toJsonMap()
    }

    private fun org.json.JSONObject.toJsonMap(): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        val keys = this.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val value = this.get(key)
            map[key] = when (value) {
                is org.json.JSONObject -> value.toJsonMap()
                is org.json.JSONArray -> value.toJsonList()
                org.json.JSONObject.NULL -> null
                else -> value
            }
        }
        return map
    }

    private fun org.json.JSONArray.toJsonList(): List<Any?> {
        val list = mutableListOf<Any?>()
        for (i in 0 until this.length()) {
            val value = this.get(i)
            list.add(when (value) {
                is org.json.JSONObject -> value.toJsonMap()
                is org.json.JSONArray -> value.toJsonList()
                org.json.JSONObject.NULL -> null
                else -> value
            })
        }
        return list
    }

    private fun cn.com.memcoach.data.entity.ExamQuestion.toQuestionMap(): Map<String, Any?> {
        return mapOf(
            "id" to id,
            "year" to year,
            "subject" to subject,
            "section" to (section ?: ""),
            "question_number" to questionNumber,
            "type" to type,
            "topic" to (topic ?: ""),
            "difficulty" to (difficulty ?: ""),
            "stem" to stem,
            "options" to (options ?: "{}"),
            "answer" to (answer ?: ""),
            "explanation" to (explanation ?: ""),
            "source_file" to sourceFile,
            "source_document_id" to (sourceDocumentId ?: ""),
            "source_page" to sourcePage,
            "source_page_type" to (sourcePageType ?: ""),
            "source_text" to (sourceText ?: ""),
            "answer_source_page" to answerSourcePage,
            "answer_source_text" to (answerSourceText ?: ""),
            "merge_status" to mergeStatus,
            "parse_confidence" to parseConfidence,
            "parse_status" to parseStatus,
            "parse_notes" to (parseNotes ?: "")
        )
    }

    private suspend fun getRandomQuestions(arguments: Map<String, Any?>): List<Map<String, Any?>> {

        val scope = normalizeExamScope(
            subject = arguments["subject"] as? String,
            section = arguments["section"] as? String
        )
        val count = (arguments["count"] as? Int) ?: 5
        val topic = arguments["topic"] as? String

        val questions = examQuestionDao.search(
            subject = scope.subject,
            section = scope.section,
            topic = topic,
            limit = count * 2 // 获取更多以便随机抽取
        ).shuffled().take(count)

        return questions.map { it.toQuestionMap() }

    }

    private suspend fun submitAnswer(arguments: Map<String, Any?>): Map<String, Any?> {
        val questionId = arguments["question_id"] as? String ?: return mapOf("error" to "question_id required")
        val userAnswer = arguments["user_answer"] as? String ?: return mapOf("error" to "user_answer required")
        val timeSpentSec = (arguments["time_spent_seconds"] as? Number)?.toInt() ?: 0
        val result = try {
            answerSubmissionRecorder.submit(
                questionId = questionId,
                userAnswer = userAnswer,
                timeSpentSeconds = timeSpentSec
            )
        } catch (e: IllegalArgumentException) {
            return mapOf("error" to (e.message ?: "submit failed"))
        }

        return mapOf(
            "success" to true,
            "correct" to result.correct,
            "user_answer" to result.userAnswer,
            "correct_answer" to result.correctAnswer,
            "explanation" to result.explanation,
            "hint" to result.hint,
            "mastery_level" to result.masteryLevel,
            "knowledge_id" to result.knowledgeId
        )

    }

    private suspend fun getKnowledgeTree(arguments: Map<String, Any?>): List<Map<String, Any?>> {
        val subject = normalizeSubject(arguments["subject"] as? String)

        val rootNodes = knowledgeNodeDao.getRootNodes(subject)
        val result = mutableListOf<Map<String, Any?>>()

        for (root in rootNodes) {
            result.add(mapOf(
                "id" to root.id,
                "name" to root.name,
                "level" to 0,
                "subject" to root.subject,
                "chapter" to (root.chapter ?: ""),
                "exam_frequency" to root.examFrequency
            ))

            val children = knowledgeNodeDao.getChildren(root.id)
            for (child in children) {
                result.add(mapOf(
                    "id" to child.id,
                    "name" to child.name,
                    "level" to 1,
                    "subject" to child.subject,
                    "chapter" to (child.chapter ?: ""),
                    "exam_frequency" to child.examFrequency
                ))

                val grandchildren = knowledgeNodeDao.getChildren(child.id)
                for (gc in grandchildren) {
                    result.add(mapOf(
                        "id" to gc.id,
                        "name" to gc.name,
                        "level" to 2,
                        "subject" to gc.subject,
                        "chapter" to (gc.chapter ?: ""),
                        "exam_frequency" to gc.examFrequency
                    ))
                }
            }
        }

        return result
    }

    /**
     * 获取首页所需的所有数据：连续学习天数、今日正确率、待复习数、薄弱点摘要、AI 建议等。
     */
    private suspend fun getHomeData(): Map<String, Any?> {
        val now = System.currentTimeMillis()
        val todayStart = run {
            val cal = java.util.Calendar.getInstance()
            cal.set(java.util.Calendar.HOUR_OF_DAY, 0)
            cal.set(java.util.Calendar.MINUTE, 0)
            cal.set(java.util.Calendar.SECOND, 0)
            cal.set(java.util.Calendar.MILLISECOND, 0)
            cal.timeInMillis
        }

        // 连续学习天数
        val streak = calculateStreak()

        // 今日正确率
        val todayTotal = studyRecordDao.getTotalCountSince(startTime = todayStart)
        val todayCorrect = studyRecordDao.getCorrectCountSince(startTime = todayStart)
        val todayAccuracy = if (todayTotal > 0) todayCorrect.toDouble() / todayTotal else -1.0

        // 待复习数（SM-2 间隔重复到期）
        val dueReviewCount = userMasteryDao.countDueForReview(now = now)

        // 全局正确率
        val overallTotal = studyRecordDao.getTotalCountSince(startTime = 0)
        val overallCorrect = studyRecordDao.getCorrectCountSince(startTime = 0)
        val overallAccuracy = if (overallTotal > 0) overallCorrect.toDouble() / overallTotal else -1.0

        // 已掌握知识点数
        val masteredCount = userMasteryDao.countMastered(threshold = 0.8f)
        val totalKnowledgeCount = userMasteryDao.countTotal()

        // 薄弱知识点（取前 2 个）
        val weakPoints = userMasteryDao.getWeakest(limit = 2)

        // 考试倒计时（默认距离 11 月考试，可配置）
        val examDate = java.util.Calendar.getInstance().apply {
            set(java.util.Calendar.MONTH, java.util.Calendar.NOVEMBER)
            set(java.util.Calendar.DAY_OF_MONTH, 15)
            set(java.util.Calendar.HOUR_OF_DAY, 0)
            set(java.util.Calendar.MINUTE, 0)
            set(java.util.Calendar.SECOND, 0)
            set(java.util.Calendar.MILLISECOND, 0)
            if (timeInMillis < now) add(java.util.Calendar.YEAR, 1)
        }.timeInMillis
        val daysUntilExam = ((examDate - now) / (24 * 60 * 60 * 1000L)).toInt()

        // AI 建议文案
        val briefing = buildBriefing(weakPoints, todayAccuracy, todayTotal)

        return mapOf(
            "streak" to streak,
            "days_until_exam" to daysUntilExam,
            "today_total" to todayTotal,
            "today_correct" to todayCorrect,
            "today_accuracy" to todayAccuracy,
            "overall_accuracy" to overallAccuracy,
            "due_review_count" to dueReviewCount,
            "mastered_count" to masteredCount,
            "total_knowledge_count" to totalKnowledgeCount,
            "weak_points" to weakPoints.map { m ->
                mapOf(
                    "knowledge_id" to m.knowledgeId,
                    "mastery_level" to m.masteryLevel
                )
            },
            "briefing" to briefing
        )
    }

    /**
     * 计算连续学习天数：从今天往回数，遇到非连续日期即停止。
     */
    private suspend fun calculateStreak(): Int {
        val dates = studyRecordDao.getDistinctStudyDates()
        if (dates.isEmpty()) return 0

        val dateFormat = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
        val today = java.util.Calendar.getInstance().apply {
            set(java.util.Calendar.HOUR_OF_DAY, 0)
            set(java.util.Calendar.MINUTE, 0)
            set(java.util.Calendar.SECOND, 0)
            set(java.util.Calendar.MILLISECOND, 0)
        }
        val todayStr = dateFormat.format(today.time)

        // 如果今天还没学习，从昨天开始算
        var streak = 0
        val cal = today.clone() as java.util.Calendar
        if (!dates.contains(todayStr)) {
            cal.add(java.util.Calendar.DAY_OF_YEAR, -1)
        }

        while (true) {
            val dateStr = dateFormat.format(cal.time)
            if (dates.contains(dateStr)) {
                streak++
                cal.add(java.util.Calendar.DAY_OF_YEAR, -1)
            } else {
                break
            }
        }
        return streak
    }

    /**
     * 根据学习数据生成 AI 建议文案
     */
    private fun buildBriefing(
        weakPoints: List<cn.com.memcoach.data.entity.UserMastery>,
        todayAccuracy: Double,
        todayTotal: Int
    ): String {
        val sb = StringBuilder()

        if (todayTotal == 0) {
            sb.append("今天还没有开始学习。")
            if (weakPoints.isNotEmpty()) {
                sb.append("上次练习中「${weakPoints[0].knowledgeId}」掌握度较低（${(weakPoints[0].masteryLevel * 100).toInt()}%），建议优先攻克。")
            } else {
                sb.append("建议先做一组真题摸底，了解自己的薄弱环节。")
            }
        } else {
            val accPercent = (todayAccuracy * 100).toInt()
            sb.append("今天已做 $todayTotal 题，正确率 $accPercent%。")
            if (todayAccuracy < 0.6) {
                sb.append("正确率偏低，")
                if (weakPoints.isNotEmpty()) {
                    sb.append("「${weakPoints[0].knowledgeId}」是你的薄弱点，建议用 5 道专项题打穿。")
                } else {
                    sb.append("建议放慢节奏，仔细阅读每道题的解析。")
                }
            } else if (todayAccuracy < 0.8) {
                sb.append("还不错！")
                if (weakPoints.isNotEmpty()) {
                    sb.append("但「${weakPoints[0].knowledgeId}」仍有提升空间，可以再练几道。")
                } else {
                    sb.append("继续巩固，保持手感。")
                }
            } else {
                sb.append("表现优秀！")
                if (weakPoints.isNotEmpty()) {
                    sb.append("不过「${weakPoints[0].knowledgeId}」掌握度还不够高，建议做几道变式题巩固。")
                } else {
                    sb.append("保持节奏，可以挑战更高难度的题目。")
                }
            }
        }

        return sb.toString()
    }

    private fun parseHistory(raw: Any?): List<ConversationMessage> {
        val items = raw as? List<*> ?: return emptyList()
        return items.mapNotNull { item ->
            val map = item as? Map<*, *> ?: return@mapNotNull null
            val role = map["role"] as? String ?: return@mapNotNull null
            val content = map["content"] as? String ?: ""
            val reasoningContent = map["reasoning_content"] as? String
            val toolCallId = map["tool_call_id"] as? String
            val toolCallsRaw = map["tool_calls"] as? List<*>
            val toolCalls = toolCallsRaw?.mapNotNull { tc ->
                val tcMap = tc as? Map<*, *> ?: return@mapNotNull null
                val id = tcMap["id"] as? String ?: ""
                val name = tcMap["name"] as? String ?: ""
                val arguments = tcMap["arguments"] as? String ?: "{}"
                mapOf("id" to id, "name" to name, "arguments" to arguments)
            }?.takeIf { it.isNotEmpty() }
            ConversationMessage(
                role = role,
                content = content,
                reasoningContent = reasoningContent,
                toolCallId = toolCallId,
                toolCalls = toolCalls
            )
        }
    }
    
    // 会话管理方法
    
    /**
     * 创建新会话
     */
    private suspend fun createConversation(arguments: Map<String, Any?>): Map<String, Any?> {
        val title = arguments["title"] as? String ?: "新对话"
        
        val conversation = cn.com.memcoach.data.entity.ConversationEntity(
            userId = "default",
            title = title,
            createdAt = System.currentTimeMillis(),
            updatedAt = System.currentTimeMillis()
        )
        val id = conversationDao.insert(conversation)
        
        return mapOf(
            "id" to id,
            "title" to title,
            "created_at" to conversation.createdAt
        )
    }
    
    /**
     * 获取用户的所有会话
     */
    private suspend fun listConversations(): List<Map<String, Any?>> {
        val conversations = conversationDao.getAllByUser("default")
        return conversations.map { conv ->
            mapOf(
                "id" to conv.id,
                "title" to conv.title,
                "summary" to conv.summary,
                "message_count" to conv.messageCount,
                "agent_run_id" to conv.agentRunId,
                "agent_status" to conv.agentStatus,
                "agent_last_seq" to conv.agentLastSeq,
                "agent_started_at" to conv.agentStartedAt,
                "agent_finished_at" to conv.agentFinishedAt,
                "agent_error" to conv.agentError,
                "created_at" to conv.createdAt,
                "updated_at" to conv.updatedAt
            )
        }
    }
    
    /**
     * 获取会话的所有消息
     */
    private suspend fun getConversationMessages(arguments: Map<String, Any?>): List<Map<String, Any?>> {
        val conversationId = (arguments["conversationId"] as? Number)?.toLong() 
            ?: return emptyList()
        
        val messages = chatMessageDao.getByConversationId(conversationId).map { msg ->
            mapOf(
                "id" to msg.id,
                "role" to msg.role,
                "content" to msg.content,
                "tool_name" to msg.toolName,
                "tool_status" to msg.toolStatus,
                "tool_result" to msg.toolResult,
                "tool_call_id" to msg.toolCallId,
                "tool_calls" to parseToolCallsJson(msg.toolCallsJson),
                "run_id" to msg.runId,
                "entry_id" to msg.entryId,
                "message_status" to msg.messageStatus,
                "thinking_content" to msg.thinkingContent,

                "thinking_stage" to msg.thinkingStage,
                "created_at" to msg.createdAt
            )
        }
        val agentEvents = agentEventDao.getByConversationId(conversationId)
        val eventChips = agentEvents.mapNotNull { event -> event.toSkillChipMap() } +
            buildToolChipMaps(agentEvents)

        return (messages + eventChips).sortedBy { row ->
            (row["created_at"] as? Number)?.toLong() ?: 0L
        }
    }

    private data class ToolChipHistory(
        val key: String,
        val runId: String,
        var toolName: String,
        var toolCallId: String?,
        var arguments: String?,
        var result: String?,
        var error: String?,
        var status: String?,
        var startedAt: Long,
        var completedAt: Long?
    )

    private fun buildToolChipMaps(events: List<AgentEventEntity>): List<Map<String, Any?>> {
        val chips = linkedMapOf<String, ToolChipHistory>()
        events.forEach { event ->
            if (event.eventType !in setOf(
                    "tool_call_start",
                    "tool_call_retry",
                    "tool_call_complete",
                    "tool_call_error"
                )
            ) {
                return@forEach
            }

            val payload = try {
                JSONObject(event.payloadJson)
            } catch (e: Exception) {
                return@forEach
            }

            val toolName = payload.optString("toolName").takeIf { it.isNotBlank() }
                ?: return@forEach
            val toolCallId = payload.optString("toolCallId").takeIf { it.isNotBlank() }
            val key = firstNonBlank(
                event.entryId,
                payload.optString("entryId"),
                payload.optString("cardId"),
                toolCallId
            ) ?: "${toolName}:${event.id}"
            val chip = chips.getOrPut(key) {
                ToolChipHistory(
                    key = key,
                    runId = event.runId,
                    toolName = toolName,
                    toolCallId = toolCallId,
                    arguments = null,
                    result = null,
                    error = null,
                    status = null,
                    startedAt = event.createdAt,
                    completedAt = null
                )
            }

            chip.toolName = toolName
            if (chip.toolCallId.isNullOrBlank()) chip.toolCallId = toolCallId
            chip.startedAt = minOf(chip.startedAt, event.createdAt)
            chip.arguments = firstNonBlank(
                chip.arguments,
                payload.optString("argsJson"),
                payload.optString("args"),
                payload.optString("arguments")
            )

            when (event.eventType) {
                "tool_call_start" -> {
                    chip.status = "running"
                }

                "tool_call_retry" -> {
                    chip.status = "running"
                }

                "tool_call_complete" -> {
                    chip.status = "success"
                    chip.result = firstNonBlank(
                        payload.optString("rawResultJson"),
                        payload.optString("resultPreviewJson"),
                        payload.optString("result"),
                        payload.optString("summary"),
                        chip.result
                    )
                    chip.completedAt = event.createdAt
                }

                "tool_call_error" -> {
                    chip.status = "error"
                    chip.error = firstNonBlank(
                        payload.optString("error"),
                        payload.optString("summary"),
                        chip.error
                    )
                    chip.result = firstNonBlank(
                        payload.optString("rawResultJson"),
                        payload.optString("resultPreviewJson"),
                        payload.optString("result"),
                        chip.result
                    )
                    chip.completedAt = event.createdAt
                }
            }
        }

        return chips.values.map { chip ->
            val durationMs = chip.completedAt?.let { completed ->
                (completed - chip.startedAt).coerceAtLeast(0L)
            }
            mapOf(
                "id" to chip.key,
                "role" to "tool_chip",
                "content" to chip.toolName,
                "tool_name" to chip.toolName,
                "tool_status" to chip.status,
                "tool_call_id" to chip.toolCallId,
                "run_id" to chip.runId,
                "entry_id" to chip.key,
                "tool_arguments" to chip.arguments,
                "tool_result" to chip.result,
                "tool_error" to chip.error,
                "tool_duration_ms" to durationMs,
                "created_at" to chip.startedAt
            )
        }
    }

    private fun AgentEventEntity.toSkillChipMap(): Map<String, Any?>? {
        return try {
            val payload = JSONObject(payloadJson)
            val skillName = payload.optString("skillName").takeIf { it.isNotBlank() }
                ?: return null
            mapOf(
                "id" to id,
                "role" to "skill_chip",
                "content" to skillName,
                "skill_id" to payload.optString("skillId"),
                "skill_confidence" to payload.optDouble("confidence", 0.0),
                "skill_trigger_reason" to payload.optString("triggerReason"),
                "created_at" to createdAt
            )
        } catch (e: Exception) {
            null
        }
    }

    private fun firstNonBlank(vararg values: String?): String? {
        return values.firstOrNull { value ->
            !value.isNullOrBlank() && value != "null"
        }
    }

    private fun Any?.asLongOrNull(): Long? {
        return when (this) {
            is Long -> this
            is Int -> this.toLong()
            is Number -> this.toLong()
            is String -> this.toLongOrNull()
            else -> null
        }
    }

    private fun Any?.asIntOrNull(): Int? {
        return when (this) {
            is Int -> this
            is Number -> this.toInt()
            is String -> this.toIntOrNull()
            else -> null
        }
    }
    
    private fun parseToolCallsJson(raw: String?): List<Map<String, String>>? {
        if (raw.isNullOrBlank()) return null
        return try {
            val array = org.json.JSONArray(raw)
            List(array.length()) { index ->
                val item = array.getJSONObject(index)
                mapOf(
                    "id" to item.optString("id"),
                    "name" to item.optString("name"),
                    "arguments" to item.optString("arguments", "{}")
                )
            }.filter { it["id"].orEmpty().isNotBlank() && it["name"].orEmpty().isNotBlank() }
                .takeIf { it.isNotEmpty() }
        } catch (e: Exception) {
            null
        }
    }

    private fun normalizeSubject(raw: String?): String {
        return when (raw?.trim()?.lowercase()) {
            null, "", "unknown", "null", "management_comprehensive", "management", "comprehensive", "管综", "管理类综合", "管理类综合能力",
            "math", "logic", "writing", "数学", "逻辑", "写作" -> "management_comprehensive"
            "english", "english2", "english_ii", "英语", "英语二" -> "english"
            else -> raw.trim()
        }
    }

    private fun normalizeSection(raw: String?): String? {
        return when (raw?.trim()?.lowercase()) {
            null, "", "null", "all", "全部" -> null
            "math", "数学" -> "math"
            "logic", "逻辑" -> "logic"
            "writing", "写作" -> "writing"
            "english", "英语", "english2", "english_ii", "英语二" -> "english"
            "cloze" -> "cloze"
            "reading_a", "reading-a", "阅读理解a" -> "reading_a"
            "reading_b", "reading-b", "阅读理解b" -> "reading_b"
            "translation", "翻译" -> "translation"
            "writing_a", "writing-a", "小作文" -> "writing_a"
            "writing_b", "writing-b", "大作文" -> "writing_b"
            else -> raw.trim()
        }
    }

    private data class ToolCallSnapshot(
        val id: String,
        val name: String,
        val arguments: String
    )

    private data class ToolResultSnapshot(
        val id: String,
        val name: String,
        val result: String
    )

    private data class ExamScope(
        val subject: String?,
        val section: String?
    )

    private fun normalizeExamScope(subject: String?, section: String?): ExamScope {
        val rawSubject = subject?.trim()?.takeIf { it.isNotBlank() }
        val explicitSection = normalizeSection(section)
        val sectionFromSubject = normalizeSection(rawSubject)

        return when (rawSubject?.lowercase()) {
            null, "null", "all", "全部" -> ExamScope(null, explicitSection)
            "math", "数学", "logic", "逻辑", "writing", "写作" ->
                ExamScope("management_comprehensive", sectionFromSubject)
            "management_comprehensive", "management", "comprehensive", "管综", "管理类综合", "管理类综合能力" ->
                ExamScope("management_comprehensive", explicitSection)
            "english", "english2", "english_ii", "英语", "英语二" ->
                ExamScope("english", explicitSection)
            else -> ExamScope(rawSubject, explicitSection)
        }
    }

    private fun normalizeToolCallsJson(raw: Any?): String? {
        val items = raw as? List<*> ?: return null
        val array = org.json.JSONArray()
        items.forEach { item ->
            val map = item as? Map<*, *> ?: return@forEach
            val id = map["id"]?.toString().orEmpty()
            val name = map["name"]?.toString().orEmpty()
            if (id.isBlank() || name.isBlank()) return@forEach
            array.put(org.json.JSONObject().apply {
                put("id", id)
                put("name", name)
                put("arguments", map["arguments"]?.toString() ?: "{}")
            })
        }
        return if (array.length() > 0) array.toString() else null
    }

    /**
     * 添加聊天消息
     */
    private suspend fun addChatMessage(arguments: Map<String, Any?>): Map<String, Any?> {

        val conversationId = (arguments["conversationId"] as? Number)?.toLong() 
            ?: return mapOf("error" to "conversationId is required")
        val role = arguments["role"] as? String ?: return mapOf("error" to "role is required")
        val content = arguments["content"] as? String ?: return mapOf("error" to "content is required")
        val reasoningContent = arguments["reasoning_content"] as? String
        val toolName = arguments["toolName"] as? String
        val toolStatus = arguments["toolStatus"] as? String
        val toolResult = arguments["toolResult"] as? String
        val toolCallId = arguments["toolCallId"] as? String
        val toolCallsJson = normalizeToolCallsJson(arguments["toolCalls"])
        val runId = arguments["runId"] as? String
        val entryId = arguments["entryId"] as? String
        val messageStatus = arguments["messageStatus"] as? String
        
        val message = cn.com.memcoach.data.entity.ChatMessageEntity(

            conversationId = conversationId,
            role = role,
            content = content,
            thinkingContent = reasoningContent,
            toolName = toolName,
            toolStatus = toolStatus,
            toolResult = toolResult,
            toolCallId = toolCallId,
            toolCallsJson = toolCallsJson,
            runId = runId,
            entryId = entryId,
            messageStatus = messageStatus,
            createdAt = System.currentTimeMillis()

        )
        val id = chatMessageDao.insert(message)
        
        return mapOf(
            "id" to id,
            "conversation_id" to conversationId,
            "role" to role,
            "content" to content
        )
    }
    
    /**
     * 更新会话消息数量
     */
    private suspend fun updateConversationMessageCount(arguments: Map<String, Any?>): Map<String, Any?> {
        val conversationId = (arguments["conversationId"] as? Number)?.toLong()
            ?: return mapOf("error" to "conversationId is required")

        val count = chatMessageDao.getCountByConversationId(conversationId)
        conversationDao.updateMessageCount(conversationId, count)

        return mapOf(
            "conversation_id" to conversationId,
            "message_count" to count
        )
    }

    /**
     * 更新会话标题
     */
    private suspend fun updateConversationTitle(arguments: Map<String, Any?>): Map<String, Any?> {
        val conversationId = (arguments["conversationId"] as? Number)?.toLong()
            ?: return mapOf("error" to "conversationId is required")
        val title = arguments["title"] as? String
            ?: return mapOf("error" to "title is required")

        conversationDao.updateTitle(conversationId, title)

        return mapOf(
            "conversation_id" to conversationId,
            "title" to title
        )
    }

    /**
     * 删除会话
     */
    private suspend fun deleteConversation(arguments: Map<String, Any?>): Map<String, Any?> {
        val conversationId = (arguments["conversationId"] as? Number)?.toLong() 
            ?: return mapOf("error" to "conversationId is required")
        
        chatMessageDao.deleteByConversationId(conversationId)
        conversationDao.delete(conversationId)
        
        return mapOf(
            "conversation_id" to conversationId,
            "deleted" to true
        )
    }
}

interface NativeEventSink {
    fun success(event: Map<String, Any?>)
    fun error(code: String, message: String?, details: Any? = null)
    fun endOfStream()
}
