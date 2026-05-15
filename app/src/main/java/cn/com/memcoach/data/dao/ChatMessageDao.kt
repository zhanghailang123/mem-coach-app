package cn.com.memcoach.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import cn.com.memcoach.data.entity.ChatMessageEntity

/**
 * 聊天消息数据访问对象
 *
 * 提供聊天消息的增删改查操作，支持按会话查询、分页加载、流式更新等。
 */
@Dao
interface ChatMessageDao {

    /** 插入新消息，返回自增 ID */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(message: ChatMessageEntity): Long

    /** 批量插入消息 */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(messages: List<ChatMessageEntity>)

    /** 更新消息内容 */
    @Update
    suspend fun update(message: ChatMessageEntity)

    /** 根据 ID 获取消息 */
    @Query("SELECT * FROM chat_messages WHERE id = :id")
    suspend fun getById(id: Long): ChatMessageEntity?

    /** 获取会话的所有消息，按创建时间正序 */
    @Query("""
        SELECT * FROM chat_messages 
        WHERE conversation_id = :conversationId 
        ORDER BY created_at ASC
    """)
    suspend fun getByConversationId(conversationId: Long): List<ChatMessageEntity>

    /** 分页获取会话消息（用于历史消息加载） */
    @Query("""
        SELECT * FROM chat_messages 
        WHERE conversation_id = :conversationId 
        ORDER BY created_at DESC 
        LIMIT :limit OFFSET :offset
    """)
    suspend fun getByConversationIdPaginated(
        conversationId: Long,
        limit: Int = 50,
        offset: Int = 0
    ): List<ChatMessageEntity>

    /** 获取会话的最新 N 条消息（用于上下文构建） */
    @Query("""
        SELECT * FROM chat_messages 
        WHERE conversation_id = :conversationId 
        ORDER BY created_at DESC 
        LIMIT :limit
    """)
    suspend fun getLatestByConversationId(
        conversationId: Long,
        limit: Int = 20
    ): List<ChatMessageEntity>

    /** 获取会话的消息总数 */
    @Query("SELECT COUNT(*) FROM chat_messages WHERE conversation_id = :conversationId")
    suspend fun getCountByConversationId(conversationId: Long): Int

    /** 获取会话中用户消息的数量 */
    @Query("""
        SELECT COUNT(*) FROM chat_messages 
        WHERE conversation_id = :conversationId AND role = 'user'
    """)
    suspend fun getUserMessageCount(conversationId: Long): Int

    /** 更新消息的流式状态 */
    @Query("UPDATE chat_messages SET is_streaming = :isStreaming WHERE id = :id")
    suspend fun updateStreamingStatus(id: Long, isStreaming: Boolean)

    /** 更新消息内容（用于流式更新） */
    @Query("UPDATE chat_messages SET content = :content WHERE id = :id")
    suspend fun updateContent(id: Long, content: String)

    /** 更新工具调用状态 */
    @Query("""
        UPDATE chat_messages 
        SET tool_status = :status, tool_result = :result 
        WHERE id = :id
    """)
    suspend fun updateToolStatus(id: Long, status: String, result: String?)

    /** 更新深度思考内容 */
    @Query("""
        UPDATE chat_messages 
        SET thinking_content = :content, thinking_stage = :stage 
        WHERE id = :id
    """)
    suspend fun updateThinkingContent(id: Long, content: String, stage: Int?)

    /** 获取会话中最后一条助手消息 */
    @Query("""
        SELECT * FROM chat_messages 
        WHERE conversation_id = :conversationId AND role = 'assistant' 
        ORDER BY created_at DESC 
        LIMIT 1
    """)
    suspend fun getLastAssistantMessage(conversationId: Long): ChatMessageEntity?

    /** 获取会话中最后一条用户消息 */
    @Query("""
        SELECT * FROM chat_messages 
        WHERE conversation_id = :conversationId AND role = 'user' 
        ORDER BY created_at DESC 
        LIMIT 1
    """)
    suspend fun getLastUserMessage(conversationId: Long): ChatMessageEntity?

    /** 删除会话的所有消息 */
    @Query("DELETE FROM chat_messages WHERE conversation_id = :conversationId")
    suspend fun deleteByConversationId(conversationId: Long)

    /** 删除指定消息 */
    @Query("DELETE FROM chat_messages WHERE id = :id")
    suspend fun deleteById(id: Long)

    /** 获取会话的总 token 数量 */
    @Query("SELECT SUM(token_count) FROM chat_messages WHERE conversation_id = :conversationId")
    suspend fun getTotalTokenCount(conversationId: Long): Int?

    /** 搜索消息内容（用于记忆检索） */
    @Query("""
        SELECT * FROM chat_messages 
        WHERE conversation_id = :conversationId AND content LIKE '%' || :query || '%' 
        ORDER BY created_at DESC 
        LIMIT :limit
    """)
    suspend fun searchByContent(
        conversationId: Long,
        query: String,
        limit: Int = 10
    ): List<ChatMessageEntity>
}