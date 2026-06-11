package cn.com.memcoach.agent.tool.handlers

import cn.com.memcoach.agent.tool.ToolDefinition
import cn.com.memcoach.agent.tool.ToolHandler
import cn.com.memcoach.data.dao.VocabularyDao
import cn.com.memcoach.data.dao.VocabularyReviewDao
import cn.com.memcoach.data.entity.VocabularyReview
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import cn.com.memcoach.data.entity.Vocabulary
import java.util.UUID
import cn.com.memcoach.MemCoachApplication
import cn.com.memcoach.agent.ChatMessage
import org.json.JSONObject
import org.json.JSONArray

class VocabularyToolHandler(
    private val vocabularyDao: VocabularyDao,
    private val reviewDao: VocabularyReviewDao
) : ToolHandler {

    override val toolNames = setOf(
        "vocabulary_list",
        "vocabulary_detail",
        "vocabulary_review",
        "vocabulary_search",
        "vocabulary_add",
        "vocabulary_stats"
    )

    override suspend fun execute(toolName: String, arguments: String): String {
        val args = try { Json.parseToJsonElement(arguments).jsonObject } catch (_: Exception) { JsonObject(emptyMap()) }
        return when (toolName) {
            "vocabulary_list" -> getVocabularyList(args)
            "vocabulary_detail" -> getVocabularyDetail(args)
            "vocabulary_review" -> submitReview(args)
            "vocabulary_search" -> searchVocabulary(args)
            "vocabulary_add" -> addVocabulary(args)
            "vocabulary_stats" -> getVocabularyStats()
            else -> """{"error":"unknown tool"}"""
        }
    }

    override fun getDefinitions() = listOf(
        ToolDefinition(
            name = "vocabulary_list",
            description = "获取单词列表",
            parameters = """{"type":"object","properties":{"status":{"type":"string"},"limit":{"type":"integer"}}}"""
        ),
        ToolDefinition(
            name = "vocabulary_detail",
            description = "获取单词详情",
            parameters = """{"type":"object","properties":{"word_id":{"type":"string"}},"required":["word_id"]}"""
        ),
        ToolDefinition(
            name = "vocabulary_review",
            description = "提交单词复习记录",
            parameters = """{"type":"object","properties":{"word_id":{"type":"string"},"is_correct":{"type":"boolean"}},"required":["word_id","is_correct"]}"""
        ),
        ToolDefinition(
            name = "vocabulary_search",
            description = "搜索单词",
            parameters = """{"type":"object","properties":{"query":{"type":"string"}},"required":["query"]}"""
        ),
        ToolDefinition(
            name = "vocabulary_add",
            description = "添加新单词到本地词库",
            parameters = """{"type":"object","properties":{"word":{"type":"string"},"phonetic":{"type":"string"},"definitions":{"type":"string"},"explanation":{"type":"string"},"tags":{"type":"string"}},"required":["word"]}"""
        ),
        ToolDefinition(
            name = "vocabulary_stats",
            description = "获取单词统计数据（包括各状态单词数及待复习数）",
            parameters = """{"type":"object","properties":{}}"""
        )
    )

    private suspend fun getVocabularyList(args: JsonObject) = withContext(Dispatchers.IO) {
        val status = args["status"]?.jsonPrimitive?.contentOrNull ?: "new"
        val limit = args["limit"]?.jsonPrimitive?.intOrNull ?: 20

        val words = when (status) {
            "review" -> vocabularyDao.getDueForReview(System.currentTimeMillis(), limit)
            "all", "" -> vocabularyDao.search("", limit)
            else -> vocabularyDao.getByStatus(status, limit)
        }

        buildJsonObject {
            put("count", words.size)
            put("words", buildJsonArray {
                words.forEach { w ->
                    add(buildJsonObject {
                        put("id", w.id)
                        put("word", w.word)
                        putNullable("phonetic", w.phonetic)
                        put("definitions", w.definitions)
                        putNullable("tags", w.tags)
                        put("status", w.status)
                    })
                }
            })
        }.toString()
    }

    private suspend fun getVocabularyDetail(args: JsonObject) = withContext(Dispatchers.IO) {
        val wordId = args["word_id"]?.jsonPrimitive?.content ?: return@withContext """{"error":"word_id required"}"""
        val word = vocabularyDao.getById(wordId) ?: return@withContext """{"error":"word not found"}"""

        buildJsonObject {
            put("id", word.id)
            put("word", word.word)
            putNullable("phonetic", word.phonetic)
            put("definitions", word.definitions)
            putNullable("synonyms", word.synonyms)
            putNullable("confusables", word.confusables)
            putNullable("tags", word.tags)
            put("explanation", word.explanation)
            put("status", word.status)
            put("review_count", word.reviewCount)
        }.toString()
    }

    private suspend fun submitReview(args: JsonObject) = withContext(Dispatchers.IO) {
        val wordId = args["word_id"]?.jsonPrimitive?.content ?: return@withContext """{"error":"word_id required"}"""
        val isCorrect = args["is_correct"]?.jsonPrimitive?.boolean ?: return@withContext """{"error":"is_correct required"}"""

        val word = vocabularyDao.getById(wordId) ?: return@withContext """{"error":"word not found"}"""

        // 记录复习
        reviewDao.insert(
            VocabularyReview(
                vocabId = wordId,
                isCorrect = isCorrect,
                reviewType = "recognition"
            )
        )

        // 更新单词状态（简化的间隔重复算法）
        val newReviewCount = word.reviewCount + 1
        val newStatus = when {
            newReviewCount >= 5 && isCorrect -> "mastered"
            newReviewCount >= 2 -> "learning"
            else -> word.status
        }

        val updated = word.copy(
            reviewCount = newReviewCount,
            status = newStatus,
            lastReviewAt = System.currentTimeMillis(),
            nextReviewAt = if (isCorrect) System.currentTimeMillis() + 86400000 * (newReviewCount + 1) else System.currentTimeMillis() + 3600000,
            updatedAt = System.currentTimeMillis()
        )

        vocabularyDao.update(updated)

        """{"success":true,"status":"$newStatus"}"""
    }

    private suspend fun searchVocabulary(args: JsonObject) = withContext(Dispatchers.IO) {
        val query = args["query"]?.jsonPrimitive?.content ?: return@withContext """{"error":"query required"}"""
        val limit = args["limit"]?.jsonPrimitive?.intOrNull ?: 50

        val words = vocabularyDao.search(query, limit)

        buildJsonObject {
            put("count", words.size)
            put("words", buildJsonArray {
                words.forEach { w ->
                    add(buildJsonObject {
                        put("id", w.id)
                        put("word", w.word)
                        putNullable("phonetic", w.phonetic)
                        put("definitions", w.definitions)
                        put("status", w.status)
                        putNullable("tags", w.tags)
                    })
                }
            })
        }.toString()
    }

    private suspend fun addVocabulary(args: JsonObject) = withContext(Dispatchers.IO) {
        val wordText = args["word"]?.jsonPrimitive?.contentOrNull?.trim()
            ?: return@withContext """{"error":"word is required"}"""

        if (wordText.isEmpty()) {
            return@withContext """{"error":"word is empty"}"""
        }

        // 检查单词是否已存在
        val existing = vocabularyDao.getByWord(wordText)
        if (existing != null) {
            return@withContext buildJsonObject {
                put("success", true)
                put("already_exists", true)
                put("id", existing.id)
                put("word", existing.word)
            }.toString()
        }

        // 调用 AI 导师进行单词深度解析
        var phonetic: String? = null
        var definitionsRaw = "[]"
        var explanation = "### $wordText\n暂无详细释义。"
        var tags = "[]"

        try {
            val prompt = """
                请为考研管理类联考（MEM/MBA）备考场景解析以下英文单词或短语：
                "$wordText"
                
                请严格以下列 JSON 格式返回结果（不要包含任何 Markdown 标识符或额外文字）：
                {
                  "word": "$wordText",
                  "phonetic": "音标，例如 /'bentʃmɑːk/",
                  "definitions": [
                    {"pos": "词性，如 n. 或 v.", "translation": "核心中文释义"}
                  ],
                  "explanation": "详细备考解析，使用 Markdown 格式。包含：1. 核心备考词义与联考真题常见用法；2. 精选 1-2 个双语例句及中文翻译；3. 记忆技巧（如词根词缀或词源/谐音联想）。",
                  "tags": ["MEM", "词汇分级，如核心词/高频词/基础词"]
                }
            """.trimIndent()

            val systemPrompt = "你是一个专业的 MEM/MBA 考研英语辅导名师，擅长词汇深度解析与记忆法教学。请严格输出符合格式的合法 JSON，不要用 ```json 包裹。"

            val messages = listOf(
                ChatMessage(role = "system", content = systemPrompt),
                ChatMessage(role = "user", content = prompt)
            )

            val client = MemCoachApplication.instance.llmClient
            val response = client.completeTurn(messages = messages, tools = null, modelId = null)
            var jsonStr = response.content.trim()

            if (jsonStr.startsWith("```json")) {
                jsonStr = jsonStr.removePrefix("```json").trim()
                if (jsonStr.endsWith("```")) {
                    jsonStr = jsonStr.removeSuffix("```").trim()
                }
            } else if (jsonStr.startsWith("```")) {
                jsonStr = jsonStr.removePrefix("```").trim()
                if (jsonStr.endsWith("```")) {
                    jsonStr = jsonStr.removeSuffix("```").trim()
                }
            }

            val jsonObject = JSONObject(jsonStr)
            phonetic = jsonObject.optString("phonetic", null)
            definitionsRaw = jsonObject.optJSONArray("definitions")?.toString() ?: "[]"
            explanation = jsonObject.optString("explanation", "### $wordText\n解析生成失败。")
            tags = jsonObject.optJSONArray("tags")?.toString() ?: "[]"
        } catch (e: Exception) {
            android.util.Log.e("VocabularyToolHandler", "AI 解析单词出错", e)
        }

        // 构造新单词实体
        val vocabId = "vocab-${UUID.randomUUID()}"
        val vocab = Vocabulary(
            id = vocabId,
            word = wordText,
            phonetic = phonetic,
            definitions = definitionsRaw,
            tags = tags,
            explanation = explanation
        )

        try {
            vocabularyDao.insert(vocab)
            buildJsonObject {
                put("success", true)
                put("id", vocabId)
                put("word", wordText)
            }.toString()
        } catch (e: Exception) {
            """{"error":"${e.message ?: "failed to insert"}"}"""
        }
    }

    private suspend fun getVocabularyStats() = withContext(Dispatchers.IO) {
        val review = vocabularyDao.getDueForReview(System.currentTimeMillis(), 9999).size
        val learning = vocabularyDao.countByStatus("learning")
        val mastered = vocabularyDao.countByStatus("mastered")
        val newWords = vocabularyDao.countByStatus("new")
        val total = review + learning + mastered + newWords

        // 返回各状态单词数
        buildJsonObject {
            put("success", true)
            put("total", total)
            put("review", review)
            put("learning", learning)
            put("mastered", mastered)
            put("new_words", newWords)
        }.toString()
    }

    private fun JsonObjectBuilder.putNullable(key: String, value: String?) {
        if (value != null) put(key, value) else put(key, JsonNull)
    }
}
