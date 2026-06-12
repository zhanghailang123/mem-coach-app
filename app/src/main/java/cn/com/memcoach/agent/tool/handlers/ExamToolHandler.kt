package cn.com.memcoach.agent.tool.handlers

import cn.com.memcoach.agent.tool.ToolDefinition
import cn.com.memcoach.agent.tool.ToolHandler
import cn.com.memcoach.data.dao.ExamQuestionDao
import cn.com.memcoach.study.AnswerSubmissionRecorder
import kotlinx.serialization.json.*
import java.io.File
import cn.com.memcoach.MemCoachApplication
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

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
 * - exam_favorite_add       —— 添加收藏
 * - exam_favorite_remove    —— 移除收藏
 * - exam_favorite_check     —— 检查收藏状态
 * - exam_favorite_list      —— 列出收藏题目
 */
class ExamToolHandler(
    private val questionDao: ExamQuestionDao,
    private val answerSubmissionRecorder: AnswerSubmissionRecorder
) : ToolHandler {

    override val toolNames = setOf(
        "exam_question_search",
        "exam_question_explain",
        "exam_answer_check",
        "exam_similar_find",
        "exam_mastery_update",
        "exam_mock_generate",
        "exam_favorite_add",
        "exam_favorite_remove",
        "exam_favorite_check",
        "exam_favorite_list"
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
            "exam_favorite_add" -> addFavorite(args)
            "exam_favorite_remove" -> removeFavorite(args)
            "exam_favorite_check" -> checkFavorite(args)
            "exam_favorite_list" -> listFavorites(args)
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
      "description": "大科目：management_comprehensive（管综）/english（英语）",
      "enum": ["management_comprehensive", "english"]
    },
    "section": {
      "type": "string",
      "description": "小模块：math/logic/writing/english",
      "enum": ["math", "logic", "writing", "english"]
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
    "user_answer": {
      "type": "string",
      "description": "用户答案，可选；用于同步写入错题本"
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
      "description": "大科目：management_comprehensive（管综）/english（英语）",
      "enum": ["management_comprehensive", "english"]
    },
    "section": {
      "type": "string",
      "description": "小模块：math/logic/writing/english",
      "enum": ["math", "logic", "writing", "english"]
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
        ),
        ToolDefinition(
            name = "exam_favorite_add",
            description = "将指定题目添加到收藏夹",
            parameters = """{"type":"object","properties":{"question_id":{"type":"string"}},"required":["question_id"]}"""
        ),
        ToolDefinition(
            name = "exam_favorite_remove",
            description = "从收藏夹中移除指定题目",
            parameters = """{"type":"object","properties":{"question_id":{"type":"string"}},"required":["question_id"]}"""
        ),
        ToolDefinition(
            name = "exam_favorite_check",
            description = "检查指定题目是否已被收藏",
            parameters = """{"type":"object","properties":{"question_id":{"type":"string"}},"required":["question_id"]}"""
        ),
        ToolDefinition(
            name = "exam_favorite_list",
            description = "获取用户收藏的所有题目列表",
            parameters = """{"type":"object","properties":{"limit":{"type":"integer"}}}"""
        )
    )

    // ─── 工具实现 ───

    private suspend fun searchQuestions(args: JsonObject): String {
        val scope = normalizeExamScope(
            subject = args["subject"]?.jsonPrimitive?.contentOrNull,
            section = args["section"]?.jsonPrimitive?.contentOrNull
        )
        val topic = args["topic"]?.jsonPrimitive?.contentOrNull
        val year = args["year"]?.jsonPrimitive?.intOrNull
        val type = args["type"]?.jsonPrimitive?.contentOrNull
        val limit = args["limit"]?.jsonPrimitive?.intOrNull ?: 100

        android.util.Log.d(
            "ExamToolHandler",
            "搜索参数: subject=${scope.subject}, section=${scope.section}, year=$year, limit=$limit"
        )

        val results = questionDao.search(
            subject = scope.subject,
            section = scope.section,
            topic = topic,
            type = type,
            year = year,
            parseStatus = null,
            minConfidence = 0.0f,
            limit = limit
        )

        android.util.Log.d("ExamToolHandler", "查询结果数量: ${results.size}")

        return buildJsonObject {
            put("count", results.size)
            put("questions", buildJsonArray {
                results.forEach { q ->
                    add(buildJsonObject {
                        put("id", q.id)
                        put("year", q.year ?: 0)
                        put("subject", q.subject)
                        putNullable("section", q.section)
                        putNullable("question_number", q.questionNumber)
                        put("type", q.type)
                        putNullable("topic", q.topic)
                        putNullable("difficulty", q.difficulty)
                        put("stem", q.stem)
                        put("source_file", q.sourceFile)
                        put("source_page", q.sourcePage)
                        put("parse_confidence", q.parseConfidence.toDouble())
                        put("parse_status", q.parseStatus)
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
            putNullable("section", question.section)
            putNullable("question_number", question.questionNumber)
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
                putNullable("page_type", question.sourcePageType)
                putNullable("text", question.sourceText)
                putNullable("answer_text", question.answerSourceText)
                putNullable("answer_page", question.answerSourcePage)
            })
            put("merge_status", question.mergeStatus)
            put("parse_confidence", question.parseConfidence.toDouble())
            put("parse_status", question.parseStatus)
            putNullable("parse_notes", question.parseNotes)
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
        val similar = questionDao.searchByTopic(
            subject = question.subject,
            topic = question.topic,
            section = question.section,
            limit = limit + 1
        ).filter { it.id != questionId }
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
        val userAnswer = args["user_answer"]?.jsonPrimitive?.contentOrNull
        val timeSpentSec = args["time_spent_sec"]?.jsonPrimitive?.intOrNull ?: 0

        val question = questionDao.getById(questionId) ?: return errorJson("题目不存在: $questionId")
        val result = try {
            answerSubmissionRecorder.submit(
                questionId = questionId,
                userAnswer = userAnswer ?: if (correct) question.answer.orEmpty() else "",
                correctAnswerOverride = question.answer,
                isCorrectOverride = correct,
                timeSpentSeconds = timeSpentSec
            )
        } catch (e: IllegalArgumentException) {
            return errorJson(e.message ?: "更新掌握度失败")
        }

        return buildJsonObject {
            put("updated", true)
            putNullable("knowledge_id", result.knowledgeId)
            putNullable("mastery_level", result.masteryLevel)
            put("correct", correct)
        }.toString()
    }

    private suspend fun generateMock(args: JsonObject): String {
        val scope = normalizeExamScope(
            subject = args["subject"]?.jsonPrimitive?.content ?: return errorJson("subject 必填"),
            section = args["section"]?.jsonPrimitive?.contentOrNull
        )
        val questionCount = args["question_count"]?.jsonPrimitive?.intOrNull ?: 10

        // 简单策略：随机抽取指定科目/模块所有题目中指定数量
        val allQuestions = questionDao.search(
            subject = scope.subject,
            section = scope.section,
            limit = maxOf(questionCount * 3, questionCount)
        )
        val mockQuestions = allQuestions.shuffled().take(questionCount)

        return buildJsonObject {
            put("mock_title", "MEM ${scope.subject.orEmpty().uppercase()} 模拟卷")
            put("question_count", mockQuestions.size)
            put("questions", buildJsonArray {
                mockQuestions.forEach { q ->
                    add(buildJsonObject {
                        put("id", q.id)
                        put("year", q.year)
                        putNullable("section", q.section)
                        putNullable("question_number", q.questionNumber)
                        put("stem", q.stem)
                        put("type", q.type)
                        putNullable("topic", q.topic)
                        put("source_file", q.sourceFile)
                        put("source_page", q.sourcePage)
                        put("parse_confidence", q.parseConfidence.toDouble())
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

    // 辅助构建器接口
    interface JsonObjectBuilder {
        fun put(key: String, element: JsonElement)
        fun put(key: String, value: String) = put(key, JsonPrimitive(value))
        fun put(key: String, value: Int) = put(key, JsonPrimitive(value))
        fun put(key: String, value: Float) = put(key, JsonPrimitive(value))
        fun put(key: String, value: Double) = put(key, JsonPrimitive(value))
        fun put(key: String, value: Boolean) = put(key, JsonPrimitive(value))
        fun putNullable(key: String, value: String?) = put(key, value?.let { JsonPrimitive(it) } ?: JsonNull)
        fun putNullable(key: String, value: Int?) = put(key, value?.let { JsonPrimitive(it) } ?: JsonNull)
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

    // ─── 收藏功能辅助实现 ───
    private val favoritesFile by lazy {
        File(MemCoachApplication.instance.filesDir, "exam_favorites.json")
    }

    private val favoritesLock = Any()

    private fun loadFavorites(): MutableSet<String> {
        synchronized(favoritesLock) {
            if (!favoritesFile.exists()) return mutableSetOf()
            return try {
                val text = favoritesFile.readText()
                val array = Json.parseToJsonElement(text).jsonArray
                array.map { it.jsonPrimitive.content }.toMutableSet()
            } catch (e: Exception) {
                mutableSetOf()
            }
        }
    }

    private fun saveFavorites(favorites: Set<String>) {
        synchronized(favoritesLock) {
            try {
                val array = buildJsonArray {
                    favorites.forEach { add(it) }
                }
                favoritesFile.writeText(array.toString())
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun addFavorite(args: JsonObject): String {
        val questionId = args["question_id"]?.jsonPrimitive?.contentOrNull ?: return errorJson("question_id 必填")
        val favorites = loadFavorites()
        favorites.add(questionId)
        saveFavorites(favorites)
        return """{"success":true}"""
    }

    private fun removeFavorite(args: JsonObject): String {
        val questionId = args["question_id"]?.jsonPrimitive?.contentOrNull ?: return errorJson("question_id 必填")
        val favorites = loadFavorites()
        favorites.remove(questionId)
        saveFavorites(favorites)
        return """{"success":true}"""
    }

    private fun checkFavorite(args: JsonObject): String {
        val questionId = args["question_id"]?.jsonPrimitive?.contentOrNull ?: return errorJson("question_id 必填")
        val favorites = loadFavorites()
        val isFavorited = favorites.contains(questionId)
        return """{"favorited":$isFavorited}"""
    }

    private suspend fun listFavorites(args: JsonObject) = withContext(Dispatchers.IO) {
        val limit = args["limit"]?.jsonPrimitive?.intOrNull ?: 50
        val favorites = loadFavorites()
        if (favorites.isEmpty()) {
            return@withContext """{"count":0,"questions":[]}"""
        }

        val ids = favorites.take(limit).toList()
        val results = questionDao.getByIds(ids)

        buildJsonObject {
            put("count", results.size)
            put("questions", buildJsonArray {
                results.forEach { q ->
                    add(buildJsonObject {
                        put("id", q.id)
                        put("year", q.year)
                        put("subject", q.subject)
                        putNullable("section", q.section)
                        putNullable("question_number", q.questionNumber)
                        put("type", q.type)
                        putNullable("topic", q.topic)
                        putNullable("difficulty", q.difficulty)
                        put("stem", q.stem)
                        put("source_file", q.sourceFile)
                        put("source_page", q.sourcePage)
                        put("parse_confidence", q.parseConfidence.toDouble())
                        put("parse_status", q.parseStatus)
                    })
                }
            })
        }.toString()
    }
}
