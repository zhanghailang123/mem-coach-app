package cn.com.memcoach.agent.tool.handlers

import cn.com.memcoach.agent.tool.ToolDefinition
import cn.com.memcoach.agent.tool.ToolHandler
import cn.com.memcoach.data.dao.AnswerRecordDao
import cn.com.memcoach.data.dao.ExamQuestionDao
import cn.com.memcoach.data.entity.AnswerRecord
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import java.util.Calendar

/**
 * 错题本工具处理器
 */
class WrongBookToolHandler(
    private val answerRecordDao: AnswerRecordDao,
    private val questionDao: ExamQuestionDao
) : ToolHandler {

    override val toolNames = setOf(
        "wrong_book_list",
        "answer_submit",
        "study_stats"
    )

    override suspend fun execute(toolName: String, arguments: String): String {
        val args = try { Json.parseToJsonElement(arguments).jsonObject } catch (_: Exception) { JsonObject(emptyMap()) }
        return when (toolName) {
            "wrong_book_list" -> getWrongBook(args)
            "answer_submit" -> submitAnswer(args)
            "study_stats" -> getStudyStats(args)
            else -> """{"error":"unknown tool"}"""
        }
    }

    override fun getDefinitions() = listOf(
        ToolDefinition(
            name = "wrong_book_list",
            description = "获取错题本列表，包含题目信息和错题统计",
            parameters = """{"type":"object","properties":{"limit":{"type":"integer"}}}"""
        ),
        ToolDefinition(
            name = "answer_submit",
            description = "提交答题记录",
            parameters = """
            {
              "type":"object",
              "properties":{
                "question_id":{"type":"string"},
                "user_answer":{"type":"string"},
                "correct_answer":{"type":"string"},
                "is_correct":{"type":"boolean"},
                "time_spent":{"type":"integer"}
              },
              "required":["question_id","user_answer","correct_answer","is_correct"]
            }
            """.trimIndent()
        ),
        ToolDefinition(
            name = "study_stats",
            description = "获取学习统计（今日做题数、正确率）",
            parameters = """{"type":"object","properties":{}}"""
        )
    )

    private suspend fun getWrongBook(args: JsonObject) = withContext(Dispatchers.IO) {
        val limit = args["limit"]?.jsonPrimitive?.intOrNull ?: 20
        val wrongQuestions = answerRecordDao.getWrongBook().take(limit)
        val questionIds = wrongQuestions.map { it.questionId }
        val questions = questionDao.getByIds(questionIds).associateBy { it.id }

        buildJsonObject {
            put("count", wrongQuestions.size)
            put("items", buildJsonArray {
                wrongQuestions.forEach { wq ->
                    val q = questions[wq.questionId]
                    add(buildJsonObject {
                        put("question_id", wq.questionId)
                        put("stem", q?.stem ?: "")
                        put("answer", q?.answer ?: "")
                        put("total_attempts", wq.totalAttempts)
                        put("wrong_count", wq.wrongCount)
                        put("last_attempt_at", wq.lastAttemptAt)
                    })
                }
            })
        }.toString()
    }

    private suspend fun submitAnswer(args: JsonObject) = withContext(Dispatchers.IO) {
        val questionId = args["question_id"]?.jsonPrimitive?.content ?: return@withContext """{"error":"question_id required"}"""
        val userAnswer = args["user_answer"]?.jsonPrimitive?.content ?: return@withContext """{"error":"user_answer required"}"""
        val correctAnswer = args["correct_answer"]?.jsonPrimitive?.content ?: return@withContext """{"error":"correct_answer required"}"""
        val isCorrect = args["is_correct"]?.jsonPrimitive?.boolean ?: return@withContext """{"error":"is_correct required"}"""
        val timeSpent = args["time_spent"]?.jsonPrimitive?.intOrNull ?: 0

        answerRecordDao.insert(
            AnswerRecord(
                questionId = questionId,
                userAnswer = userAnswer,
                correctAnswer = correctAnswer,
                isCorrect = isCorrect,
                timeSpent = timeSpent
            )
        )

        """{"success":true,"message":"答题记录已保存"}"""
    }

    private suspend fun getStudyStats(args: JsonObject) = withContext(Dispatchers.IO) {
        val todayStart = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis

        val todayCount = answerRecordDao.getTodayCount(todayStart)
        val todayAccuracy = answerRecordDao.getTodayAccuracy(todayStart) ?: 0f

        buildJsonObject {
            put("today_count", todayCount)
            put("today_accuracy", todayAccuracy.toDouble())
        }.toString()
    }
}
