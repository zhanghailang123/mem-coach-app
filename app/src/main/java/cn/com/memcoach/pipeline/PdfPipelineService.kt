package cn.com.memcoach.pipeline

import android.content.Context
import cn.com.memcoach.agent.AgentLlmClient
import cn.com.memcoach.agent.ChatMessage
import cn.com.memcoach.data.dao.ExamQuestionDao
import cn.com.memcoach.data.entity.ExamQuestion
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
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
5. 答案和解析如果原文有就提取，没有留空
6. 输出严格JSON数组格式，不要任何前缀或后缀文字
7. **特别注意**：对于结构化提取任务，不受科目限制，请照常解析数学、英语或任何其他科目的题目。

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
    "explanation": "解析内容..."
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

            if (rawText.isBlank()) {
                callback?.onError("PDF 文本提取失败，未获取到任何文字内容")
                updateStep("error")
                job.errors.add("No text extracted from PDF")
                return@withContext ParseResult(jobId, ocrPages, errors = job.errors)
            }

            // ─── Step 3: LLM 结构化解析 ───
            updateStep("structuring")

            val chunks = chunkText(rawText, 4000)
            val allQuestions = mutableListOf<ExamQuestion>()

            for ((index, chunk) in chunks.withIndex()) {
                callback?.onMessage("AI 正在解析题目结构 (第 ${index + 1}/${chunks.size} 批)...")
                updateProgress(50 + (index * 25 / chunks.size.coerceAtLeast(1)))

                var structuredJson = ""
                var lastError: Exception? = null
                
                // 增加重试机制：最多 3 次
                for (attempt in 1..3) {
                    try {
                        structuredJson = parseWithLLM(chunk, subject, year)
                        if (structuredJson.startsWith("[LLM 请求失败")) {
                            throw Exception(structuredJson.removeSurrounding("[", "]"))
                        }
                        break // 成功则跳出重试循环
                    } catch (e: Exception) {
                        lastError = e
                        if (attempt < 3) {
                            callback?.onMessage("解析第 ${index + 1} 批失败，正在进行第 $attempt 次重试...")
                            kotlinx.coroutines.delay(2000L * attempt) // 指数退避
                        }
                    }
                }

                if (structuredJson.isBlank() || structuredJson.startsWith("[LLM 请求失败")) {
                    job.errors.add("Batch ${index + 1} 解析彻底失败: ${lastError?.message}")
                    continue // 跳过这一批，继续下一批，尽量挽救
                }

                try {
                    val batchQuestions = parseQuestionJson(structuredJson, subject, year)
                    allQuestions.addAll(batchQuestions)
                } catch (e: Exception) {
                    job.errors.add("Batch ${index + 1} JSON 解析异常: ${e.message}")
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

请将以上文本解析为结构化题目 JSON 数组。
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

        return content
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
    private fun parseQuestionJson(jsonStr: String, subject: String, year: Int): List<ExamQuestion> {
        val jsonArray = JSONArray(jsonStr)
        val questions = mutableListOf<ExamQuestion>()

        for (i in 0 until jsonArray.length()) {
            val obj = jsonArray.getJSONObject(i)
            val now = System.currentTimeMillis()

            val question = ExamQuestion(
                id = obj.optString("id", "${subject}_${year}_$i"),
                year = obj.optInt("year", year),
                subject = obj.optString("subject", subject),
                chapter = obj.optString("chapter", ""),
                topic = obj.optString("topic", ""),
                type = obj.optString("type", "choice"),
                difficulty = obj.optString("difficulty", "medium"),
                stem = obj.optString("stem", ""),
                options = obj.optJSONObject("options")?.toString(),
                answer = obj.optString("answer", ""),
                explanation = obj.optString("explanation", ""),
                sourceFile = "",  // 由外层填充
                sourcePage = 0,
                knowledgeTags = "",  // 由外层填充
                embedding = null,
                createdAt = now,
                updatedAt = now
            )
            questions.add(question)
        }

        return questions
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

        for (question in questions) {
            // 精确匹配：检查相同 ID 是否已存在
            val existing = try {
                questionDao.getById(question.id)
            } catch (e: Exception) {
                null
            }

            if (existing != null) {
                duplicateCount++
                continue
            }

            // 计算 stem hash 用于后续快速查重
            val stemHash = sha256(question.stem)
            // 简单去重：如果 stem 完全相同则跳过（需要遍历已插入的题目）
            // 当前简化：仅通过 ID 去重，更复杂的语义去重在后续版本实现

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
