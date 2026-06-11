package cn.com.memcoach.data.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * 学习洞察
 *
 * Agent 通过分析错题本、答题记录等数据，挖掘出用户的薄弱点、错误模式、有效策略等。
 */
@Entity(tableName = "learning_insights")
data class LearningInsight(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,

    val category: String,           // weak_point, mistake_pattern, strategy, progress
    val content: String,            // "条件充分性联合判断薄弱"
    val confidence: String,         // low, medium, high
    val evidence: String,           // JSON array: ["logic_2023_5", ...]
    val suggestion: String,         // "重点练习条件交叉类题目"

    val status: String = "pending", // pending, confirmed, rejected

    @ColumnInfo(name = "user_notes")
    val userNotes: String? = null,

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "updated_at")
    val updatedAt: Long = System.currentTimeMillis()
)
