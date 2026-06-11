package cn.com.memcoach.data.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * 答题记录
 */
@Entity(tableName = "answer_records")
data class AnswerRecord(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,

    @ColumnInfo(name = "question_id")
    val questionId: String,

    @ColumnInfo(name = "user_answer")
    val userAnswer: String,

    @ColumnInfo(name = "correct_answer")
    val correctAnswer: String,

    @ColumnInfo(name = "is_correct")
    val isCorrect: Boolean,

    @ColumnInfo(name = "time_spent")
    val timeSpent: Int = 0, // 秒

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis()
)

/**
 * 错题统计（聚合视图）
 */
data class WrongQuestion(
    val questionId: String,
    val totalAttempts: Int,
    val wrongCount: Int,
    val correctCount: Int,
    val lastAttemptAt: Long,
    val isMastered: Boolean // 连续2次正确视为掌握
)
