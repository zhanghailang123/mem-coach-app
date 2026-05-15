package cn.com.memcoach.data.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * 聊天消息实体
 *
 * 记录单条聊天消息的详细信息，支持文本消息、工具调用、深度思考等类型。
 * 每条消息关联一个会话。
 */
@Entity(
    tableName = "chat_messages",
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
        Index("role"),
        Index("created_at")
    ]
)
data class ChatMessageEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id")
    val id: Long = 0,

    @ColumnInfo(name = "conversation_id")
    val conversationId: Long,

    @ColumnInfo(name = "role")
    val role: String,  // user, assistant, system, tool

    @ColumnInfo(name = "content")
    val content: String,

    @ColumnInfo(name = "tool_name")
    val toolName: String? = null,

    @ColumnInfo(name = "tool_result")
    val toolResult: String? = null,

    @ColumnInfo(name = "tool_status")
    val toolStatus: String? = null,  // running, success, error

    @ColumnInfo(name = "tool_call_id")
    val toolCallId: String? = null,

    @ColumnInfo(name = "tool_calls_json")
    val toolCallsJson: String? = null,

    @ColumnInfo(name = "thinking_content")

    val thinkingContent: String? = null,

    @ColumnInfo(name = "thinking_stage")
    val thinkingStage: Int? = null,  // 1-识别需求，2-规划任务，3-帮你规划任务，4-完成思考

    @ColumnInfo(name = "is_streaming")
    val isStreaming: Boolean = false,

    @ColumnInfo(name = "token_count")
    val tokenCount: Int = 0,

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis()
) {
    companion object {
        /** 用户消息 */
        const val ROLE_USER = "user"

        /** AI 助手消息 */
        const val ROLE_ASSISTANT = "assistant"

        /** 系统消息 */
        const val ROLE_SYSTEM = "system"

        /** 工具调用结果 */
        const val ROLE_TOOL = "tool"

        /** 工具状态：运行中 */
        const val TOOL_STATUS_RUNNING = "running"

        /** 工具状态：成功 */
        const val TOOL_STATUS_SUCCESS = "success"

        /** 工具状态：错误 */
        const val TOOL_STATUS_ERROR = "error"

        /** 思考阶段：识别需求 */
        const val THINKING_STAGE_IDENTIFY = 1

        /** 思考阶段：规划任务 */
        const val THINKING_STAGE_PLAN = 2

        /** 思考阶段：执行任务 */
        const val THINKING_STAGE_EXECUTE = 3

        /** 思考阶段：完成思考 */
        const val THINKING_STAGE_COMPLETE = 4
    }
}