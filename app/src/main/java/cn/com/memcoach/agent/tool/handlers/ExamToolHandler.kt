package cn.com.memcoach.agent.tool.handlers

import cn.com.memcoach.agent.tool.ToolDefinition
import cn.com.memcoach.agent.tool.ToolHandler
import cn.com.memcoach.data.dao.ExamQuestionDao
import cn.com.memcoach.data.dao.StudyRecordDao
import cn.com.memcoach.data.dao.UserMasteryDao
import cn.com.memcoach.data.entity.StudyRecord
import cn.com.memcoach.data.entity.UserMastery
import kotlinx.serialization.json.*

/**
 * 真题工具处理器 —— 提供真题搜索、答案检查、相似题查找、掌握度更新、模拟卷生成等工具。
 *
 * 覆盖工具：
 * - exam_question_search    —— 按年份/科目/知识点/题型搜索真题
 * - exam_question_explain   —— 获取题目详解（题干、答案、解析、来源）
 * - exam_answer_check       —— 比对用户答案与正确答案
 * - exam_similar_find       —— 查找与指定题目知识点相似的真题
 * - exam_mastery_update     —— 更新用户对该知识点的掌握度
 * - exam_mock_generate      —— 从题库中按约束抽取组成模拟卷
 */
class ExamToolHandler(
    private val questionDao: ExamQuestionDao,
    private val studyRecordDao: StudyRecordDao,
    private val masteryDao: UserMasteryDao
) : ToolHandler {

    override val toolNames = setOf(
        "exam_question_search",
        "exam_question_explain",
        "exam_answer_check",
        "exam_similar_find",
        "exam_mastery_update",
        "exam_mock_generate"
    )

    override suspend fun execute(toolName: String, arguments: String): String {
        val args = try { Json.parseToJsonElement(arguments).jsonObject } catch (_: Exception) { JsonObject(emptyMap()) }
        return when (toolName) {
            "exam_question_search" -> searchQuestions(args)
            "exam_question_explain" -> explainQuestion(args)
            "exam_answer_check" -> checkAnswer(args)
            "exam_similar_find" -> findSimilar(args)
            "exam_mastery_update" -> updateMastery(args)
            "exam_mock_generate" -> generateMock(args)
            else -> """{"error":"unknown tool: $toolName"}"""
        }
    }

    override fun getDefinitions(): List<ToolDefinition> = listOf(
        ToolDefinition(
            name = "exam_question_search",
            description = "搜索真题库，支持按年份、科目、知识点、题型过滤。返回符合条件的题目列表（不含答案和解析）。",
            parameters = """
{
  "type": "object",
  "properties": {
    "subject": {
      "type": "string",
      "description": "科目：logic/writing/math/english",
      "enum": ["logic", "writing", "math", "english"]
    },
    "topic": {
      "type": "string",
      "description": "知识点ID，如 conditional_inference"
    },
    "year": {
      "type": "integer",
      "description": "年份，如 2023"
    },
    "type": {
      "type": "string",
      "description": "题型：choice/fill/essay"
    },
    "limit": {
      "type": "integer",
      "description": "返回数量上限"
    }
  },
  "required": ["subject"]
}
""".trimIndent()
        ),
        ToolDefinition(
            name = "exam_question_explain",
            description = "获取指定题目的完整信息：题干、选项、正确答案、解析、来源（年份/真题编号）。用于讲解时引用。",
            parameters = """
{
  "type": "object",
  "properties": {
    "question_id": {
      "type": "string",
      "description": "题目ID，如 logic_2023_1"
    },
    "depth": {
      "type": "string",
      "description": "解析深度：brief/standard/detailed"
    }
  },
  "required": ["question_id"]
}
""".trimIndent()
        ),
        ToolDefinition(
            name = "exam_answer_check",
            description = "比对用户答案与正确答案，返回是否正确及解析。用于做题后即时反馈。",
            parameters = """
{
  "type": "object",
  "properties": {
    "question_id": {
      "type": "string",
      "description": "题目ID"
    },
    "user_answer": {
      "type": "string",
      "description": "用户提交的答案"
    }
  },
  "required": ["question_id", "user_answer"]
}
""".trimIndent()
        ),
        ToolDefinition(
            name = "exam_similar_find",
            description = "查找与指定题目知识点相似的真题，用于变式练习和延伸学习。基于 topic 字段精确匹配后随机抽取。",
            parameters = """
{
  "type": "object",
  "properties": {
    "question_id": {
      "type": "string",
      "description": "参考题目ID"
    },
    "limit": {
      "type": "integer",
      "description": "返回数量"
    }
  },
  "required": ["question_id"]
}
""".trimIndent()
        ),
        ToolDefinition(
            name = "exam_mastery_update",
            description = "更新用户对某道题关联知识点的掌握度。Agent 在用户完成练习后调用此工具记录学习效果。",
            parameters = """
{
  "type": "object",
  "properties": {
    "question_id": {
      "type": "string",
      "description": "题目ID"
    },
    "correct": {
      "type": "boolean",
      "description": "是否正确"
    },
    "time_spent_sec": {
      "type": "integer",
      "description": "用时（秒）"
    }
  },
  "required": ["question_id", "correct"]
}
""".trimIndent()
        ),
        ToolDefinition(
            name = "exam_mock_generate",
            description = "从题库中按约束抽取题目组成模拟卷。用于用户要求'来一套模拟题'或'随机组卷'时。",
            parameters = """
{
  "type": "object",
  "properties": {
    "subject": {
      "type": "string",
      "description": "科目",
      "enum": ["logic", "writing"]
    },
    "question_count": {
      "type": "integer",
      "description": "题目数量"
    },
    "strategy": {
      "type": "string",
      "description": "抽取策略：random（随机）/ weak_focus（重点薄弱点）/ balanced（均匀分布）"
    }
  },
  "required": ["subject"]
}
""".trimIndent()
        )
    )

    // ─── 工具实现 ───

    private suspend fun searchQuestions(args: JsonObject): String {
        val subject = args["subject"]?.jsonPrimitive?.content ?: return errorJson("subject 必填")
        val topic = args["topic"]?.jsonPrimitive?.contentOrNull
        val year = args["year"]?.jsonPrimitive?.intOrNull
        val type = args["type"]?.jsonPrimitive?.contentOrNull
        val limit = args["limit"]?.jsonPrimitive?.intOrNull ?: 5

        val results = questionDao.search(
            subject = subject,
            topic = topic,
            type = type,
            year = year,
            limit = limit
        )

        return buildJsonObject {
            put("count", results.size)
            put("questions", buildJsonArray {
                results.forEach { q ->
                    add(buildJsonObject {
                        put("id", q.id)
                        put("year", q.year)
                        put("subject", q.subject)
                        put("type", q.type)
                        putNullable("topic", q.topic)
                        putNullable("difficulty", q.difficulty)
                        put("stem", q.stem)
                        put("source_file", q.sourceFile)
                        put("source_page", q.sourcePage)
                    })
                }
            })
        }.toString()
    }

    private suspend fun explainQuestion(args: JsonObject): String {
        val questionId = args["question_id"]?.jsonPrimitive?.content ?: return errorJson("question_id 必填")
        val question = questionDao.getById(questionId) ?: return errorJson("题目不存在: $questionId")

        return buildJsonObject {
            put("id", question.id)
            put("year", question.year)
            put("subject", question.subject)
            put("type", question.type)
            putNullable("topic", question.topic)
            putNullable("difficulty", question.difficulty)
            put("stem", question.stem)
            putNullable("options", question.options)
            putNullable("answer", question.answer)
            put("explanation", question.explanation ?: "暂无解析")
            put("source", buildJsonObject {
                put("file", question.sourceFile)
                put("page", question.sourcePage)
            })
        }.toString()
    }

    private suspend fun checkAnswer(args: JsonObject): String {
        val questionId = args["question_id"]?.jsonPrimitive?.content ?: return errorJson("question_id 必填")
        val userAnswer = args["user_answer"]?.jsonPrimitive?.content ?: return errorJson("user_answer 必填")
        val question = questionDao.getById(questionId) ?: return errorJson("题目不存在: $questionId")

        val correctAnswer = question.answer ?: ""
        val isCorrect = userAnswer.trim().equals(correctAnswer.trim(), ignoreCase = true)

        return buildJsonObject {
            put("correct", isCorrect)
            put("user_answer", userAnswer)
            put("correct_answer", correctAnswer)
            if (!isCorrect) {
                put("explanation", question.explanation ?: "")
                put("hint", "请仔细阅读解析，理解错误原因后再尝试变式练习")
            } else {
                put("message", "回答正确！继续保持")
            }
        }.toString()
    }

    private suspend fun findSimilar(args: JsonObject): String {
        val questionId = args["question_id"]?.jsonPrimitive?.content ?: return errorJson("question_id 必填")
        val limit = args["limit"]?.jsonPrimitive?.intOrNull ?: 3
        val question = questionDao.getById(questionId) ?: return errorJson("题目不存在: $questionId")

        // 按 topic 找同知识点题目，排除自身
        val similar = questionDao.searchByTopic(question.subject, question.topic, limit + 1)
            .filter { it.id != questionId }
            .take(limit)

        return buildJsonObject {
            put("reference_question_id", questionId)
            putNullable("reference_topic", question.topic)
            put("count", similar.size)
            put("similar_questions", buildJsonArray {
                similar.forEach { q ->
                    add(buildJsonObject {
                        put("id", q.id)
                        put("year", q.year)
                        put("stem", q.stem)
                        putNullable("difficulty", q.difficulty)
                    })
                }
            })
        }.toString()
    }

    private suspend fun updateMastery(args: JsonObject): String {
        val questionId = args["question_id"]?.jsonPrimitive?.content ?: return errorJson("question_id 必填")
        val correct = args["correct"]?.jsonPrimitive?.booleanOrNull ?: return errorJson("correct 必填")
        val timeSpentSec = args["time_spent_sec"]?.jsonPrimitive?.intOrNull ?: 0

        val question = questionDao.getById(questionId) ?: return errorJson("题目不存在: $questionId")
        val knowledgeId = question.topic ?: return errorJson("题目未关联知识点，无法更新掌握度: $questionId")
        val now = System.currentTimeMillis()

        // 1. 记录学习记录
        studyRecordDao.insert(
            StudyRecord(
                questionId = questionId,
                userAnswer = if (correct) question.answer else "",
                isCorrect = correct,
                timeSpentSeconds = timeSpentSec,
                studyMode = StudyRecord.MODE_PRACTICE,
                knowledgeId = knowledgeId,
                createdAt = now
            )
        )

        // 2. 更新掌握度
        val existing = masteryDao.getByUserAndKnowledge(userId = "default", knowledgeId = knowledgeId)
        val updated = if (existing != null) {
            val newLevel = if (correct) {
                minOf(1f, existing.masteryLevel + 0.1f)
            } else {
                maxOf(0f, existing.masteryLevel - 0.05f)
            }
            // 使用简化的间隔重复：正确则下次复习延后，错误则提前
            val nextReview = if (correct) {
                now + (existing.reviewCount + 1) * 24 * 60 * 60 * 1000L
            } else {
                now + 12 * 60 * 60 * 1000L // 12小时后复习
            }
            existing.copy(
                masteryLevel = newLevel,
                reviewCount = existing.reviewCount + 1,
                correctCount = if (correct) existing.correctCount + 1 else existing.correctCount,
                lastReviewDate = now,
                nextReviewDate = nextReview,
                updatedAt = now
            )
        } else {
            UserMastery(
                userId = "default",
                knowledgeId = knowledgeId,
                masteryLevel = if (correct) 0.5f else 0.2f,
                reviewCount = 1,
                correctCount = if (correct) 1 else 0,
                lastReviewDate = now,
                nextReviewDate = if (correct) now + 24 * 60 * 60 * 1000L else now + 12 * 60 * 60 * 1000L,
                updatedAt = now
            )
        }
        masteryDao.upsert(updated)

        return buildJsonObject {
            put("updated", true)
            put("knowledge_id", knowledgeId)
            put("mastery_level", "${"%.0f".format(updated.masteryLevel * 100)}%")
            put("correct", correct)
        }.toString()
    }

    private suspend fun generateMock(args: JsonObject): String {
        val subject = args["subject"]?.jsonPrimitive?.content ?: return errorJson("subject 必填")
        val questionCount = args["question_count"]?.jsonPrimitive?.intOrNull ?: 10

        // 简单策略：随机抽取指定科目所有题目中指定数量
        val allQuestions = questionDao.search(
            subject = subject,
            limit = maxOf(questionCount * 3, questionCount)
        )
        val mockQuestions = allQuestions.shuffled().take(questionCount)

        return buildJsonObject {
            put("mock_title", "MEM ${subject.uppercase()} 模拟卷")
            put("question_count", mockQuestions.size)
            put("questions", buildJsonArray {
                mockQuestions.forEach { q ->
                    add(buildJsonObject {
                        put("id", q.id)
                        put("year", q.year)
                        put("stem", q.stem)
                        put("type", q.type)
                        putNullable("topic", q.topic)
                    })
                }
            })
        }.toString()
    }

    private fun buildJsonSchema(block: JsonObjectBuilder.() -> Unit): JsonObject {
        return JsonObject(emptyMap()).let {
            val builder = object : JsonObjectBuilder {
                private val map = mutableMapOf<String, JsonElement>()
                override fun put(key: String, element: JsonElement) { map[key] = element }
                override fun build(): JsonObject = JsonObject(map)
            }
            builder.block()
            builder.build()
        }
    }

    // 简化：直接构建JsonObject
    private fun buildJsonObject(block: JsonObjectBuilder.() -> Unit): JsonObject {
        val builder = JsonObjectBuilderImpl()
        builder.block()
        return builder.build()
    }

    private fun buildJsonArray(block: JsonArrayBuilder.() -> Unit): JsonArray {
        val builder = JsonArrayBuilderImpl()
        builder.block()
        return builder.build()
    }

    private fun errorJson(msg: String) = """{"error":"$msg"}"""

    // 辅助构建器接口
    interface JsonObjectBuilder {
        fun put(key: String, element: JsonElement)
        fun put(key: String, value: String) = put(key, JsonPrimitive(value))
        fun put(key: String, value: Int) = put(key, JsonPrimitive(value))
        fun put(key: String, value: Boolean) = put(key, JsonPrimitive(value))
        fun putNullable(key: String, value: String?) = put(key, value?.let { JsonPrimitive(it) } ?: JsonNull)
        fun build(): JsonObject
    }

    interface JsonArrayBuilder {
        fun add(element: JsonElement)
        fun add(value: String) = add(JsonPrimitive(value))
        fun build(): JsonArray
    }

    inner class JsonObjectBuilderImpl : JsonObjectBuilder {
        private val map = mutableMapOf<String, JsonElement>()
        override fun build(): JsonObject = JsonObject(map)
        override fun put(key: String, element: JsonElement) { map[key] = element }
    }

    inner class JsonArrayBuilderImpl : JsonArrayBuilder {
        private val list = mutableListOf<JsonElement>()
        override fun build(): JsonArray = JsonArray(list)
        override fun add(element: JsonElement) { list.add(element) }
    }
}
