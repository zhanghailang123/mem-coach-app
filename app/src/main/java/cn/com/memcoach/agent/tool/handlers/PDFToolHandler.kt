package cn.com.memcoach.agent.tool.handlers

import cn.com.memcoach.agent.tool.ToolDefinition
import cn.com.memcoach.agent.tool.ToolHandler
import org.json.JSONObject

/**
 * PDF 处理工具处理器 —— 提供 PDF 上传、OCR 识别状态查询、结构化解析等工具。
 *
 * 覆盖工具：
 * - pdf_upload            —— 接收 PDF 文件路径，启动 OCR+结构化解析 Pipeline
 * - pdf_parse_status      —— 查询 PDF 解析进度和结果
 * - pdf_ocr_recognize     —— 对单页图片进行 OCR 识别（调试用）
 *
 * 注意：真实 OCR 能力需要在 Task #6（implement-pdf-pipeline）中实现。
 * 本 Handler 目前提供工具定义和桩实现，后续替换为完整的 ML Kit OCR + LLM 结构化流水线。
 */
class PDFToolHandler : ToolHandler {

    // 内存中的解析状态（MVP 阶段用内存存储，后续迁移到数据库）
    private data class ParseJob(
        val filePath: String,
        var status: String,         // pending / ocr / structuring / done / error
        var progress: Int = 0,      // 0-100
        var totalPages: Int = 0,
        var parsedPages: Int = 0,
        var questions: String? = null,  // JSON 格式的解析结果
        var error: String? = null,
        val createdAt: Long = System.currentTimeMillis()
    )

    private val jobs = mutableMapOf<String, ParseJob>()
    private var jobIdCounter = 0L

    override val toolNames = setOf(
        "pdf_upload",
        "pdf_parse_status",
        "pdf_ocr_recognize"
    )

    override suspend fun execute(toolName: String, arguments: String): String {
        return try {
            val args = JSONObject(arguments)
            when (toolName) {
                "pdf_upload" -> uploadPdf(args)
                "pdf_parse_status" -> getParseStatus(args)
                "pdf_ocr_recognize" -> ocrRecognize(args)
                else -> errorJson("unknown tool: $toolName")
            }
        } catch (e: Exception) {
            errorJson("execute error: ${e.message?.replace("\"", "'")}")
        }
    }

    override fun getDefinitions(): List<ToolDefinition> = listOf(
        ToolDefinition(
            name = "pdf_upload",
            description = "上传真题 PDF 文件，启动 OCR 识别与 LLM 结构化解析 Pipeline。返回 jobId 用于后续查询进度。支持扫描版和文字版 PDF。",
            parameters = """
{
  "type": "object",
  "properties": {
    "file_path": {
      "type": "string",
      "description": "PDF 文件的本地路径或 URI"
    },
    "subject": {
      "type": "string",
      "description": "科目：logic/writing/math/english",
      "enum": ["logic", "writing", "math", "english"]
    },
    "year": {
      "type": "integer",
      "description": "真题年份，如 2023"
    }
  },
  "required": ["file_path", "subject", "year"]
}
""".trimIndent()
        ),
        ToolDefinition(
            name = "pdf_parse_status",
            description = "查询 PDF 解析任务的状态和进度。返回当前阶段（OCR/结构化/完成）、进度百分比、已解析题目列表。",
            parameters = """
{
  "type": "object",
  "properties": {
    "job_id": {
      "type": "string",
      "description": "pdf_upload 返回的任务 ID"
    }
  },
  "required": ["job_id"]
}
""".trimIndent()
        ),
        ToolDefinition(
            name = "pdf_ocr_recognize",
            description = "对 PDF 的指定页面进行 OCR 文字识别（调试和预览用）。返回该页的识别文本。",
            parameters = """
{
  "type": "object",
  "properties": {
    "file_path": {
      "type": "string",
      "description": "PDF 文件路径"
    },
    "page_number": {
      "type": "integer",
      "description": "页码（从 1 开始）"
    }
  },
  "required": ["file_path", "page_number"]
}
""".trimIndent()
        )
    )

    // ─── 工具实现（桩实现，后续替换为完整 Pipeline）───

    /**
     * 上传 PDF 并启动解析任务
     *
     * 真实实现将：
     * 1. 复制 PDF 到应用私有目录
     * 2. 尝试 pdftotext 提取文本
     * 3. 如果提取为空 → 用 PdfRenderer 逐页渲染 + ML Kit OCR
     * 4. 拼接 OCR 文本 → 调用 LLM 结构化解析
     * 5. 去重 → 写入 SQLite
     */
    private fun uploadPdf(args: JSONObject): String {
        val filePath = args.optString("file_path", "")
        if (filePath.isBlank()) return errorJson("file_path 必填")
        val subject = args.optString("subject", "")
        if (subject.isBlank()) return errorJson("subject 必填")
        val year = args.optInt("year", -1)
        if (year <= 0) return errorJson("year 必填且必须大于 0")

        jobIdCounter++
        val jobId = "pdf_job_$jobIdCounter"
        val job = ParseJob(
            filePath = filePath,
            status = "pending",
            totalPages = 0
        )
        jobs[jobId] = job

        // 桩实现：直接返回 jobId，后台任务未启用
        // 后续在 Task #6 中实现真正的后台 Pipeline
        job.status = "pending"
        job.progress = 0

        val json = JSONObject()
        json.put("job_id", jobId)
        json.put("status", "pending")
        json.put("file_path", filePath)
        json.put("subject", subject)
        json.put("year", year)
        json.put("message", "PDF 已接收，解析 Pipeline 尚未启用（Task #6 待实现）。当前为桩实现，返回模拟状态。")
        return json.toString()
    }

    /**
     * 查询解析进度
     */
    private fun getParseStatus(args: JSONObject): String {
        val jobId = args.optString("job_id", "")
        if (jobId.isBlank()) return errorJson("job_id 必填")

        val job = jobs[jobId] ?: return errorJson("任务不存在: $jobId")

        val json = JSONObject()
        json.put("job_id", jobId)
        json.put("status", job.status)
        json.put("progress", job.progress)
        json.put("total_pages", job.totalPages)
        json.put("parsed_pages", job.parsedPages)

        if (job.questions != null) {
            json.put("questions", JSONObject(job.questions))
        }
        if (job.error != null) {
            json.put("error", job.error)
        }

        // 提示：当前为桩实现
        json.put("_note", "PDF 解析 Pipeline 尚未实现（Task #6）。当前返回模拟状态。")
        return json.toString()
    }

    /**
     * 单页 OCR 识别（桩实现）
     *
     * 真实实现将：
     * 1. 用 PdfRenderer 渲染指定页为 Bitmap
     * 2. 调用 ML Kit text-recognition-chinese 识别中文
     * 3. 返回识别文本
     */
    private fun ocrRecognize(args: JSONObject): String {
        val filePath = args.optString("file_path", "")
        if (filePath.isBlank()) return errorJson("file_path 必填")
        val pageNumber = args.optInt("page_number", -1)
        if (pageNumber <= 0) return errorJson("page_number 必填且必须大于 0")

        val json = JSONObject()
        json.put("file_path", filePath)
        json.put("page_number", pageNumber)
        json.put("text", "")
        json.put("_note", "OCR 识别未启用（Task #6 待实现）。后续将使用 ML Kit text-recognition-chinese 进行中文识别。")
        return json.toString()
    }

    private fun errorJson(msg: String): String {
        val escaped = msg.replace("\\", "\\\\").replace("\"", "\\\"")
        return """{"error":"$escaped"}"""
    }
}
