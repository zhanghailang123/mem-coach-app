package cn.com.memcoach.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import cn.com.memcoach.data.entity.AgentEventEntity

/**
 * Agent 事件 DAO
 */
@Dao
interface AgentEventDao {

    /** 插入 Agent 事件 */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(event: AgentEventEntity): Long

    /** 获取指定会话的所有事件 */
    @Query("""
        SELECT * FROM agent_events
        WHERE conversation_id = :conversationId
        ORDER BY created_at ASC
    """)
    suspend fun getByConversationId(conversationId: Long): List<AgentEventEntity>

    /** 获取指定会话的某类事件 */
    @Query("""
        SELECT * FROM agent_events
        WHERE conversation_id = :conversationId AND event_type = :eventType
        ORDER BY created_at ASC
    """)
    suspend fun getByConversationIdAndType(
        conversationId: Long,
        eventType: String
    ): List<AgentEventEntity>

    /** 获取指定会话中某个序号之后的事件，用于聊天框重开后的增量恢复 */
    @Query("""
        SELECT * FROM agent_events
        WHERE conversation_id = :conversationId AND seq > :afterSeq
        ORDER BY seq ASC, created_at ASC
    """)
    suspend fun getByConversationIdAfterSeq(
        conversationId: Long,
        afterSeq: Long
    ): List<AgentEventEntity>

    /** 删除指定会话的事件 */
    @Query("DELETE FROM agent_events WHERE conversation_id = :conversationId")
    suspend fun deleteByConversationId(conversationId: Long)
}
