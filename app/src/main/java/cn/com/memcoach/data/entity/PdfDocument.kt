package cn.com.memcoach.data.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * PDF 文档实体
 *
 * 记录导入到 App 私有目录的 PDF 文件元数据，用于文件管理和 LLM 引用。
 * 文件实际存储在 filesDir/pdf_documents/ 目录下。
 */
@Entity(tableName = "pdf_documents")
data class PdfDocument(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,                     // UUID

    @ColumnInfo(name = "file_name")
    val fileName: String,               // 原始文件名

    @ColumnInfo(name = "local_path")
    val localPath: String,              // 私有目录中的完整路径

    @ColumnInfo(name = "file_size")
    val fileSize: Long,                 // 文件大小（字节）

    @ColumnInfo(name = "page_count")
    val pageCount: Int,                 // PDF 页数

    @ColumnInfo(name = "subject")
    val subject: String? = null,        // 科目（可选）

    @ColumnInfo(name = "year")
    val year: Int? = null,              // 年份（可选）

    @ColumnInfo(name = "sha256")
    val sha256: String? = null,         // 文件哈希，用于去重

    @ColumnInfo(name = "import_time")
    val importTime: Long = System.currentTimeMillis()  // 导入时间戳
)