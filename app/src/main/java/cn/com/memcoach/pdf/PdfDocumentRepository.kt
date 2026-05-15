package cn.com.memcoach.pdf

import android.content.Context
import android.database.Cursor
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import cn.com.memcoach.data.dao.PdfDocumentDao
import cn.com.memcoach.data.entity.PdfDocument
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.security.MessageDigest
import java.util.UUID

/**
 * PDF 文档仓库
 *
 * 负责将 PDF 文件导入 App 私有目录，并通过 Room DAO 持久化元数据。
 * 文件存储在 filesDir/pdf_documents/ 目录下。
 */
class PdfDocumentRepository(
    private val context: Context,
    private val pdfDocumentDao: PdfDocumentDao
) {
    private val documentsDir: File by lazy { File(context.filesDir, "pdf_documents").apply { mkdirs() } }

    /**
     * 导入 PDF 文件到私有目录
     *
     * @param source 源文件路径（支持 content://、file:// 或普通路径）
     * @param subject 科目（可选）
     * @param year 年份（可选）
     * @return 导入的文档记录
     */
    suspend fun importPdf(source: String, subject: String? = null, year: Int? = null): PdfDocument {
        return withContext(Dispatchers.IO) {
            val displayName = resolveDisplayName(source).ifBlank { "document_${System.currentTimeMillis()}.pdf" }
            val id = "pdf_${UUID.randomUUID().toString().replace("-", "")}"
            val target = File(documentsDir, "${id}_${sanitizeFileName(displayName)}")

            copySourceToFile(source, target)
            val checksum = sha256(target)

            // 检查是否已存在相同哈希的文件
            val existing = pdfDocumentDao.getBySha256(checksum)
            if (existing != null) {
                target.delete()
                return@withContext existing
            }

            val document = PdfDocument(
                id = id,
                fileName = displayName,
                localPath = target.absolutePath,
                fileSize = target.length(),
                pageCount = getPageCount(target),
                subject = subject?.takeIf { it.isNotBlank() },
                year = year?.takeIf { it > 0 },
                sha256 = checksum
            )

            pdfDocumentDao.insert(document)
            document
        }
    }

    /**
     * 获取所有已导入的 PDF 文档
     */
    suspend fun listDocuments(): List<PdfDocument> {
        return withContext(Dispatchers.IO) {
            pdfDocumentDao.getAll().filter { File(it.localPath).exists() }
        }
    }

    /**
     * 按 ID 或路径获取文档
     */
    suspend fun getDocument(idOrPath: String): PdfDocument? {
        return withContext(Dispatchers.IO) {
            val key = idOrPath.trim()
            if (key.isBlank()) return@withContext null

            // 先尝试按 ID 查询
            val byId = pdfDocumentDao.getById(key)
            if (byId != null && File(byId.localPath).exists()) return@withContext byId

            // 再尝试按路径查询
            val byPath = pdfDocumentDao.getAll().firstOrNull { it.localPath == key }
            if (byPath != null && File(byPath.localPath).exists()) return@withContext byPath

            // 最后尝试直接打开文件
            val file = File(key)
            if (file.exists() && file.extension.equals("pdf", ignoreCase = true)) {
                val document = PdfDocument(
                    id = key,
                    fileName = file.name,
                    localPath = file.absolutePath,
                    fileSize = file.length(),
                    pageCount = getPageCount(file),
                    sha256 = sha256(file)
                )
                // 注意：这里不自动导入，只是返回临时记录
                return@withContext document
            }

            null
        }
    }

    /**
     * 删除文档记录并物理删除文件
     */
    suspend fun deleteDocument(id: String) {
        withContext(Dispatchers.IO) {
            val document = pdfDocumentDao.getById(id)
            if (document != null) {
                val file = File(document.localPath)
                if (file.exists()) {
                    file.delete()
                }
                pdfDocumentDao.deleteById(id)
            }
        }
    }

    private fun copySourceToFile(source: String, target: File) {
        val trimmed = source.trim()
        if (trimmed.startsWith("content://", ignoreCase = true)) {
            context.contentResolver.openInputStream(Uri.parse(trimmed)).use { input ->
                requireNotNull(input) { "Unable to open PDF URI" }
                target.outputStream().use { output -> input.copyTo(output) }
            }
        } else {
            val file = if (trimmed.startsWith("file://", ignoreCase = true)) File(Uri.parse(trimmed).path.orEmpty()) else File(trimmed)
            require(file.exists()) { "PDF file does not exist: $source" }
            file.inputStream().use { input -> target.outputStream().use { output -> input.copyTo(output) } }
        }
    }

    private fun resolveDisplayName(source: String): String {
        val trimmed = source.trim()
        if (trimmed.startsWith("content://", ignoreCase = true)) {
            var cursor: Cursor? = null
            return try {
                cursor = context.contentResolver.query(Uri.parse(trimmed), null, null, null, null)
                val nameIndex = cursor?.getColumnIndex(OpenableColumns.DISPLAY_NAME) ?: -1
                if (cursor != null && cursor.moveToFirst() && nameIndex >= 0) cursor.getString(nameIndex) else ""
            } finally {
                cursor?.close()
            }
        }
        return if (trimmed.startsWith("file://", ignoreCase = true)) File(Uri.parse(trimmed).path.orEmpty()).name else File(trimmed).name
    }

    private fun sanitizeFileName(name: String): String = name.substringAfterLast('/').substringAfterLast('\\')
        .replace(Regex("[^A-Za-z0-9._-]"), "_")
        .ifBlank { "document.pdf" }

    private fun getPageCount(file: File): Int {
        val descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
        return try { PdfRenderer(descriptor).use { it.pageCount } } finally { descriptor.close() }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val read = input.read(buffer)
                if (read <= 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}

/**
 * 扩展函数：将 PdfDocument 转换为 Map，方便 Bridge 传输
 */
fun PdfDocument.toMap(): Map<String, Any?> = mapOf(
    "id" to id,
    "file_name" to fileName,
    "local_path" to localPath,
    "file_size" to fileSize,
    "page_count" to pageCount,
    "subject" to subject,
    "year" to year,
    "sha256" to sha256,
    "import_time" to importTime
)