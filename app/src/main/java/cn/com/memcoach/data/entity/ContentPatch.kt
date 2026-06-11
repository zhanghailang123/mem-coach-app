package cn.com.memcoach.data.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * 内容改进提案
 *
 * Agent 发现真题解析、单词讲解等内容需要优化时，生成提案供用户审核。
 */
@Entity(tableName = "content_patches")
data class ContentPatch(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,

    @ColumnInfo(name = "target_type")
    val targetType: String,         // question, vocabulary, knowledge

    @ColumnInfo(name = "target_id")
    val targetId: String,           // 如 "logic_2023_5"

    val operation: String,          // append, replace, clarify

    @ColumnInfo(name = "patch_content")
    val patchContent: String,       // 改进内容（Markdown）

    val reason: String,             // 改进理由

    @ColumnInfo(name = "risk_level")
    val riskLevel: String,          // low, medium, high

    val status: String = "pending", // pending, approved, rejected

    @ColumnInfo(name = "review_notes")
    val reviewNotes: String? = null,

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "updated_at")
    val updatedAt: Long = System.currentTimeMillis()
)
