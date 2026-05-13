package cn.com.memcoach.data.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index

/**
 * 用户知识掌握度实体
 *
 * 记录用户对每个知识点的掌握程度，并支持间隔重复算法的复习排期。
 * 通过 SM-2 简化算法计算 nextReviewDate。
 */
@Entity(
    tableName = "user_mastery",
    primaryKeys = ["user_id", "knowledge_id"],
    foreignKeys = [
        ForeignKey(
            entity = KnowledgeNode::class,
            parentColumns = ["id"],
            childColumns = ["knowledge_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index("user_id"),
        Index("knowledge_id"),
        Index("next_review_date")
    ]
)
data class UserMastery(
    @ColumnInfo(name = "user_id")
    val userId: String = "default",    // 默认单用户为 "default"

    @ColumnInfo(name = "knowledge_id")
    val knowledgeId: String,            // 知识点ID（外键）

    @ColumnInfo(name = "mastery_level")
    val masteryLevel: Float = 0.0f,     // 掌握程度 0.0 ~ 1.0

    @ColumnInfo(name = "review_count")
    val reviewCount: Int = 0,           // 总复习次数

    @ColumnInfo(name = "correct_count")
    val correctCount: Int = 0,          // 回答正确次数

    @ColumnInfo(name = "ease_factor")
    val easeFactor: Float = 2.5f,       // SM-2 难度因子（初始值 2.5）

    @ColumnInfo(name = "interval_days")
    val intervalDays: Int = 0,          // SM-2 当前复习间隔（天）

    @ColumnInfo(name = "last_review_date")
    val lastReviewDate: Long = 0L,      // 上次复习时间戳

    @ColumnInfo(name = "next_review_date")
    val nextReviewDate: Long = 0L,      // 下次复习时间戳（SM-2 算法计算）

    @ColumnInfo(name = "updated_at")
    val updatedAt: Long = System.currentTimeMillis()
) {
    companion object {
        /** 判断该知识点今天是否该复习 */
        fun isDueForReview(mastery: UserMastery, now: Long = System.currentTimeMillis()): Boolean {
            return mastery.nextReviewDate <= now
        }

        /** 根据掌握度等级返回标签 */
        fun getLevelLabel(level: Float): String = when {
            level >= 0.8f -> "🟢 已掌握"
            level >= 0.4f -> "🟡 学习中"
            else -> "🔴 薄弱"
        }
    }
}
