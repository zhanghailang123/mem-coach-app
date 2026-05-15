package cn.com.memcoach.pipeline

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import java.io.File

/**
 * PDF OCR 工具类 —— 封装 Android PdfRenderer + ML Kit 中文 OCR。
 *
 * 功能：
 * - 将 PDF 指定页渲染为 Bitmap
 * - 对 Bitmap 进行 ML Kit 中文文字识别
 * - 支持逐页识别和整文档识别
 *
 * 借鉴：OpenOmniBot 的 ML Kit OCR 集成方案（OcrUtil），
 * 复用 text-recognition-chinese 的中文识别模型。
 *
 * @param context Android Context（用于初始化 ML Kit）
 */
class PdfOcrUtil(private val context: Context) {

    companion object {
        private const val TAG = "PdfOcrUtil"
        private const val DEFAULT_TARGET_WIDTH = 1800
    }

    /** ML Kit 中文文字识别器（线程安全，延迟初始化） */
    private val recognizer by lazy {
        TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
    }

    /**
     * 渲染 PDF 指定页码为 Bitmap。
     *
     * @param pdfFile PDF 文件
     * @param pageIndex 页码索引（从 0 开始）
     * @param targetWidth 目标宽度（像素），0 表示原始尺寸
     * @param targetHeight 目标高度（像素），0 表示原始尺寸
     * @return 渲染后的 Bitmap，使用完毕后需调用者 recycle()
     */
    fun renderPage(
        pdfFile: File,
        pageIndex: Int,
        targetWidth: Int = 0,
        targetHeight: Int = 0
    ): Bitmap {
        val fileDescriptor = ParcelFileDescriptor.open(pdfFile, ParcelFileDescriptor.MODE_READ_ONLY)
        val renderer = PdfRenderer(fileDescriptor)

        try {
            val page = renderer.openPage(pageIndex)

            // 计算渲染尺寸：OCR 默认使用更高宽度，提升小字号、选项和标点识别稳定性。
            val width = if (targetWidth > 0) targetWidth else maxOf(page.width, DEFAULT_TARGET_WIDTH)
            val height = if (targetHeight > 0) targetHeight else ((width.toFloat() / page.width) * page.height).toInt()

            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            Canvas(bitmap).drawColor(Color.WHITE)
            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)

            page.close()
            return bitmap
        } finally {
            renderer.close()
            fileDescriptor.close()
        }
    }

    /**
     * 获取 PDF 总页数。
     */
    fun getPageCount(pdfFile: File): Int {
        val fileDescriptor = ParcelFileDescriptor.open(pdfFile, ParcelFileDescriptor.MODE_READ_ONLY)
        val renderer = PdfRenderer(fileDescriptor)
        return try {
            renderer.pageCount
        } finally {
            renderer.close()
            fileDescriptor.close()
        }
    }

    /**
     * 对 Bitmap 进行中文 OCR 识别。
     *
     * @param bitmap 待识别的图片
     * @return 识别的文本字符串
     */
    suspend fun recognizeText(bitmap: Bitmap): String {
        val image = InputImage.fromBitmap(bitmap, 0)
        val result = recognizer.process(image).await()
        return cleanRecognizedText(result.text)
    }

    fun cleanRecognizedText(text: String): String {
        if (text.isBlank()) return ""
        return text
            .replace('\u00A0', ' ')
            .replace(Regex("[\\t\\x0B\\f\\r]+"), " ")
            .lines()
            .map { it.trim() }
            .filter { line ->
                line.isNotBlank() &&
                    !line.matches(Regex("""^[-—_ ]*$""")) &&
                    !line.matches(Regex("""^第?\s*\d+\s*[页頁]$""")) &&
                    !line.matches(Regex("""^\d+\s*/\s*\d+$"""))
            }
            .joinToString("\n")
            .replace(Regex("[ ]{2,}"), " ")
            .replace(Regex("\n{3,}"), "\n\n")
            .trim()
    }

    /**
     * 对 PDF 整文档进行 OCR 识别。
     *
     * @param pdfFile PDF 文件
     * @param onProgress 进度回调 (currentPage, totalPages)
     * @return 整文档的 OCR 文本（页间用换行分隔）
     */
    suspend fun recognizeEntireDocument(
        pdfFile: File,
        onProgress: ((Int, Int) -> Unit)? = null
    ): String {
        val totalPages = getPageCount(pdfFile)
        val sb = StringBuilder()

        for (i in 0 until totalPages) {
            onProgress?.invoke(i + 1, totalPages)

            val bitmap = renderPage(pdfFile, i)
            try {
                val text = recognizeText(bitmap)
                sb.appendLine("=== 第 ${i + 1} 页 ===")
                sb.appendLine(text)
                sb.appendLine()
            } finally {
                bitmap.recycle()
            }
        }

        return sb.toString()
    }

    /**
     * 尝试用 PdfRenderer 提取文字（非 OCR，直接提取 PDF 内嵌文本）。
     *
     * 注意：PdfRenderer 本身不支持文本提取。如果 PDF 包含内嵌文本，
     * 在 Android 上通常需要通过其他方式（如 iText 或 PDFBox 等第三方库）
     * 或者在服务器端用 pdftotext 提取。
     *
     * 当前方法返回空字符串，由调用方决定回退到 OCR。
     *
     * @return 提取的文本，如果 PDF 不含内嵌文本则返回空字符串
     */
    fun tryExtractEmbeddedText(pdfFile: File): String {
        // Android PdfRenderer 不提供文本提取 API。
        // 可选方案：
        // 1. 服务器端 pdftotext 提取
        // 2. 集成 Apache PDFBox (Android port)
        // 3. 直接使用 OCR（当前方案）
        return ""
    }

    /**
     * 判断 PDF 是否可能包含内嵌文本（启发式方法）。
     *
     * 通过检查文件大小/页码比来判断：
     * - 扫描版 PDF 每页通常 200KB+
     * - 文字版 PDF 每页通常 < 100KB
     *
     * @return true 表示可能是文字版 PDF
     */
    fun isLikelyTextBased(pdfFile: File): Boolean {
        // 启发式判断暂不实现，默认走 OCR
        return false
    }

    /**
     * 释放 ML Kit 识别器资源。
     */
    fun close() {
        try {
            recognizer.close()
        } catch (_: Exception) {
            // 忽略关闭时的异常
        }
    }
}

/**
 * Google Task API 的协程扩展：等待 ML Kit 任务完成。
 */
private suspend fun <T> com.google.android.gms.tasks.Task<T>.await(): T {
    return com.google.android.gms.tasks.Tasks.await(this)
}
