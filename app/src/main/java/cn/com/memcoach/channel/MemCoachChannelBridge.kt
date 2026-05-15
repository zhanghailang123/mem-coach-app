package cn.com.memcoach.channel

import cn.com.memcoach.agent.AgentInput
import cn.com.memcoach.agent.AgentOrchestrator
import cn.com.memcoach.agent.AgentPromptContext
import cn.com.memcoach.agent.AgentReasoningEffort
import cn.com.memcoach.agent.ConversationMessage

import cn.com.memcoach.pdf.PdfDocumentRepository
import cn.com.memcoach.pdf.toMap
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
    private val eventSink: NativeEventSink,
    private val studyRecordDao: cn.com.memcoach.data.dao.StudyRecordDao,
    private val userMasteryDao: cn.com.memcoach.data.dao.UserMasteryDao,
    private val pdfRepository: PdfDocumentRepository,
    private val examQuestionDao: cn.com.memcoach.data.dao.ExamQuestionDao,
    private val knowledgeNodeDao: cn.com.memcoach.data.dao.KnowledgeNodeDao,
    private val conversationDao: cn.com.memcoach.data.dao.ConversationDao,
    private val chatMessageDao: cn.com.memcoach.data.dao.ChatMessageDao,
    private val pipelineService: cn.com.memcoach.pipeline.PdfPipelineService,
    private val dailyMemoryService: cn.com.memcoach.agent.memory.DailyMemoryService? = null,
    private val longTermMemoryService: cn.com.memcoach.agent.memory.LongTermMemoryService? = null
) {
    private var currentAgentJob: Job? = null

    suspend fun handleMethodCall(method: String, arguments: Map<String, Any?>): Any? {
        return when (method) {
            "agent.startTurn" -> startAgentTurn(arguments)
            "agent.cancelTurn" -> cancelAgentTurn()
            "agent.compactContext" -> compactContext(arguments)
            "agent.setReasoningEffort" -> setReasoningEffort(arguments)
            "pdf.upload" -> uploadPdf(arguments)
            "pdf.parseStatus" -> getPdfParseStatus(arguments)

            "pdf.list" -> listPdfs()

            "insight.getSummary" -> getInsightSummary()
            "exam.getRandomQuestions" -> getRandomQuestions(arguments)
            "exam.submitAnswer" -> submitAnswer(arguments)
            "knowledge.getTree" -> getKnowledgeTree(arguments)
            "home.getData" -> getHomeData()
            "conversation.create" -> createConversation(arguments)
            "conversation.list" -> listConversations()
            "conversation.getMessages" -> getConversationMessages(arguments)
            "conversation.addMessage" -> addChatMessage(arguments)
            "conversation.updateMessageCount" -> updateConversationMessageCount(arguments)
            "conversation.delete" -> deleteConversation(arguments)
            "pdf.delete" -> deletePdf(arguments)
            else -> error("Unsupported native method: $method")
        }
    }

    private suspend fun deletePdf(arguments: Map<String, Any?>): Map<String, Any?> {
        val id = arguments["id"] as? String ?: return mapOf("error" to "id is required")
        pdfRepository.deleteDocument(id)
        return mapOf("id" to id, "deleted" to true)
    }

    private suspend fun getInsightSummary(): Map<String, Any?> {
        val now = System.currentTimeMillis()
        val oneWeekAgo = now - 7 * 24 * 60 * 60 * 1000L
        
        val totalTime = studyRecordDao.getTotalTimeSpent() ?: 0
        val totalCount = studyRecordDao.getTotalCountSince(startTime = 0)
        val correctCount = studyRecordDao.getCorrectCountSince(startTime = 0)
        val accuracy = if (totalCount > 0) correctCount.toDouble() / totalCount else 0.0
        
        val dailyCounts = studyRecordDao.getDailyCountSince(startTime = oneWeekAgo)
        val weakPoints = userMasteryDao.getWeakest(limit = 3)
        
        return mapOf(
            "total_study_time_seconds" to totalTime,
            "total_questions" to totalCount,
            "overall_accuracy" to accuracy,
            "daily_stats" to dailyCounts.map { it: cn.com.memcoach.data.dao.DailyStudyCount -> mapOf<String, Any>("date" to it.date, "count" to it.count) },
            "weak_points" to weakPoints.map { it: cn.com.memcoach.data.entity.UserMastery -> mapOf<String, Any>("name" to it.knowledgeId, "mastery" to it.masteryLevel) }
        )

    }



    private suspend fun startAgentTurn(arguments: Map<String, Any?>): String {
        val message = arguments["message"] as? String ?: return ""
        val history = parseHistory(arguments["history"])
        val context = buildAgentContext()

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

    /**
     * 构建 Agent 的动态上下文 —— 注入真实学情、薄弱点、待复习知识点、记忆数据。
     *
     * 这是「记忆」的第一层：会话内上下文。Agent 每次启动时都能看到用户的最新学习状态。
     */
    private suspend fun buildAgentContext(): AgentPromptContext {
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

        return cn.com.memcoach.agent.AgentPromptContext(
            learningContext = learningContext,
            weakPoints = weakPoints,
            memorizedItems = memorizedItems,
            conversationSummary = memoryContext,
            studyMode = "practice",
            currentTopic = null
        )
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

    private fun cancelAgentTurn(): String {
        currentAgentJob?.cancel()
        currentAgentJob = null
        return "cancelled"
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
        val subject = arguments["subject"] as? String
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
            pipelineService.processPdf(java.io.File(document.localPath), subject ?: "unknown", year ?: 0, jobId)
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

    private suspend fun getRandomQuestions(arguments: Map<String, Any?>): List<Map<String, Any?>> {

        val subject = arguments["subject"] as? String ?: "logic"
        val count = (arguments["count"] as? Int) ?: 5
        val topic = arguments["topic"] as? String

        val questions = examQuestionDao.search(
            subject = subject,
            topic = topic,
            limit = count * 2 // 获取更多以便随机抽取
        ).shuffled().take(count)

        return questions.map { q ->
            mapOf(
                "id" to q.id,
                "year" to q.year,
                "subject" to q.subject,
                "type" to q.type,
                "topic" to (q.topic ?: ""),
                "difficulty" to (q.difficulty ?: ""),
                "stem" to q.stem,
                "options" to (q.options ?: "{}"),
                "answer" to (q.answer ?: ""),
                "explanation" to (q.explanation ?: ""),
                "source_file" to q.sourceFile,
                "source_page" to q.sourcePage
            )
        }
    }

    private suspend fun submitAnswer(arguments: Map<String, Any?>): Map<String, Any?> {
        val questionId = arguments["question_id"] as? String ?: return mapOf("error" to "question_id required")
        val userAnswer = arguments["user_answer"] as? String ?: return mapOf("error" to "user_answer required")
        val timeSpentSec = (arguments["time_spent_seconds"] as? Int) ?: 0

        val question = examQuestionDao.getById(questionId) ?: return mapOf("error" to "question not found: $questionId")
        val correctAnswer = question.answer ?: ""
        val isCorrect = userAnswer.trim().equals(correctAnswer.trim(), ignoreCase = true)

        // 记录学习记录
        val knowledgeId = question.topic ?: "unknown"
        studyRecordDao.insert(
            cn.com.memcoach.data.entity.StudyRecord(
                questionId = questionId,
                userAnswer = userAnswer,
                isCorrect = isCorrect,
                timeSpentSeconds = timeSpentSec,
                studyMode = cn.com.memcoach.data.entity.StudyRecord.MODE_PRACTICE,
                knowledgeId = knowledgeId,
                createdAt = System.currentTimeMillis()
            )
        )

        // 更新掌握度
        val now = System.currentTimeMillis()
        val existing = userMasteryDao.getByUserAndKnowledge(userId = "default", knowledgeId = knowledgeId)
        val updated = if (existing != null) {
            val newLevel = if (isCorrect) {
                minOf(1f, existing.masteryLevel + 0.1f)
            } else {
                maxOf(0f, existing.masteryLevel - 0.05f)
            }
            val nextReview = if (isCorrect) {
                now + (existing.reviewCount + 1) * 24 * 60 * 60 * 1000L
            } else {
                now + 12 * 60 * 60 * 1000L
            }
            existing.copy(
                masteryLevel = newLevel,
                reviewCount = existing.reviewCount + 1,
                correctCount = if (isCorrect) existing.correctCount + 1 else existing.correctCount,
                lastReviewDate = now,
                nextReviewDate = nextReview,
                updatedAt = now
            )
        } else {
            cn.com.memcoach.data.entity.UserMastery(
                userId = "default",
                knowledgeId = knowledgeId,
                masteryLevel = if (isCorrect) 0.5f else 0.2f,
                reviewCount = 1,
                correctCount = if (isCorrect) 1 else 0,
                lastReviewDate = now,
                nextReviewDate = if (isCorrect) now + 24 * 60 * 60 * 1000L else now + 12 * 60 * 60 * 1000L,
                updatedAt = now
            )
        }
        userMasteryDao.upsert(updated)

        return mapOf(
            "correct" to isCorrect,
            "user_answer" to userAnswer,
            "correct_answer" to correctAnswer,
            "explanation" to (question.explanation ?: ""),
            "hint" to if (!isCorrect) "请仔细阅读解析，理解错误原因后再尝试变式练习" else "回答正确！继续保持",
            "mastery_level" to "%.0f%%".format(updated.masteryLevel * 100)
        )
    }

    private suspend fun getKnowledgeTree(arguments: Map<String, Any?>): List<Map<String, Any?>> {
        val subject = arguments["subject"] as? String ?: "logic"

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
        
        val messages = chatMessageDao.getByConversationId(conversationId)
        return messages.map { msg ->
            mapOf(
                "id" to msg.id,
                "role" to msg.role,
                "content" to msg.content,
                "tool_name" to msg.toolName,
                "tool_status" to msg.toolStatus,
                "tool_result" to msg.toolResult,
                "tool_call_id" to msg.toolCallId,
                "tool_calls" to parseToolCallsJson(msg.toolCallsJson),
                "thinking_content" to msg.thinkingContent,

                "thinking_stage" to msg.thinkingStage,
                "created_at" to msg.createdAt
            )
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
        val toolName = arguments["toolName"] as? String
        val toolStatus = arguments["toolStatus"] as? String
        val toolResult = arguments["toolResult"] as? String
        val toolCallId = arguments["toolCallId"] as? String
        val toolCallsJson = normalizeToolCallsJson(arguments["toolCalls"])
        
        val message = cn.com.memcoach.data.entity.ChatMessageEntity(

            conversationId = conversationId,
            role = role,
            content = content,
            toolName = toolName,
            toolStatus = toolStatus,
            toolResult = toolResult,
            toolCallId = toolCallId,
            toolCallsJson = toolCallsJson,
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
