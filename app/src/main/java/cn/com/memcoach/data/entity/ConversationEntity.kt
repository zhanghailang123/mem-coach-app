package cn.com.memcoach.data.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * 会话实体
 *
 * 记录用户的聊天会话信息，支持会话列表和历史会话加载。
 * 每个会话包含多条聊天消息。
 */
@Entity(
    tableName = "conversations",
    indices = [
        Index("user_id"),
        Index("created_at"),
        Index("updated_at"),
        Index("agent_run_id"),
        Index("agent_status")
    ]
)
data class ConversationEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id")
    val id: Long = 0,

    @ColumnInfo(name = "user_id")
    val userId: String = "default",

    @ColumnInfo(name = "title")
    val title: String = "新对话",

    @ColumnInfo(name = "summary")
    val summary: String? = null,

    @ColumnInfo(name = "message_count")
    val messageCount: Int = 0,

    @ColumnInfo(name = "is_active")
    val isActive: Boolean = true,

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "updated_at")
    val updatedAt: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "agent_run_id")
    val agentRunId: String? = null,

    @ColumnInfo(name = "agent_status")
    val agentStatus: String? = null,

    @ColumnInfo(name = "agent_started_at")
    val agentStartedAt: Long? = null,

    @ColumnInfo(name = "agent_finished_at")
    val agentFinishedAt: Long? = null,

    @ColumnInfo(name = "agent_last_seq")
    val agentLastSeq: Long = 0,

    @ColumnInfo(name = "agent_error")
    val agentError: String? = null
) {
    companion object {
        const val AGENT_STATUS_RUNNING = "running"
        const val AGENT_STATUS_COMPLETED = "completed"
        const val AGENT_STATUS_ERROR = "error"
        const val AGENT_STATUS_CANCELLED = "cancelled"
        const val AGENT_STATUS_INTERRUPTED = "interrupted"
    }
}
