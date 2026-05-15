package cn.com.memcoach.pipeline

import android.content.Context
import cn.com.memcoach.agent.AgentLlmClient
import cn.com.memcoach.agent.ChatMessage
import cn.com.memcoach.data.dao.ExamQuestionDao
import cn.com.memcoach.data.entity.ExamQuestion
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/**
 * PDF 真题解析 Pipeline 编排器。
 *
 * 完整流程（5 步）：
 *   Step 1: 尝试内嵌文本提取 → 有内容则跳过 OCR
 *   Step 2: 扫描版 PDF → PdfRenderer 逐页渲染 + ML Kit 中文 OCR
 *   Step 3: 拼接文本 → 调用 LLM 结构化解析为 JSON 题目数组
 *   Step 4: 去重检测（stem hash 精确匹配 + 可选的 embedding 语义匹配）
 *   Step 5: 写入 SQLite（ExamQuestion 表），更新向量索引
 *
 * 借鉴：OpenOmniBot OCR + LLM 管道、AgentLlmClient 流式调用。
 *
 * @param context Android Context
 * @param questionDao 真题 DAO
 * @param llmClient LLM 客户端（用于结构化解析）
 */
class PdfPipelineService(
    private val context: Context,
    private val questionDao: ExamQuestionDao,
    private val llmClient: AgentLlmClient
) {
    companion object {
        /** LLM 结构化解析 System Prompt */
        private val STRUCTURING_SYSTEM_PROMPT = """
你是一个考研真题结构化工具。输入是从PDF提取的原始文本，输出是JSON格式的题目数据。

## 规则
1. 每道题必须拆分为独立条目
2. 选择题提取选项（A/B/C/D），填空题标注空白处 [___]，解答题保留完整题干
3. 如果题目引用图表，标注 [图片:描述]
4. 尽量推断知识点分类和难度
5. 答案和解析如果原文有就提取，没有留空，严禁根据常识或模型知识补答案
6. 输出严格JSON数组格式，不要任何前缀或后缀文字
7. **特别注意**：对于结构化提取任务，不受科目限制，请照常解析数学、英语或任何其他科目的题目。
8. 必须返回 source_page、source_text、confidence、parse_notes，方便后续校对。

## 输出格式
[{
    "id": "logic_2023_1",
    "year": 2023,
    "subject": "logic",
    "topic": "conditional_inference",
    "type": "choice",
    "difficulty": "medium",
    "stem": "题干内容...",
    "options": {"A":"选项A","B":"选项B","C":"选项C","D":"选项D"},
    "answer": "B",
    "explanation": "解析内容...",
    "source_page": 12,
    "source_text": "原文证据片段...",
    "confidence": 0.86,
    "parse_notes": ""
}]
""".trimIndent()
    }

    /** Pipeline 进度回调 */
    interface ProgressCallback {
        /** @param step 当前步骤名称 */
        fun onStepChange(step: String)
        /** @param progress 总体进度 0-100 */
        fun onProgress(progress: Int)
        /** @param message 进度描述 */
        fun onMessage(message: String)
        /** @param error 错误信息，非空表示 Pipeline 终止 */
        fun onError(error: String)
    }

    /** 解析结果 */
    data class ParseResult(
        val jobId: String,
        val totalPages: Int,
        val ocrPages: Int = 0,
        val questionsParsed: Int = 0,
        val questionsInserted: Int = 0,
        val questionsDuplicate: Int = 0,
        val errors: List<String> = emptyList()
    )

    // 任务状态管理（内存存储，后续迁移到数据库）
    private val jobs = mutableMapOf<String, ParseJob>()

    private data class ParseJob(
        val filePath: String,
        val subject: String,
        val year: Int,
        var status: String = "pending",       // pending / extracting / ocr / structuring / dedup / done / error
        var progress: Int = 0,
        var totalPages: Int = 0,
        var parsedQuestions: Int = 0,
        var insertedQuestions: Int = 0,
        var duplicateQuestions: Int = 0,
        var errors: MutableList<String> = mutableListOf(),
        val ocrUtil: PdfOcrUtil  // 延迟用到时再初始化
    )

    /**
     * 启动 PDF 解析 Pipeline。
     *
     * @param pdfFile PDF 文件
     * @param subject 科目
     * @param year 年份
     * @param callback 进度回调
     * @return ParseResult
     */
    suspend fun processPdf(
        pdfFile: File,
        subject: String,
        year: Int,
        jobId: String,
        callback: ProgressCallback? = null
    ): ParseResult = withContext(Dispatchers.IO) {
        val job = ParseJob(
            filePath = pdfFile.absolutePath,
            subject = subject,
            year = year,
            ocrUtil = PdfOcrUtil(context)
        )
        jobs[jobId] = job

        fun updateStep(step: String) {
            job.status = step
            callback?.onStepChange(step)
        }

        fun updateProgress(progress: Int) {
            job.progress = progress.coerceIn(0, 100)
            callback?.onProgress(job.progress)
        }

        try {
            // ─── Step 1: 提取 PDF 内嵌文本 ───
            updateStep("extracting")
            updateProgress(5)
            callback?.onMessage("正在提取 PDF 内嵌文本...")


            var rawText = ""
            val ocrPages = try {
                val pageCount = job.ocrUtil.getPageCount(pdfFile)
                job.totalPages = pageCount
                pageCount
            } catch (e: Exception) {
                callback?.onError("无法读取 PDF: ${e.message}")
                job.status = "error"
                job.errors.add("PDF read error: ${e.message}")
                return@withContext ParseResult(jobId, 0, errors = job.errors)
            }

            // 尝试提取内嵌文本
            rawText = try {
                job.ocrUtil.tryExtractEmbeddedText(pdfFile)
            } catch (e: Exception) {
                ""
            }

            if (rawText.isNotBlank()) {
                callback?.onMessage("内嵌文本提取成功，跳过 OCR")
                updateProgress(30)
            } else {
                // ─── Step 2: OCR 扫描版 PDF ───
                updateStep("ocr")
                callback?.onMessage("检测到扫描版 PDF，开始 OCR 识别（共 ${ocrPages} 页）...")

                val sb = StringBuilder()
                for (i in 0 until ocrPages) {
                    updateProgress(10 + (i * 40 / ocrPages.coerceAtLeast(1)))
                    callback?.onMessage("OCR 识别第 ${i + 1}/$ocrPages 页...")

                    try {
                        val bitmap = job.ocrUtil.renderPage(pdfFile, i)
                        try {
                            val text = job.ocrUtil.recognizeText(bitmap)
                            sb.appendLine("=== 第 ${i + 1} 页 ===")
                            sb.appendLine(text)
                            sb.appendLine()
                        } finally {
                            bitmap.recycle()
                        }
                    } catch (e: Exception) {
                        callback?.onMessage("第 ${i + 1} 页 OCR 失败: ${e.message}")
                        job.errors.add("Page ${i + 1} OCR failed: ${e.message}")
                    }
                }
                rawText = sb.toString()
                updateProgress(50)
            }

            rawText = normalizeExtractedText(rawText)

            if (rawText.isBlank()) {
                callback?.onError("PDF 文本提取失败，未获取到任何文字内容")
                updateStep("error")
                job.errors.add("No text extracted from PDF")
                return@withContext ParseResult(jobId, ocrPages, errors = job.errors)
            }

            // ─── Step 3: LLM 结构化解析 ───
            updateStep("structuring")

            // 优先按题号切为候选题块，减少跨题串题；候选不足时回退到页分块。
            val candidateBlocks = splitQuestionCandidates(rawText)
            val batches = if (candidateBlocks.size >= 2) {
                candidateBlocks.chunked(4).map { it.joinToString("\n\n--- 下一题 ---\n\n") }
            } else {
                chunkByPages(rawText, pagesPerBatch = 2, overlapChars = 500)
            }
            val allQuestions = mutableListOf<ExamQuestion>()

            // 并发处理（最大并发 3）
            coroutineScope {
                val deferredResults = batches.mapIndexed { index, batchText ->
                    async(Dispatchers.IO) {
                        var structuredJson = ""
                        var lastError: Exception? = null
                        
                        // 增加重试机制：最多 3 次
                        for (attempt in 1..3) {
                            try {
                                structuredJson = parseWithLLM(batchText, subject, year)
                                if (structuredJson.startsWith("[LLM 请求失败")) {
                                    throw Exception(structuredJson.removeSurrounding("[", "]"))
                                }
                                break 
                            } catch (e: Exception) {
                                lastError = e
                                if (attempt < 3) {
                                    delay(2000L * attempt)
                                }
                            }
                        }

                        if (structuredJson.isBlank() || structuredJson.startsWith("[LLM 请求失败")) {
                            null
                        } else {
                            try {
                                // 注入 batch 索引以保持 ID 唯一且有序
                                parseQuestionJson(
                                    structuredJson,
                                    subject,
                                    year,
                                    sourceFile = pdfFile.name,
                                    batchText = batchText,
                                    batchIndex = index
                                )
                            } catch (e: Exception) {
                                null
                            }
                        }
                    }
                }

                // awaitAll 保证结果顺序与 batches 顺序一致
                deferredResults.awaitAll().forEachIndexed { index, batchQuestions ->
                    if (batchQuestions != null) {
                        allQuestions.addAll(batchQuestions)
                        // 更新进度：50% + 每批次的占比
                        updateProgress(50 + ((index + 1) * 35 / batches.size.coerceAtLeast(1)))
                    } else {
                        job.errors.add("第 ${index + 1} 批解析失败")
                    }
                }
            }

            if (allQuestions.isEmpty()) {
                callback?.onError("题目解析失败：未识别到任何有效题目")
                updateStep("error")
                return@withContext ParseResult(jobId, ocrPages, errors = job.errors)
            }

            job.parsedQuestions = allQuestions.size
            callback?.onMessage("解析完成，共识别 ${allQuestions.size} 道题目")

            // ─── Step 4: 去重检测 ───
            updateStep("dedup")
            callback?.onMessage("正在进行去重检测...")

            val (newQuestions, dupCount) = deduplicateQuestions(allQuestions)
            updateProgress(85)
            callback?.onMessage("去重完成：新增 ${newQuestions.size} 题，重复 $dupCount 题")

            // ─── Step 5: 入库 ───
            updateStep("inserting")
            callback?.onMessage("正在写入数据库...")

            var insertedCount = 0
            for (question in newQuestions) {
                try {
                    questionDao.insert(question)
                    insertedCount++
                } catch (e: Exception) {
                    job.errors.add("Insert ${question.id} failed: ${e.message}")
                }
            }

            job.insertedQuestions = insertedCount
            job.duplicateQuestions = dupCount
            updateStep("done")
            updateProgress(100)

            callback?.onMessage("完成！新增 $insertedCount 道题目，重复 $dupCount 题")


            ParseResult(
                jobId = jobId,
                totalPages = ocrPages,
                ocrPages = if (rawText.isNotBlank()) ocrPages else 0,
                questionsParsed = allQuestions.size,
                questionsInserted = insertedCount,
                questionsDuplicate = dupCount,
                errors = job.errors
            )
        } catch (e: Exception) {
            job.status = "error"
            job.errors.add("Unexpected error: ${e.message}")
            callback?.onError("Pipeline 异常: ${e.message}")
            ParseResult(jobId, 0, errors = job.errors)
        }
    }

    /**
     * 提取 PDF 前几页文本，供 Agent 在聊天中基于 document_id 做轻量查询。
     * 不写入数据库，只返回当前文件的可读文本预览。
     */
    suspend fun extractTextPreview(
        pdfFile: File,
        maxPages: Int = 3
    ): String = withContext(Dispatchers.IO) {
        val ocrUtil = PdfOcrUtil(context)
        val embeddedText = try {
            ocrUtil.tryExtractEmbeddedText(pdfFile)
        } catch (e: Exception) {
            ""
        }
        if (embeddedText.isNotBlank()) {
            return@withContext embeddedText.take(12000)
        }

        val pageCount = ocrUtil.getPageCount(pdfFile)
        val pagesToRead = maxPages.coerceAtLeast(1).coerceAtMost(pageCount)
        val sb = StringBuilder()
        for (i in 0 until pagesToRead) {
            val bitmap = ocrUtil.renderPage(pdfFile, i)
            try {
                val text = ocrUtil.recognizeText(bitmap)
                sb.appendLine("=== 第 ${i + 1} 页 ===")
                sb.appendLine(text)
                sb.appendLine()
            } finally {
                bitmap.recycle()
            }
        }
        sb.toString().take(12000)
    }

    /**
     * 调用 LLM 进行结构化解析。
     */
    private suspend fun parseWithLLM(

        chunkText: String,
        subject: String,
        year: Int
    ): String {
        val userPrompt = """
## PDF 原始文本 (片段)

来源科目：$subject
年份：$year

$chunkText

请将以上文本解析为结构化题目 JSON 数组。要求：
1. 只抽取文本中明确出现的题目，不要编造题干、答案或解析。
2. 如果答案或解析未在文本中明确出现，对应字段必须返回空字符串。
3. 选择题必须尽量保留 A/B/C/D 选项；选项缺失时仍可返回，但 confidence 需要降低。
4. source_page 填题目最可能来自的页码；无法判断填 0。
5. source_text 填支持该题的原始片段，最多 800 字。
6. confidence 返回 0 到 1；OCR 乱码、题干不完整、选项不完整或答案不确定时低于 0.7。
7. parse_notes 简短说明不确定原因；确定时可为空。
""".trimIndent()

        val messages = listOf(
            ChatMessage(role = "system", content = STRUCTURING_SYSTEM_PROMPT),
            ChatMessage(role = "user", content = userPrompt)
        )

        // 使用标准模型进行解析（不需要工具调用）
        val result = llmClient.completeTurn(
            messages = messages,
            modelId = null  // 由 LLM Router 自动选择
        )

        // 尝试从回复中提取 JSON 数组
        var content = result.content.trim()

        // 移除可能的 Markdown 代码块标记
        if (content.startsWith("```json")) {
            content = content.removePrefix("```json").trim()
            if (content.endsWith("```")) {
                content = content.removeSuffix("```").trim()
            }
        } else if (content.startsWith("```")) {
            content = content.removePrefix("```").trim()
            if (content.endsWith("```")) {
                content = content.removeSuffix("```").trim()
            }
        }

        return extractJsonArray(content)
    }

    private fun extractJsonArray(content: String): String {
        val start = content.indexOf('[')
        val end = content.lastIndexOf(']')
        return if (start >= 0 && end > start) content.substring(start, end + 1).trim() else content
    }

    private fun normalizeExtractedText(text: String): String {
        if (text.isBlank()) return ""
        return text
            .replace('\u00A0', ' ')
            .replace('—', '-')
            .replace('－', '-')
            .replace('（', '(')
            .replace('）', ')')
            .replace('．', '.')
            .replace('。', '.')
            .replace(Regex("[\\t\\x0B\\f\\r]+"), " ")
            .lines()
            .map { it.trim() }
            .filter { line ->
                line.isNotBlank() &&
                    !line.matches(Regex("""^[-_ ]*$""")) &&
                    !line.matches(Regex("""^第?\s*\d+\s*[页頁]$""")) &&
                    !line.matches(Regex("""^\d+\s*/\s*\d+$"""))
            }
            .joinToString("\n")
            .replace(Regex("([.!?！？；;：:])\\n(?=[^A-DＡ-Ｄa-dａ-ｄ①②③④(【])"), "$1")
            .replace(Regex("\\n{3,}"), "\n\n")
            .trim()
    }

    private fun splitQuestionCandidates(text: String): List<String> {
        val marker = Regex(
            """(?m)^(?:=== 第 \d+ 页 ===\s*)?(?:第\s*)?(?:[0-9]{1,3}|[一二三四五六七八九十百]{1,4})[\.、)]\s*|^\s*\(([0-9]{1,3})\)\s+"""
        )
        val matches = marker.findAll(text).toList()
        if (matches.size < 2) return emptyList()

        return matches.mapIndexedNotNull { index, match ->
            val start = match.range.first
            val end = matches.getOrNull(index + 1)?.range?.first ?: text.length
            text.substring(start, end)
                .trim()
                .takeIf { candidate ->
                    candidate.length >= 30 &&
                        !candidate.contains(Regex("""(?m)^\s*(参考答案|答案解析|答案|解析)\s*[:：]?\s*$"""))
                }
        }
    }

    /**
     * 智能切片：按页分组，并增加重叠
     */
    private fun chunkByPages(text: String, pagesPerBatch: Int, overlapChars: Int): List<String> {
        val pageMarker = Regex("""=== 第 (\d+) 页 ===""")
        val pages = text.split(pageMarker).filter { it.isNotBlank() }
        val markers = pageMarker.findAll(text).toList()
        
        if (pages.isEmpty()) return listOf(text)

        val result = mutableListOf<String>()
        var i = 0
        while (i < pages.size) {
            val batchBuilder = StringBuilder()
            
            // 如果不是第一批，先塞入上一批末尾的重叠内容
            if (i > 0) {
                val prevPage = pages[i - 1]
                val overlap = if (prevPage.length > overlapChars) prevPage.takeLast(overlapChars) else prevPage
                batchBuilder.append("... [接上一页末尾] ...\n").append(overlap).append("\n\n")
            }

            // 塞入当前批次的页内容
            val end = minOf(i + pagesPerBatch, pages.size)
            for (j in i until end) {
                if (j < markers.size) {
                    batchBuilder.append(markers[j].value).append("\n")
                }
                batchBuilder.append(pages[j]).append("\n")
            }
            
            result.add(batchBuilder.toString())
            i += pagesPerBatch
        }
        return result
    }

    private fun chunkText(text: String, chunkSize: Int): List<String> {
        if (text.length <= chunkSize) return listOf(text)
        val chunks = mutableListOf<String>()
        var start = 0
        while (start < text.length) {
            val end = minOf(start + chunkSize, text.length)
            chunks.add(text.substring(start, end))
            start = end
        }
        return chunks
    }

    /**
     * 将 LLM 返回的 JSON 数组解析为 ExamQuestion 列表。
     */
    private fun parseQuestionJson(
        jsonStr: String,
        subject: String,
        year: Int,
        sourceFile: String,
        batchText: String,
        batchIndex: Int = 0
    ): List<ExamQuestion> {
        val jsonArray = JSONArray(jsonStr)
        val questions = mutableListOf<ExamQuestion>()

        for (i in 0 until jsonArray.length()) {
            val obj = jsonArray.getJSONObject(i)
            val now = System.currentTimeMillis()
            val stem = obj.optString("stem", "").trim()
            if (stem.length < 12) continue

            val normalizedStem = normalizeForHash(stem)
            val stemHash = sha256(normalizedStem)
            val options = obj.optJSONObject("options")?.toString()
            val confidence = obj.optDouble("confidence", estimateConfidence(stem, options, obj.optString("answer", ""))).toFloat().coerceIn(0f, 1f)
            val sourceText = obj.optString("source_text", "")
                .takeIf { it.isNotBlank() && it != "null" }
                ?: batchText.take(800)
            val parseNotes = obj.optString("parse_notes", "")
                .takeIf { it.isNotBlank() && it != "null" }
                ?: buildParseNotes(stem, options, confidence)
            val parseStatus = when {
                confidence < 0.55f -> "needs_review"
                parseNotes != null -> "needs_review"
                else -> "parsed"
            }

            val fallbackId = "${subject}_${year}_${batchIndex + 1}_${i + 1}_${stemHash.take(12)}"
            val question = ExamQuestion(
                id = obj.optString("id", "").takeIf { it.isNotBlank() && it != "null" }
                    ?: fallbackId,
                year = obj.optInt("year", year),
                subject = obj.optString("subject", subject),
                chapter = obj.optString("chapter", ""),
                topic = obj.optString("topic", ""),
                type = obj.optString("type", "choice"),
                difficulty = obj.optString("difficulty", "medium"),
                stem = stem,
                options = options,
                answer = obj.optString("answer", ""),
                explanation = obj.optString("explanation", ""),
                sourceFile = sourceFile,
                sourcePage = obj.optInt("source_page", 0),
                knowledgeTags = obj.optJSONArray("knowledge_tags")?.toString() ?: "",
                sourceText = sourceText.take(1200),
                stemHash = stemHash,
                parseConfidence = confidence,
                parseStatus = parseStatus,
                parseNotes = parseNotes,
                embedding = null,
                createdAt = now,
                updatedAt = now
            )
            questions.add(question)
        }

        return questions
    }

    private fun normalizeForHash(text: String): String {
        return text.lowercase()
            .replace(Regex("""\s+"""), "")
            .replace(Regex("""[，。！？；：,.!?;:\"'“”‘’（）()【】\[\]{}<>《》]"""), "")
            .trim()
    }

    private fun estimateConfidence(stem: String, options: String?, answer: String): Double {
        var score = 0.72
        if (stem.length < 30) score -= 0.18
        if (options.isNullOrBlank()) score -= 0.12
        if (answer.isBlank() || answer == "null") score -= 0.08
        if (stem.contains("�") || stem.count { it == '?' || it == '？' } >= 4) score -= 0.16
        return score.coerceIn(0.25, 0.95)
    }

    private fun buildParseNotes(stem: String, options: String?, confidence: Float): String? {
        val notes = mutableListOf<String>()
        if (stem.length < 30) notes.add("题干偏短")
        if (options.isNullOrBlank()) notes.add("选项缺失或无法识别")
        if (confidence < 0.55f) notes.add("解析置信度较低")
        return notes.takeIf { it.isNotEmpty() }?.joinToString("；")
    }

    /**
     * 去重检测：精确匹配 stem hash。
     * 后续可扩展为 embedding 语义匹配。
     */
    private suspend fun deduplicateQuestions(
        questions: List<ExamQuestion>
    ): Pair<List<ExamQuestion>, Int> {
        val newQuestions = mutableListOf<ExamQuestion>()
        var duplicateCount = 0

        val seenStemHashes = mutableSetOf<String>()
        for (question in questions) {
            val stemHash = question.stemHash ?: sha256(normalizeForHash(question.stem))
            if (!seenStemHashes.add(stemHash)) {
                duplicateCount++
                continue
            }

            // 精确匹配：检查相同 ID 是否已存在
            val existingById = try {
                questionDao.getById(question.id)
            } catch (e: Exception) {
                null
            }

            if (existingById != null) {
                duplicateCount++
                continue
            }

            val existingByStemHash = try {
                questionDao.countByStemHashAndSubject(stemHash, question.subject) > 0
            } catch (e: Exception) {
                questionDao.countByStemAndSubject(question.stem, question.subject) > 0
            }

            if (existingByStemHash) {
                duplicateCount++
                continue
            }

            newQuestions.add(question)
        }

        return newQuestions to duplicateCount
    }

    /**
     * 计算字符串的 SHA-256 哈希。
     */
    private fun sha256(input: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val hashBytes = digest.digest(input.toByteArray())
        return hashBytes.joinToString("") { "%02x".format(it) }
    }

    /**
     * 获取所有活跃（未完成且未报错）的任务 ID
     */
    fun getActiveJobIds(): List<String> {
        return jobs.filter { (_, job) -> 
            job.status != "done" && job.status != "error" && job.status != "cancelled"
        }.keys.toList()
    }

    /**
     * 查询作业状态。
     */
    fun getJobStatus(jobId: String): JSONObject? {
        val job = jobs[jobId] ?: return null
        return JSONObject().apply {
            put("job_id", jobId)
            put("status", job.status)
            put("progress", job.progress)
            put("total_pages", job.totalPages)
            put("parsed_questions", job.parsedQuestions)
            put("inserted_questions", job.insertedQuestions)
            put("duplicate_questions", job.duplicateQuestions)
            put("errors", JSONArray(job.errors))
        }
    }

    /**
     * 取消指定作业（暂未实现真正的取消逻辑）。
     */
    fun cancelJob(jobId: String) {
        jobs[jobId]?.status = "cancelled"
    }
}
