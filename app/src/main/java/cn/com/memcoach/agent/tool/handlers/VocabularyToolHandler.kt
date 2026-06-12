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
import java.util.Locale

class VocabularyToolHandler(
    private val vocabularyDao: VocabularyDao,
    private val reviewDao: VocabularyReviewDao
) : ToolHandler {

    private data class ParsedVocabulary(
        val phonetic: String?,
        val definitions: JSONArray,
        val explanation: String,
        val tags: JSONArray,
        val synonyms: JSONArray?,
        val confusables: JSONArray?
    )

    override val toolNames = setOf(
        "vocabulary_list",
        "vocabulary_detail",
        "vocabulary_review",
        "vocabulary_search",
        "vocabulary_add",
        "vocabulary_delete",
        "vocabulary_regenerate",
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
            "vocabulary_delete" -> deleteVocabulary(args)
            "vocabulary_regenerate" -> regenerateVocabulary(args)
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
            name = "vocabulary_delete",
            description = "从本地词库删除单词",
            parameters = """{"type":"object","properties":{"word_id":{"type":"string"}},"required":["word_id"]}"""
        ),
        ToolDefinition(
            name = "vocabulary_regenerate",
            description = "使用 code-199 风格提示词重新生成单词深度解析",
            parameters = """{"type":"object","properties":{"word_id":{"type":"string"}},"required":["word_id"]}"""
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
        val rawWordText = args["word"]?.jsonPrimitive?.contentOrNull
            ?: return@withContext """{"error":"word is required"}"""
        val wordText = normalizeWordText(rawWordText)

        if (wordText.isEmpty()) {
            return@withContext """{"error":"word is empty"}"""
        }

        // 检查单词是否已存在
        val existing = vocabularyDao.getByWordIgnoreCase(wordText)
        if (existing != null) {
            return@withContext buildJsonObject {
                put("success", true)
                put("already_exists", true)
                put("id", existing.id)
                put("word", existing.word)
            }.toString()
        }

        // 调用 AI 导师进行单词深度解析
        val parsed = try {
            parseVocabularyWithAi(wordText)
        } catch (e: Exception) {
            android.util.Log.e("VocabularyToolHandler", "AI 解析单词出错", e)
            return@withContext buildJsonObject {
                put("success", false)
                put("error", "AI 解析失败：${e.message ?: e::class.java.simpleName}")
            }.toString()
        }

        // 构造新单词实体
        val vocabId = resolveVocabularyId(wordText)
        val now = System.currentTimeMillis()
        val vocab = Vocabulary(
            id = vocabId,
            word = wordText,
            phonetic = parsed.phonetic,
            definitions = parsed.definitions.toString(),
            synonyms = parsed.synonyms?.toString(),
            confusables = parsed.confusables?.toString(),
            tags = parsed.tags.toString(),
            explanation = parsed.explanation,
            nextReviewAt = now,
            createdAt = now,
            updatedAt = now
        )

        try {
            vocabularyDao.insert(vocab)
            buildJsonObject {
                put("success", true)
                put("id", vocabId)
                put("word", wordText)
                put("ai_parsed", true)
            }.toString()
        } catch (e: Exception) {
            """{"error":"${e.message ?: "failed to insert"}"}"""
        }
    }

    private suspend fun deleteVocabulary(args: JsonObject) = withContext(Dispatchers.IO) {
        val wordId = args["word_id"]?.jsonPrimitive?.contentOrNull
            ?: return@withContext """{"error":"word_id required"}"""
        val word = vocabularyDao.getById(wordId)
            ?: return@withContext """{"error":"word not found"}"""

        val deleted = vocabularyDao.deleteById(wordId)
        if (deleted <= 0) {
            return@withContext """{"error":"word not found"}"""
        }

        buildJsonObject {
            put("success", true)
            put("id", word.id)
            put("word", word.word)
        }.toString()
    }

    private suspend fun regenerateVocabulary(args: JsonObject) = withContext(Dispatchers.IO) {
        val wordId = args["word_id"]?.jsonPrimitive?.contentOrNull
            ?: return@withContext """{"error":"word_id required"}"""
        val word = vocabularyDao.getById(wordId)
            ?: return@withContext """{"error":"word not found"}"""

        val parsed = try {
            parseVocabularyWithAi(word.word)
        } catch (e: Exception) {
            android.util.Log.e("VocabularyToolHandler", "AI 重新生成单词解析出错", e)
            return@withContext buildJsonObject {
                put("success", false)
                put("error", "AI 重新生成失败：${e.message ?: e::class.java.simpleName}")
            }.toString()
        }

        val updated = word.copy(
            phonetic = parsed.phonetic,
            definitions = parsed.definitions.toString(),
            synonyms = parsed.synonyms?.toString(),
            confusables = parsed.confusables?.toString(),
            tags = parsed.tags.toString(),
            explanation = parsed.explanation,
            updatedAt = System.currentTimeMillis()
        )

        try {
            vocabularyDao.update(updated)
            buildJsonObject {
                put("success", true)
                put("id", word.id)
                put("word", word.word)
                put("ai_parsed", true)
            }.toString()
        } catch (e: Exception) {
            """{"error":"${e.message ?: "failed to update"}"}"""
        }
    }

    private suspend fun getVocabularyStats() = withContext(Dispatchers.IO) {
        val review = vocabularyDao.getDueForReview(System.currentTimeMillis(), 9999).size
        val learning = vocabularyDao.countByStatus("learning")
        val mastered = vocabularyDao.countByStatus("mastered")
        val newWords = vocabularyDao.countByStatus("new")
        val total = vocabularyDao.countAll()

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

    private suspend fun parseVocabularyWithAi(wordText: String): ParsedVocabulary {
        val prompt = buildVocabularyArticlePrompt(wordText)
        val systemPrompt = """
            你是 code-199 风格的考研英语词汇辅导名师，讲课风趣、直接、重实战。
            你的输出会被移动端直接解析入库，所以必须只输出一个合法 JSON 对象。
            不要输出 Markdown 代码块、YAML Frontmatter、解释文字或额外说明。
        """.trimIndent()

        val messages = listOf(
            ChatMessage(role = "system", content = systemPrompt),
            ChatMessage(role = "user", content = prompt)
        )

        val client = MemCoachApplication.instance.llmClient
        val response = client.completeTurn(messages = messages, tools = null, modelId = null)
        if (response.finishReason == "error") {
            error(response.content.ifBlank { "LLM 返回错误" })
        }

        val jsonObject = JSONObject(extractJsonObject(response.content))
        val definitions = normalizeDefinitions(jsonObject.optJSONArray("definitions"))
        require(definitions.length() > 0) { "LLM 返回的 definitions 为空" }

        val explanation = jsonObject.optStringOrNull("explanation")
        require(!explanation.isNullOrBlank()) { "LLM 返回的 explanation 为空" }
        require(explanation.length >= 120) { "LLM 返回的 explanation 过短" }
        val requiredMarkers = listOf("核心记忆锚点", "考研核心考法", "考研写作替换")
        require(requiredMarkers.all { explanation.contains(it) }) {
            "LLM 返回的 explanation 缺少 code-199 标准章节"
        }

        return ParsedVocabulary(
            phonetic = jsonObject.optStringOrNull("phonetic"),
            definitions = definitions,
            explanation = explanation,
            tags = normalizeTags(jsonObject.optJSONArray("tags")),
            synonyms = normalizeWordMeaningArray(jsonObject.optJSONArray("synonyms")),
            confusables = normalizeWordMeaningArray(jsonObject.optJSONArray("confusables"))
        )
    }

    private suspend fun resolveVocabularyId(wordText: String): String {
        val baseId = "vocab-${slugifyVocabularyWord(wordText)}"
        if (vocabularyDao.getById(baseId) == null) return baseId
        return "$baseId-${UUID.randomUUID().toString().take(8)}"
    }

    private fun normalizeWordText(raw: String): String {
        return raw.trim().replace(Regex("\\s+"), " ")
    }

    private fun slugifyVocabularyWord(wordText: String): String {
        return wordText
            .lowercase(Locale.US)
            .replace(Regex("[^a-z0-9]+"), "-")
            .trim('-')
            .takeIf { it.isNotBlank() }
            ?: UUID.randomUUID().toString().take(8)
    }

    private fun buildVocabularyArticlePrompt(wordText: String): String {
        return """
            请为单词或短语 "$wordText" 生成一份 code-199 风格的考研英语深度词汇笔记。

            风格要求：
            1. 像面对面辅导一样，开篇要直接，建议以“考研党你好！”开场；语气风趣但干货密集。
            2. 重点服务 MEM/MBA/管理类联考英语备考，直击阅读、写作、翻译中的高频用法。
            3. 使用 **粗体** 强调关键词，使用 > 引用块展示例句，风格接近 code-199 已有词条。

            explanation 字段必须是 Markdown 正文，包含以下章节，标题文字必须完全一致：
            - 开篇引入（一两句话，直击单词在考研中的地位或常见误区）
            - ### 一、 核心记忆锚点（Root & Logic）
            - ### 二、 考研核心考法（The "Killer" Meaning）
            - ### 三、 词性变体与派生词（Word Family）
            - ### 四、 形近词/近义词辨析（Look-alikes & Synonyms）
            - ### 五、 考研写作替换（Writing Upgrade）
            - ### 六、 沉浸式记忆（Scenario）
            - 结尾鼓励（一句话总结）

            内容要求：
            1. 核心记忆锚点必须讲清词根、构词或短语逻辑，不能只给中文释义。
            2. 在“考研核心考法”里必须给 1-2 个类似考研真题语境的英文例句、中文翻译和解析。
            3. 在“词性变体与派生词”里列出常见派生词，给出词性、中文释义和简短例句。
            4. 在“形近词/近义词辨析”里列出 2-3 个 confusables 和 2-3 个 synonyms，并解释区别。
            5. 在“写作替换”里必须给 Low Level vs High Level 对比。
            6. phonetic 必须是 IPA 音标；如果是短语，也要给自然连读音标或常见读音。

            JSON 字段要求：
            1. explanation 字段只放 Markdown 正文，不要包含 YAML Frontmatter，不要包含 ```markdown。
            2. definitions 列表中的每一项必须包含 pos、part、translation、text；禁止只给 meaning。
            3. tags 必须且只能从白名单中选择 2-4 个，禁止发明新标签。

            只允许输出一个合法 JSON 对象，不要输出 YAML Frontmatter，不要输出 ```json 代码块，不要输出解释文字。
            所有换行必须在 JSON 字符串里写成 \n 转义，不要在字符串中直接换行。

            JSON 格式必须严格如下：
            {
              "word": "$wordText",
              "phonetic": "IPA 音标，例如 /əˈdæpt/",
              "definitions": [
                {
                  "pos": "词性，如 v.",
                  "part": "与 pos 相同，兼容旧数据",
                  "translation": "列表页使用的简短中文释义",
                  "text": "更完整的英文或中文释义"
                }
              ],
              "tags": ["只能从标签白名单中选择 2-4 个"],
              "synonyms": [
                {"word": "近义词", "meaning": "中文含义或细微差异"}
              ],
              "confusables": [
                {"word": "形近词", "meaning": "中文含义或与目标词区别"}
              ],
              "explanation": "完整 Markdown 正文"
            }

            标签白名单：
            阅读, 写作, 翻译, 完型, 核心词汇, 高频, 熟词僻义, 一词多义, 形近词辨析, 经济, 法律, 医学, 教育, 科技, 社会, 文化, 环境, 情感态度, 逻辑词, 写作亮点
        """.trimIndent()
    }

    private fun extractJsonObject(raw: String): String {
        var text = raw.trim()
        if (text.startsWith("```")) {
            text = text
                .removePrefix("```json")
                .removePrefix("```")
                .trim()
            if (text.endsWith("```")) {
                text = text.removeSuffix("```").trim()
            }
        }
        val start = text.indexOf('{')
        val end = text.lastIndexOf('}')
        require(start >= 0 && end > start) { "LLM 未返回 JSON 对象" }
        return text.substring(start, end + 1)
    }

    private fun normalizeDefinitions(source: JSONArray?): JSONArray {
        val result = JSONArray()
        if (source == null) return result

        for (index in 0 until source.length()) {
            val item = source.optJSONObject(index) ?: continue
            val pos = item.optStringOrNull("pos")
                ?: item.optStringOrNull("part")
                ?: item.optStringOrNull("part_of_speech")
                ?: ""
            val translation = item.optStringOrNull("translation")
                ?: item.optStringOrNull("meaning")
                ?: ""
            val text = item.optStringOrNull("text")
                ?: item.optStringOrNull("definition")
                ?: translation
            if (translation.isBlank() && text.isBlank()) continue

            result.put(JSONObject().apply {
                put("pos", pos)
                put("part", pos)
                put("translation", translation.ifBlank { text })
                put("text", text)
            })
        }

        return result
    }

    private fun normalizeTags(source: JSONArray?): JSONArray {
        val whitelist = setOf(
            "阅读", "写作", "翻译", "完型", "核心词汇", "高频", "熟词僻义", "一词多义", "形近词辨析",
            "经济", "法律", "医学", "教育", "科技", "社会", "文化", "环境", "情感态度", "逻辑词", "写作亮点"
        )
        val result = JSONArray()
        val seen = linkedSetOf<String>()
        if (source != null) {
            for (index in 0 until source.length()) {
                val tag = source.optString(index, "").trim()
                if (tag in whitelist) {
                    seen.add(tag)
                }
            }
        }
        if (seen.isEmpty()) {
            seen.add("阅读")
            seen.add("核心词汇")
        }
        seen.take(4).forEach { result.put(it) }
        return result
    }

    private fun normalizeWordMeaningArray(source: JSONArray?): JSONArray? {
        if (source == null) return null
        val result = JSONArray()
        for (index in 0 until source.length()) {
            val item = source.optJSONObject(index) ?: continue
            val word = item.optStringOrNull("word") ?: continue
            val meaning = item.optStringOrNull("meaning")
                ?: item.optStringOrNull("translation")
                ?: item.optStringOrNull("text")
                ?: ""
            result.put(JSONObject().apply {
                put("word", word)
                put("meaning", meaning)
            })
        }
        return if (result.length() == 0) null else result
    }

    private fun JSONObject.optStringOrNull(key: String): String? {
        return optString(key, "").trim().takeIf { it.isNotBlank() && it != "null" }
    }
}
