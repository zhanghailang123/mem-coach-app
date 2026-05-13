package cn.com.memcoach.data.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * 学习记录实体
 *
 * 记录用户每次做题的详细信息，用于追踪学习进度和分析薄弱点。
 * 每条记录关联一道真题和一种学习模式。
 */
@Entity(
    tableName = "study_records",
    foreignKeys = [
        ForeignKey(
            entity = ExamQuestion::class,
            parentColumns = ["id"],
            childColumns = ["question_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index("user_id"),
        Index("question_id"),
        Index("created_at")
    ]
)
data class StudyRecord(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id")
    val id: Long = 0,

    @ColumnInfo(name = "user_id")
    val userId: String = "default",

    @ColumnInfo(name = "question_id")
    val questionId: String,           // 题目ID（外键）

    @ColumnInfo(name = "user_answer")
    val userAnswer: String?,          // 用户答案（选择题为字母，填空题为文字）

    @ColumnInfo(name = "is_correct")
    val isCorrect: Boolean?,          // 是否正确（null表示未判断/跳过）

    @ColumnInfo(name = "time_spent_seconds")
    val timeSpentSeconds: Int = 0,    // 用户答题用时（秒）

    @ColumnInfo(name = "study_mode")
    val studyMode: String,            // practice / review / mock / memorize

    @ColumnInfo(name = "knowledge_id")
    val knowledgeId: String?,         // 关联的知识点ID（冗余字段，方便统计）

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis()
) {
    companion object {
        /** 练习模式 */
        const val MODE_PRACTICE = "practice"

        /** 复习模式 */
        const val MODE_REVIEW = "review"

        /** 模拟考试模式 */
        const val MODE_MOCK = "mock"

        /** 背诵模式 */
        const val MODE_MEMORIZE = "memorize"
    }
}
