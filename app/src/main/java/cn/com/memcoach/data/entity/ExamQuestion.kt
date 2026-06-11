package cn.com.memcoach.data.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * 真题题目实体
 *
 * 存储从PDF识别并结构化后的真题数据。
 * options 和 knowledge_tags 以JSON字符串存储，
 * embedding 以ByteArray存储向量数据。
 */
@Entity(
    tableName = "exam_questions",
    indices = [
        Index(value = ["stem_hash"]),
        Index(value = ["parse_status"]),
        Index(value = ["section"]),
        Index(value = ["question_number"]),
        Index(value = ["merge_status"]),
        Index(value = ["source_document_id"])

    ]
)
data class ExamQuestion(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,                    // math_2023_1, logic_2023_5

    @ColumnInfo(name = "year")
    val year: Int,                     // 2023

    @ColumnInfo(name = "subject")
    val subject: String,               // management_comprehensive / english

    @ColumnInfo(name = "section")
    val section: String? = null,        // math / logic / writing / english

    @ColumnInfo(name = "question_number")
    val questionNumber: Int? = null,    // 真题题号，用于题干与答案解析合并

    @ColumnInfo(name = "chapter")
    val chapter: String?,              // formal_logic / analytical_logic / argument_logic

    @ColumnInfo(name = "topic")
    val topic: String?,                // conditional_inference / contrapositive

    @ColumnInfo(name = "type")
    val type: String,                  // choice / validity / essay / fill / sufficiency

    @ColumnInfo(name = "difficulty")
    val difficulty: String?,           // basic / medium / hard

    @ColumnInfo(name = "stem")
    val stem: String,                  // 题干文字

    @ColumnInfo(name = "options")
    val options: String?,              // JSON: {"A":"选项A","B":"选项B",...}

    @ColumnInfo(name = "answer")
    val answer: String?,               // 答案（选择题为字母，填空题为文字）

    @ColumnInfo(name = "explanation")
    val explanation: String?,          // 官方解析

    @ColumnInfo(name = "source_file")
    val sourceFile: String,            // 来源PDF文件名: "2023管综真题.pdf"

    @ColumnInfo(name = "source_document_id")
    val sourceDocumentId: String? = null, // 来源 PDF 文档 ID，用于按导入文件统一管理真题

    @ColumnInfo(name = "source_page")
    val sourcePage: Int,               // 来源页码


    @ColumnInfo(name = "knowledge_tags")
    val knowledgeTags: String?,        // JSON数组: ["条件推理","假言命题"]

    @ColumnInfo(name = "source_text")
    val sourceText: String? = null,    // 题目对应的原始 OCR/文本片段，便于追溯和校对

    @ColumnInfo(name = "source_page_type")
    val sourcePageType: String? = null, // question_page / answer_page / mixed_page / noise_page

    @ColumnInfo(name = "answer_source_text")
    val answerSourceText: String? = null, // 答案解析对应的原始 OCR/文本片段

    @ColumnInfo(name = "answer_source_page")
    val answerSourcePage: Int? = null,  // 答案解析来源页码

    @ColumnInfo(name = "merge_status")
    val mergeStatus: String = "question_only", // question_only / answer_only / merged / needs_review

    @ColumnInfo(name = "stem_hash")
    val stemHash: String? = null,      // 标准化题干哈希，用于稳定去重

    @ColumnInfo(name = "parse_confidence")
    val parseConfidence: Float = 0.5f, // LLM/OCR 结构化置信度，0-1

    @ColumnInfo(name = "parse_status")
    val parseStatus: String = "parsed", // parsed / needs_review / invalid

    @ColumnInfo(name = "parse_notes")
    val parseNotes: String? = null,    // 低置信度或校验失败原因

    @ColumnInfo(name = "exam_frequency")
    val examFrequency: Int = 0,        // 近10年考频

    @ColumnInfo(name = "embedding")
    val embedding: ByteArray? = null,  // 向量数据

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "updated_at")
    val updatedAt: Long = System.currentTimeMillis()
)
