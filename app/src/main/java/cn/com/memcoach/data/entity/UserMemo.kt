package cn.com.memcoach.data.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * 用户笔记
 *
 * Agent 为用户生成个性化学习笔记，如单词记忆技巧、易混概念对比等。
 */
@Entity(tableName = "user_memos")
data class UserMemo(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,

    val type: String,               // word, question, concept

    @ColumnInfo(name = "target_id")
    val targetId: String,           // 关联的ID

    val content: String,            // 笔记内容（Markdown）
    val tags: String,               // JSON array: ["易混词", "公式"]

    @ColumnInfo(name = "is_pinned")
    val isPinned: Boolean = false,

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "updated_at")
    val updatedAt: Long = System.currentTimeMillis()
)
