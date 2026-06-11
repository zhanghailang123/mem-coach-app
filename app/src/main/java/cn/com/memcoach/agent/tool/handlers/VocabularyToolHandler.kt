package cn.com.memcoach.agent.tool.handlers

import cn.com.memcoach.agent.tool.ToolDefinition
import cn.com.memcoach.agent.tool.ToolHandler
import cn.com.memcoach.data.dao.VocabularyDao
import cn.com.memcoach.data.dao.VocabularyReviewDao
import cn.com.memcoach.data.entity.VocabularyReview
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*

class VocabularyToolHandler(
    private val vocabularyDao: VocabularyDao,
    private val reviewDao: VocabularyReviewDao
) : ToolHandler {

    override val toolNames = setOf(
        "vocabulary_list",
        "vocabulary_detail",
        "vocabulary_review",
        "vocabulary_search"
    )

    override suspend fun execute(toolName: String, arguments: String): String {
        val args = try { Json.parseToJsonElement(arguments).jsonObject } catch (_: Exception) { JsonObject(emptyMap()) }
        return when (toolName) {
            "vocabulary_list" -> getVocabularyList(args)
            "vocabulary_detail" -> getVocabularyDetail(args)
            "vocabulary_review" -> submitReview(args)
            "vocabulary_search" -> searchVocabulary(args)
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
        )
    )

    private suspend fun getVocabularyList(args: JsonObject) = withContext(Dispatchers.IO) {
        val status = args["status"]?.jsonPrimitive?.contentOrNull ?: "new"
        val limit = args["limit"]?.jsonPrimitive?.intOrNull ?: 20

        val words = when (status) {
            "review" -> vocabularyDao.getDueForReview(System.currentTimeMillis(), limit)
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
                    })
                }
            })
        }.toString()
    }

    private fun JsonObjectBuilder.putNullable(key: String, value: String?) {
        if (value != null) put(key, value) else put(key, JsonNull)
    }
}
