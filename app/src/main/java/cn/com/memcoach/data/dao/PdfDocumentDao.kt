package cn.com.memcoach.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import cn.com.memcoach.data.entity.PdfDocument

/**
 * PDF 文档数据访问对象
 *
 * 管理导入的 PDF 文件元数据，支持文件列表查询、去重和清理。
 */
@Dao
interface PdfDocumentDao {

    /** 插入 PDF 文档记录 */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(document: PdfDocument)

    /** 批量插入 */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(documents: List<PdfDocument>)

    /** 获取所有 PDF 文档，按导入时间降序 */
    @Query("SELECT * FROM pdf_documents ORDER BY import_time DESC")
    suspend fun getAll(): List<PdfDocument>

    /** 按 ID 查询 */
    @Query("SELECT * FROM pdf_documents WHERE id = :id")
    suspend fun getById(id: String): PdfDocument?

    /** 按文件名查询 */
    @Query("SELECT * FROM pdf_documents WHERE file_name = :fileName")
    suspend fun getByFileName(fileName: String): PdfDocument?

    /** 按 SHA256 查询，用于去重 */
    @Query("SELECT * FROM pdf_documents WHERE sha256 = :sha256")
    suspend fun getBySha256(sha256: String): PdfDocument?

    /** 按科目筛选 */
    @Query("SELECT * FROM pdf_documents WHERE subject = :subject ORDER BY import_time DESC")
    suspend fun getBySubject(subject: String): List<PdfDocument>

    /** 按年份筛选 */
    @Query("SELECT * FROM pdf_documents WHERE year = :year ORDER BY import_time DESC")
    suspend fun getByYear(year: Int): List<PdfDocument>

    /** 删除指定 ID 的文档记录 */
    @Query("DELETE FROM pdf_documents WHERE id = :id")
    suspend fun deleteById(id: String)

    /** 删除所有文档记录 */
    @Query("DELETE FROM pdf_documents")
    suspend fun deleteAll()

    /** 统计文档数量 */
    @Query("SELECT COUNT(*) FROM pdf_documents")
    suspend fun count(): Int
}