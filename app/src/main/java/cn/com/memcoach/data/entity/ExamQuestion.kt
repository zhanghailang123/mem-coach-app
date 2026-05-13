package cn.com.memcoach.data.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * 真题题目实体
 *
 * 存储从PDF识别并结构化后的真题数据。
 * options 和 knowledge_tags 以JSON字符串存储，
 * embedding 以ByteArray存储向量数据。
 */
@Entity(tableName = "exam_questions")
data class ExamQuestion(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,                    // math_2023_1, logic_2023_5

    @ColumnInfo(name = "year")
    val year: Int,                     // 2023

    @ColumnInfo(name = "subject")
    val subject: String,               // math / logic / writing / english

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

    @ColumnInfo(name = "source_page")
    val sourcePage: Int,               // 来源页码

    @ColumnInfo(name = "knowledge_tags")
    val knowledgeTags: String?,        // JSON数组: ["条件推理","假言命题"]

    @ColumnInfo(name = "exam_frequency")
    val examFrequency: Int = 0,        // 近10年考频

    @ColumnInfo(name = "embedding")
    val embedding: ByteArray? = null,  // 向量数据

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "updated_at")
    val updatedAt: Long = System.currentTimeMillis()
)
