package cn.com.memcoach.agent.tool.handlers

import cn.com.memcoach.agent.tool.ToolDefinition
import cn.com.memcoach.agent.tool.ToolHandler
import cn.com.memcoach.pdf.PdfDocumentRepository
import cn.com.memcoach.pdf.toMap
import cn.com.memcoach.pipeline.PdfPipelineService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.io.File

/**
 * PDF 处理工具处理器 —— 提供 PDF 上传、OCR 识别状态查询、结构化解析等工具。
 *
 * 覆盖工具：
 * - pdf_upload            —— 接收 PDF 文件路径，启动 OCR+结构化解析 Pipeline
 * - pdf_parse_status      —— 查询 PDF 解析进度 and 结果
 * - pdf_ocr_recognize     —— 对单页图片进行 OCR 识别（调试用）
 *
 * 借鉴：OpenOmniBot 的 PDF 处理逻辑。
 */
class PDFToolHandler(
    private val pipelineService: PdfPipelineService,
    private val pdfRepository: PdfDocumentRepository,
    private val scope: CoroutineScope
) : ToolHandler {

    override val toolNames = setOf(
        "pdf_upload",
        "pdf_list",
        "pdf_parse_status",
        "pdf_ocr_recognize",
        "pdf_query"
    )

    override suspend fun execute(toolName: String, arguments: String): String {
        return try {
            val args = JSONObject(arguments)
            when (toolName) {
                "pdf_upload" -> uploadPdf(args)
                "pdf_list" -> listPdfs()
                "pdf_parse_status" -> getParseStatus(args)
                "pdf_ocr_recognize" -> ocrRecognize(args)
                "pdf_query" -> queryPdf(args)
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
            name = "pdf_list",
            description = "列出已导入 App 私有目录的 PDF 文件。返回文件 ID、文件名、本地路径、页数、大小、科目和年份。对话中引用 PDF 时优先使用文件 ID，不要把整份 PDF 直接塞进上下文。",
            parameters = """
{
  "type": "object",
  "properties": {}
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
            description = "对 PDF 的指定页面进行 OCR 文字识别（调试和预览用）。返回该页的识别文本。可传 file_path 或 document_id。",
            parameters = """
{
  "type": "object",
  "properties": {
    "file_path": {
      "type": "string",
      "description": "PDF 文件路径"
    },
    "document_id": {
      "type": "string",
      "description": "已导入 PDF 的文档 ID"
    },
    "page_number": {
      "type": "integer",
      "description": "页码（从 1 开始）"
    }
  },
  "required": ["page_number"]
}
""".trimIndent()
        ),
        ToolDefinition(
            name = "pdf_query",
            description = "根据 document_id 查询已导入 PDF 的文本预览，用于回答用户基于 PDF 的问题。优先在用户消息包含 document_id 时调用。",
            parameters = """
{
  "type": "object",
  "properties": {
    "document_id": {
      "type": "string",
      "description": "已导入 PDF 的文档 ID，例如 pdf_xxx"
    },
    "question": {
      "type": "string",
      "description": "用户围绕该 PDF 提出的问题"
    },
    "max_pages": {
      "type": "integer",
      "description": "最多读取前几页，默认 3，建议 1-5"
    }
  },
  "required": ["document_id", "question"]
}
""".trimIndent()
        )
    )


    // ─── 工具实现 ───

    /**
     * 上传 PDF 并启动解析任务
     */
    private suspend fun uploadPdf(args: JSONObject): String {
        val filePath = args.optString("file_path", "")
        if (filePath.isBlank()) return errorJson("file_path 必填")
        val subject = args.optString("subject", "")
        if (subject.isBlank()) return errorJson("subject 必填")
        val year = args.optInt("year", -1)
        if (year <= 0) return errorJson("year 必填且必须大于 0")

        val document = pdfRepository.importPdf(filePath, subject, year)
        val file = File(document.localPath)
        if (!file.exists()) return errorJson("文件归档失败: ${document.localPath}")

        val jobId = "pdf_job_${System.currentTimeMillis()}"

        // 使用前台服务启动解析，防止被系统杀掉
        cn.com.memcoach.pipeline.PdfParsingForegroundService.start(
            context = cn.com.memcoach.MemCoachApplication.instance,
            filePath = document.localPath,
            subject = subject,
            year = year,
            jobId = jobId
        )

        val json = JSONObject()
        json.put("job_id", jobId)
        json.put("status", "pending")
        json.put("document_id", document.id)
        json.put("file_name", document.fileName)
        json.put("file_path", document.localPath)
        json.put("page_count", document.pageCount)
        json.put("subject", subject)
        json.put("year", year)
        json.put("message", "PDF 已导入私有目录并启动后台解析。后续对话请优先引用 document_id，不要直接传整份 PDF。")
        return json.toString()
    }

    private suspend fun listPdfs(): String {
        val array = org.json.JSONArray()
        pdfRepository.listDocuments().forEach { document ->
            array.put(JSONObject(document.toMap()))
        }
        val json = JSONObject()
        json.put("documents", array)
        json.put("count", array.length())
        return json.toString()
    }

    /**
     * 查询解析进度
     */
    private fun getParseStatus(args: JSONObject): String {
        val jobId = args.optString("job_id", "")
        if (jobId.isBlank()) return errorJson("job_id 必填")

        val statusJson = pipelineService.getJobStatus(jobId)
            ?: return errorJson("任务不存在或已过期: $jobId")

        return statusJson.toString()
    }

    /**
     * 单页 OCR 识别（桩实现）
     */
    private suspend fun ocrRecognize(args: JSONObject): String {
        val documentId = args.optString("document_id", "")
        val filePathArg = args.optString("file_path", "")
        val filePath = when {
            filePathArg.isNotBlank() -> filePathArg
            documentId.isNotBlank() -> pdfRepository.getDocument(documentId)?.localPath.orEmpty()
            else -> ""
        }
        if (filePath.isBlank()) return errorJson("file_path 或 document_id 必填")
        val pageNumber = args.optInt("page_number", -1)
        if (pageNumber <= 0) return errorJson("page_number 必填且必须大于 0")

        val json = JSONObject()
        json.put("document_id", documentId.takeIf { it.isNotBlank() })
        json.put("file_path", filePath)
        json.put("page_number", pageNumber)
        json.put("text", "")
        json.put("_note", "单页 OCR 识别接口暂未通过 Handler 直接暴露，请优先使用 pdf_query 获取文本预览，或使用 pdf_upload 启动完整 Pipeline。")
        return json.toString()
    }

    private suspend fun queryPdf(args: JSONObject): String {
        val documentId = args.optString("document_id", "")
        if (documentId.isBlank()) return errorJson("document_id 必填")
        val question = args.optString("question", "")
        if (question.isBlank()) return errorJson("question 必填")
        val maxPages = args.optInt("max_pages", 3).coerceIn(1, 5)

        val document = pdfRepository.getDocument(documentId)
            ?: return errorJson("未找到 PDF 文档: $documentId")
        val file = File(document.localPath)
        if (!file.exists()) return errorJson("PDF 文件不存在: ${document.localPath}")

        val text = pipelineService.extractTextPreview(file, maxPages)
        val json = JSONObject()
        json.put("document_id", document.id)
        json.put("file_name", document.fileName)
        json.put("page_count", document.pageCount)
        json.put("question", question)
        json.put("max_pages", maxPages)
        json.put("text", text)
        json.put("message", if (text.isBlank()) "未提取到 PDF 文本，请确认文档可读或等待解析完成。" else "已返回 PDF 文本预览，请基于 text 回答用户问题；如果依据不足，请明确说明。")
        return json.toString()
    }

    private fun errorJson(msg: String): String {

        val escaped = msg.replace("\\", "\\\\").replace("\"", "\\\"")
        return """{"error":"$escaped"}"""
    }
}
