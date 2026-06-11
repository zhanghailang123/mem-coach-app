package cn.com.memcoach.pipeline

import android.content.Context
import cn.com.memcoach.agent.AgentLlmClient
import cn.com.memcoach.agent.AgentTraceLogger
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
你是一个 MEM 考研真题结构化工具。输入是已经预清洗的 PDF 页/题块文本，输出严格 JSON 数组。

## 科目模型
1. subject 只能是 management_comprehensive 或 english。
2. 管综内部用 section 区分：math、logic、writing。
3. 英语用 subject=english、section=english。
4. 管综题号映射：1-25 为 math，26-55 为 logic，56-57 为 writing。

## 抽取规则
1. 每道题必须拆分为独立条目，只抽取文本中明确出现的内容。
2. 题干页只抽题干和选项；答案页只抽答案和解析；不要根据常识或模型知识补答案。
3. 选择题尽量保留 A/B/C/D/E 选项；共用题干要复制到关联题目的 stem 中。
4. 输出必须包含 question_number、subject、section、source_page、source_page_type、source_text、confidence、parse_notes。
5. 无法确定答案或解析时 answer/explanation 置空，confidence 降低并写 parse_notes。
6. 输出严格 JSON 数组，不要任何前缀、后缀或 Markdown。

## 输出格式
[{
    "id": "management_comprehensive_2025_26",
    "year": 2025,
    "subject": "management_comprehensive",
    "section": "logic",
    "question_number": 26,
    "topic": "conditional_inference",
    "type": "choice",
    "difficulty": "medium",
    "stem": "题干内容...",
    "options": {"A":"选项A","B":"选项B","C":"选项C","D":"选项D","E":"选项E"},
    "answer": "B",
    "explanation": "解析内容...",
    "source_page": 12,
    "source_page_type": "question_page",
    "source_text": "原文证据片段...",
    "answer_source_page": 18,
    "answer_source_text": "答案解析原文片段...",
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

    private data class PdfTextPage(
        val pageNumber: Int,
        val text: String,
        val pageType: String,
        val sectionHint: String?
    )

    private data class PdfParseBatch(
        val index: Int,
        val text: String,
        val pageType: String,
        val sectionHint: String?,
        val pageNumbers: List<Int>
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
        sourceDocumentId: String? = null,
        callback: ProgressCallback? = null
    ): ParseResult = withContext(Dispatchers.IO) {

        val normalizedSubject = normalizeSubject(subject)
        val pipelineTraceId = AgentTraceLogger.newTraceId("pdf_pipeline")
        val job = ParseJob(
            filePath = pdfFile.absolutePath,
            subject = normalizedSubject,
            year = year,
            ocrUtil = PdfOcrUtil(context)
        )
        AgentTraceLogger.event(
            "pdf_pipeline_start",
            mapOf(
                "trace_id" to pipelineTraceId,
                "file" to pdfFile.name,
                "subject_input" to subject,
                "subject" to normalizedSubject,
                "year" to year,
                "job_id" to jobId
            )
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

            val pages = splitPages(rawText)
            val batches = buildParseBatches(pages, normalizedSubject)
            AgentTraceLogger.event(
                "pdf_batches_built",
                mapOf(
                    "trace_id" to pipelineTraceId,
                    "page_count" to pages.size,
                    "batch_count" to batches.size,
                    "page_types" to pages.groupingBy { it.pageType }.eachCount(),
                    "sections" to pages.mapNotNull { it.sectionHint }.groupingBy { it }.eachCount()
                )
            )
            val allQuestions = mutableListOf<ExamQuestion>()

            val completedBatches = java.util.concurrent.atomic.AtomicInteger(0)

            // 并发处理（最大并发 3）
            coroutineScope {
                val deferredResults = batches.map { batch ->
                    async(Dispatchers.IO) {
                        var structuredJson = ""
                        var lastError: Exception? = null
                        AgentTraceLogger.event(
                            "pdf_batch_start",
                            mapOf(
                                "trace_id" to pipelineTraceId,
                                "batch_index" to batch.index,
                                "page_type" to batch.pageType,
                                "section_hint" to batch.sectionHint,
                                "pages" to batch.pageNumbers,
                                "text_length" to batch.text.length,
                                "text_preview" to batch.text.take(600)
                            )
                        )
                        
                        // 增加重试机制：最多 3 次
                        for (attempt in 1..3) {
                            try {
                                structuredJson = parseWithLLM(batch, normalizedSubject, year)
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

                        val parsedResult = if (structuredJson.isBlank() || structuredJson.startsWith("[LLM 请求失败")) {
                            AgentTraceLogger.event(
                                "pdf_batch_error",
                                mapOf(
                                    "trace_id" to pipelineTraceId,
                                    "batch_index" to batch.index,
                                    "error_message" to lastError?.message
                                )
                            )
                            null
                        } else {
                            try {
                                // 注入 batch 索引以保持 ID 唯一且有序
                                parseQuestionJson(
                                    structuredJson,
                                    normalizedSubject,
                                    year,
                                    sourceFile = pdfFile.name,
                                    sourceDocumentId = sourceDocumentId,
                                    batchText = batch.text,
                                    batchIndex = batch.index,
                                    batchPageType = batch.pageType,
                                    batchSectionHint = batch.sectionHint
                                ).also { parsed ->
                                    AgentTraceLogger.event(
                                        "pdf_batch_success",
                                        mapOf(
                                            "trace_id" to pipelineTraceId,
                                            "batch_index" to batch.index,
                                            "parsed_count" to parsed.size
                                        )
                                    )
                                }
                            } catch (e: Exception) {
                                null
                            }
                        }
                        
                        // 在 async 内部实时更新进度
                        val completed = completedBatches.incrementAndGet()
                        updateProgress(50 + (completed * 35 / batches.size.coerceAtLeast(1)))
                        
                        parsedResult
                    }
                }

                // awaitAll 保证结果顺序与 batches 顺序一致
                deferredResults.awaitAll().forEachIndexed { index, batchQuestions ->
                    if (batchQuestions != null) {
                        allQuestions.addAll(batchQuestions)
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

            // ─── Step 3.5: 合并题干与答案 ───
            updateStep("merging")
            callback?.onMessage("正在按题号合并题干与答案解析并尝试回溯缺失信息...")
            val mergedQuestions = mergeQuestions(allQuestions, rawText, normalizedSubject, year)
            callback?.onMessage("合并完成，共 ${mergedQuestions.size} 道完整题目")

            // ─── Step 4: 去重检测 ───
            updateStep("dedup")
            callback?.onMessage("正在进行去重检测...")

            val (newQuestions, dupCount) = deduplicateQuestions(mergedQuestions)
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
        batch: PdfParseBatch,
        subject: String,
        year: Int
    ): String {
        val modeInstruction = when (batch.pageType) {
            "answer_page" -> "当前片段主要是答案解析页：优先抽取 question_number、answer、explanation、answer_source_page、answer_source_text；题干缺失时 stem 可留空或只填可定位的简短题号说明。"
            "question_page" -> "当前片段主要是试题页：优先抽取 question_number、stem、options、source_page、source_text；不要补写答案解析。"
            "mixed_page" -> "当前片段可能同时包含试题和答案解析：请按题号分开抽取，能确定答案来源时填写 answer_source_text。"
            else -> "当前片段噪声较多：只抽取结构完整且能定位题号的题目。"
        }
        val userPrompt = """
## PDF 预清洗片段

大科目 subject：$subject
年份：$year
页类型：${batch.pageType}
模块提示 section：${batch.sectionHint ?: "unknown"}
页码范围：${batch.pageNumbers.joinToString(",")}

$modeInstruction

${batch.text}

请将以上文本解析为结构化题目 JSON 数组。要求：
1. 只抽取文本中明确出现的题目，不要编造题干、答案或解析。
2. subject 必须使用 $subject；如果是管综，section 按题号映射或模块提示填写 math/logic/writing。
3. 必须返回 question_number；无法判断题号的片段不要输出。
4. 如果答案或解析未在文本中明确出现，对应字段必须返回空字符串。
5. 选择题必须尽量保留 A/B/C/D/E 选项；选项缺失时仍可返回，但 confidence 需要降低。
6. source_page 填题目最可能来自的页码；source_page_type 填 ${batch.pageType}。
7. source_text 和 answer_source_text 均只填原文证据片段，最多 800 字。
8. confidence 返回 0 到 1；OCR 乱码、题干不完整、选项不完整或答案不确定时低于 0.7。
9. parse_notes 简短说明不确定原因；确定时可为空。
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

        val jsonStr = extractJsonArray(content)
        
        // 数据完整性校验：如果提取的 JSON 为空数组，但原文本包含明显的题号特征，抛出异常以触发外层重试
        if (jsonStr == "[]" || jsonStr.isBlank()) {
            val hasQuestionMarkers = Regex("(?m)^\\s*(?:[0-9]{1,3})[\\.、)]\\s*").containsMatchIn(batch.text)
            if (hasQuestionMarkers) {
                throw Exception("LLM 返回空数组，但文本中检测到题号特征，触发重试")
            }
        }
        
        return jsonStr
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
                .takeIf { candidate -> candidate.length >= 30 }
        }
    }

    private fun splitPages(text: String): List<PdfTextPage> {
        val marker = Regex("""(?m)^=== 第 (\d+) 页 ===\s*$""")
        val matches = marker.findAll(text).toList()
        if (matches.isEmpty()) {
            val pageType = classifyPage(text)
            return listOf(PdfTextPage(1, text.trim(), pageType, inferSectionFromText(text, normalizeSubject("management_comprehensive"))))
        }
        return matches.mapIndexed { index, match ->
            val pageNumber = match.groupValues[1].toIntOrNull() ?: (index + 1)
            val start = match.range.last + 1
            val end = matches.getOrNull(index + 1)?.range?.first ?: text.length
            val pageText = text.substring(start, end).trim()
            val pageType = classifyPage(pageText)
            PdfTextPage(
                pageNumber = pageNumber,
                text = pageText,
                pageType = pageType,
                sectionHint = inferSectionFromText(pageText, normalizeSubject("management_comprehensive"))
            )
        }.filter { it.text.isNotBlank() }
    }

    private fun classifyPage(text: String): String {
        val normalized = text.take(1200)
        val hasAnswer = normalized.contains(Regex("答案|解析|参考答案|【答案】|【解析】"))
        val questionMarkers = Regex("(?m)^\\s*(?:[0-9]{1,3})[\\.、)]\\s*").findAll(text).count()
        val hasOptions = text.contains(Regex("(?m)^\\s*[A-EＡ-Ｅ][\\.、]\\s*"))
        return when {
            hasAnswer && (questionMarkers >= 2 || hasOptions) -> "mixed_page"
            hasAnswer -> "answer_page"
            questionMarkers >= 2 || hasOptions -> "question_page"
            else -> "noise_page"
        }
    }

    private fun buildParseBatches(pages: List<PdfTextPage>, subject: String): List<PdfParseBatch> {
        val effectivePages = pages.filter { it.pageType != "noise_page" && it.text.length >= 40 }
        val questionBatches = effectivePages
            .filter { it.pageType == "question_page" || it.pageType == "mixed_page" }
            .flatMap { page ->
                val blocks = splitQuestionCandidates("=== 第 ${page.pageNumber} 页 ===\n${page.text}")
                if (blocks.size >= 2) {
                    blocks.chunked(4).map { chunk ->
                        PdfParseBatch(
                            index = 0,
                            text = chunk.joinToString("\n\n--- 下一题 ---\n\n"),
                            pageType = page.pageType,
                            sectionHint = page.sectionHint ?: inferSectionFromText(page.text, subject),
                            pageNumbers = listOf(page.pageNumber)
                        )
                    }
                } else {
                    listOf(
                        PdfParseBatch(
                            index = 0,
                            text = "=== 第 ${page.pageNumber} 页 ===\n${page.text}",
                            pageType = page.pageType,
                            sectionHint = page.sectionHint ?: inferSectionFromText(page.text, subject),
                            pageNumbers = listOf(page.pageNumber)
                        )
                    )
                }
            }
        val answerBatches = effectivePages
            .filter { it.pageType == "answer_page" }
            .chunked(2)
            .map { chunk ->
                PdfParseBatch(
                    index = 0,
                    text = chunk.joinToString("\n\n") { page -> "=== 第 ${page.pageNumber} 页 ===\n${page.text}" },
                    pageType = "answer_page",
                    sectionHint = chunk.mapNotNull { it.sectionHint }.firstOrNull(),
                    pageNumbers = chunk.map { it.pageNumber }
                )
            }
        return (questionBatches + answerBatches).mapIndexed { index, batch -> batch.copy(index = index) }
            .ifEmpty { listOf(PdfParseBatch(0, pages.joinToString("\n\n") { "=== 第 ${it.pageNumber} 页 ===\n${it.text}" }, "mixed_page", null, pages.map { it.pageNumber })) }
    }

    private fun inferSectionFromText(text: String, subject: String): String? {
        if (subject == "english") return "english"
        val numbers = Regex("(?m)^\\s*(?:第\\s*)?(\\d{1,3})[\\.、)]\\s*").findAll(text)
            .mapNotNull { it.groupValues.getOrNull(1)?.toIntOrNull() }
            .toList()
        val first = numbers.firstOrNull()
        if (first != null) return inferSectionFromQuestionNumber(subject, first)
        return when {
            text.contains(Regex("写作|论证有效性|论说文")) -> "writing"
            text.contains(Regex("逻辑|推理|削弱|加强|假设")) -> "logic"
            text.contains(Regex("数学|函数|概率|方程|几何|数列")) -> "math"
            else -> null
        }
    }

    private fun inferSectionFromQuestionNumber(subject: String, questionNumber: Int?): String? {
        if (subject == "english") return "english"
        return when (questionNumber) {
            in 1..25 -> "math"
            in 26..55 -> "logic"
            in 56..57 -> "writing"
            else -> null
        }
    }

    private fun normalizeSubject(raw: String): String {
        return when (raw.trim().lowercase()) {
            "management_comprehensive", "management", "comprehensive", "管综", "管理类综合", "管理类综合能力",
            "math", "logic", "writing", "数学", "逻辑", "写作" -> "management_comprehensive"
            "english", "english2", "english_ii", "英语", "英语二" -> "english"
            else -> raw.trim().ifBlank { "management_comprehensive" }
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
        sourceDocumentId: String?,
        batchText: String,
        batchIndex: Int = 0,
        batchPageType: String = "mixed_page",
        batchSectionHint: String? = null
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
            val rawSubject = obj.optString("subject", subject)
            val normalizedSubject = normalizeSubject(rawSubject)
            val questionNumber = obj.optInt("question_number", -1).takeIf { it > 0 }
            val section = obj.optString("section", "")
                .takeIf { it.isNotBlank() && it != "null" }
                ?: inferSectionFromQuestionNumber(normalizedSubject, questionNumber)
                ?: batchSectionHint
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

            val fallbackId = if (questionNumber != null) {
                "${normalizedSubject}_${year}_${questionNumber}_${stemHash.take(8)}"
            } else {
                "${normalizedSubject}_${year}_${batchIndex + 1}_${i + 1}_${stemHash.take(12)}"
            }
            val sourcePageType = obj.optString("source_page_type", batchPageType)
                .takeIf { it.isNotBlank() && it != "null" }
                ?: batchPageType
            val answerSourceText = obj.optString("answer_source_text", "")
                .takeIf { it.isNotBlank() && it != "null" }
            val answerSourcePage = obj.optInt("answer_source_page", -1).takeIf { it > 0 }
            val mergeStatus = when {
                !answerSourceText.isNullOrBlank() && sourcePageType == "question_page" -> "merged"
                sourcePageType == "answer_page" -> "answer_only"
                else -> "question_only"
            }
            val question = ExamQuestion(
                id = obj.optString("id", "").takeIf { it.isNotBlank() && it != "null" }
                    ?: fallbackId,
                year = obj.optInt("year", year),
                subject = normalizedSubject,
                section = section,
                questionNumber = questionNumber,
                chapter = obj.optString("chapter", ""),
                topic = obj.optString("topic", ""),
                type = obj.optString("type", "choice"),
                difficulty = obj.optString("difficulty", "medium"),
                stem = stem,
                options = options,
                answer = obj.optString("answer", ""),
                explanation = obj.optString("explanation", ""),
                sourceFile = sourceFile,
                sourceDocumentId = sourceDocumentId,
                sourcePage = obj.optInt("source_page", 0),

                knowledgeTags = obj.optJSONArray("knowledge_tags")?.toString() ?: "",
                sourceText = sourceText.take(1200),
                sourcePageType = sourcePageType,
                answerSourceText = answerSourceText?.take(1200),
                answerSourcePage = answerSourcePage,
                mergeStatus = mergeStatus,
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
     * 按 subject, section, questionNumber 合并 question_only 和 answer_only 记录
     */
    private suspend fun mergeQuestions(
        questions: List<ExamQuestion>,
        rawText: String,
        subject: String,
        year: Int
    ): List<ExamQuestion> {
        val mergedList = mutableListOf<ExamQuestion>()
        
        // 按照 year + subject + section + questionNumber 分组
        val grouped = questions.groupBy { 
            "${it.year}_${it.subject}_${it.section}_${it.questionNumber}" 
        }

        for ((key, group) in grouped) {
            // 如果没有题号，无法合并，直接加入
            if (key.endsWith("_null") || key.endsWith("_-1")) {
                mergedList.addAll(group)
                continue
            }

            val questionOnly = group.filter { it.mergeStatus == "question_only" || it.mergeStatus == "merged" }
            val answerOnly = group.filter { it.mergeStatus == "answer_only" }

            if (questionOnly.isEmpty()) {
                // 只有答案，没有题干，尝试回溯
                val bestA = answerOnly.maxByOrNull { it.parseConfidence } ?: answerOnly.first()
                val qn = bestA.questionNumber
                val section = bestA.section
                
                // 触发孤儿回溯
                val recoveredQ = tryRecoverOrphanQuestion(qn, section, rawText, subject, year)
                if (recoveredQ != null && recoveredQ.stem.isNotBlank()) {
                    val mergedQ = bestA.copy(
                        stem = recoveredQ.stem,
                        options = recoveredQ.options,
                        sourceText = recoveredQ.sourceText,
                        sourcePage = recoveredQ.sourcePage,
                        mergeStatus = "merged",
                        parseStatus = "parsed",
                        parseNotes = "通过回溯找回题干"
                    )
                    mergedList.add(mergedQ)
                } else {
                    // 回溯失败，保留但标记 needs_review
                    mergedList.addAll(answerOnly.map { 
                        it.copy(
                            parseStatus = "needs_review", 
                            parseNotes = "只有答案解析，缺失题干，回溯失败"
                        ) 
                    })
                }
                continue
            }

            // 以第一个 question_only 为基础，合并最优的 answer_only
            val baseQ = questionOnly.maxByOrNull { it.parseConfidence } ?: questionOnly.first()
            val bestA = answerOnly.maxByOrNull { it.parseConfidence }

            if (bestA != null && baseQ.answer.isNullOrBlank()) {
                // 执行合并
                val mergedQ = baseQ.copy(
                    answer = bestA.answer ?: baseQ.answer,
                    explanation = bestA.explanation ?: baseQ.explanation,
                    answerSourceText = bestA.answerSourceText ?: bestA.sourceText,
                    answerSourcePage = bestA.answerSourcePage ?: bestA.sourcePage,
                    mergeStatus = "merged",
                    parseConfidence = (baseQ.parseConfidence + bestA.parseConfidence) / 2f,
                    parseNotes = listOfNotNull(baseQ.parseNotes, bestA.parseNotes, "已与答案页合并").joinToString("；")
                )
                mergedList.add(mergedQ)
                
                // 将其他未合并的同题号记录也加进去，但置信度降低，避免丢失信息
                val others = group.filter { it.id != baseQ.id && it.id != bestA.id }
                mergedList.addAll(others.map { it.copy(parseConfidence = it.parseConfidence * 0.8f) })
            } else if (baseQ.answer.isNullOrBlank() && bestA == null) {
                // 有题干没有答案，尝试回溯答案
                val qn = baseQ.questionNumber
                val section = baseQ.section
                val recoveredA = tryRecoverOrphanAnswer(qn, section, rawText, subject, year)
                if (recoveredA?.answer?.isNotBlank() == true) {
                    val mergedQ = baseQ.copy(
                        answer = recoveredA.answer,
                        explanation = recoveredA.explanation,
                        answerSourceText = recoveredA.answerSourceText,
                        answerSourcePage = recoveredA.answerSourcePage,
                        mergeStatus = "merged",
                        parseNotes = listOfNotNull(baseQ.parseNotes, "通过回溯找回答案").joinToString("；")
                    )
                    mergedList.add(mergedQ)
                    val others = group.filter { it.id != baseQ.id }
                    mergedList.addAll(others.map { it.copy(parseConfidence = it.parseConfidence * 0.8f) })
                } else {
                    mergedList.addAll(group)
                }
            } else {
                mergedList.addAll(group)
            }
        }

        return mergedList
    }

    private suspend fun tryRecoverOrphanQuestion(
        questionNumber: Int?,
        section: String?,
        rawText: String,
        subject: String,
        year: Int
    ): ExamQuestion? {
        if (questionNumber == null) return null
        val prompt = """
你是一个 MEM 考研真题回溯工具。
在初步解析中，我们只找到了第 $questionNumber 题的答案，但遗漏了题干。
请在以下完整文档文本中，专门寻找并提取第 $questionNumber 题的题干和选项。
如果找到，请严格返回 JSON 数组格式，包含 stem, options, source_text, source_page。
如果没有找到，请返回空数组 []。

## 文档内容片段 (截取前 20000 字)
${rawText.take(20000)}
"""
        return performRecovery(prompt, subject, year, questionNumber, section)
    }

    private suspend fun tryRecoverOrphanAnswer(
        questionNumber: Int?,
        section: String?,
        rawText: String,
        subject: String,
        year: Int
    ): ExamQuestion? {
        if (questionNumber == null) return null
        val prompt = """
你是一个 MEM 考研真题回溯工具。
在初步解析中，我们只找到了第 $questionNumber 题的题干，但遗漏了答案和解析。
请在以下完整文档文本中，专门寻找并提取第 $questionNumber 题的答案和解析。
如果找到，请严格返回 JSON 数组格式，包含 answer, explanation, answer_source_text, answer_source_page。
如果没有找到，请返回空数组 []。

## 文档内容片段 (截取后 20000 字，答案通常在后面)
${rawText.takeLast(20000)}
"""
        return performRecovery(prompt, subject, year, questionNumber, section)
    }

    private suspend fun performRecovery(
        userPrompt: String,
        subject: String,
        year: Int,
        questionNumber: Int,
        section: String?
    ): ExamQuestion? {
        val messages = listOf(
            ChatMessage(role = "system", content = STRUCTURING_SYSTEM_PROMPT),
            ChatMessage(role = "user", content = userPrompt)
        )
        try {
            val result = llmClient.completeTurn(messages = messages, modelId = null)
            var content = result.content.trim()
            if (content.startsWith("```json")) content = content.removePrefix("```json").trim()
            else if (content.startsWith("```")) content = content.removePrefix("```").trim()
            if (content.endsWith("```")) content = content.removeSuffix("```").trim()
            content = extractJsonArray(content)
            
            val jsonArray = JSONArray(content)
            if (jsonArray.length() > 0) {
                val obj = jsonArray.getJSONObject(0)
                return ExamQuestion(
                    id = "", year = year, subject = subject, section = section,
                    questionNumber = questionNumber,
                    stem = obj.optString("stem", ""),
                    options = obj.optJSONObject("options")?.toString(),
                    answer = obj.optString("answer", ""),
                    explanation = obj.optString("explanation", ""),
                    sourceText = obj.optString("source_text", ""),
                    sourcePage = obj.optInt("source_page", 0),
                    answerSourceText = obj.optString("answer_source_text", ""),
                    answerSourcePage = obj.optInt("answer_source_page", 0),
                    createdAt = 0, updatedAt = 0, sourceFile = "", sourcePageType = "", mergeStatus = "", parseStatus = "",
                    chapter = "", topic = "", type = "choice", difficulty = "medium", knowledgeTags = "", stemHash = "", parseConfidence = 1.0f, parseNotes = ""
                )
            }
        } catch (e: Exception) {
            // 回溯失败忽略
        }
        return null
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
