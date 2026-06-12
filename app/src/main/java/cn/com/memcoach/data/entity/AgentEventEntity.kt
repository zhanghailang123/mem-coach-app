package cn.com.memcoach.data.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * Agent 事件实体
 *
 * 保存 Agent 运行过程中的 UI 事件，用于聊天框关闭后恢复工具/策略胶囊等过程状态。
 */
@Entity(
    tableName = "agent_events",
    foreignKeys = [
        ForeignKey(
            entity = ConversationEntity::class,
            parentColumns = ["id"],
            childColumns = ["conversation_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index("conversation_id"),
        Index("run_id"),
        Index("event_type"),
        Index("created_at"),
        Index("seq"),
        Index("entry_id")
    ]
)
data class AgentEventEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id")
    val id: Long = 0,

    @ColumnInfo(name = "conversation_id")
    val conversationId: Long,

    @ColumnInfo(name = "run_id")
    val runId: String,

    @ColumnInfo(name = "event_type")
    val eventType: String,

    @ColumnInfo(name = "payload_json")
    val payloadJson: String,

    @ColumnInfo(name = "seq")
    val seq: Long = 0,

    @ColumnInfo(name = "entry_id")
    val entryId: String? = null,

    @ColumnInfo(name = "round_index")
    val roundIndex: Int? = null,

    @ColumnInfo(name = "status")
    val status: String? = null,

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis()
)
