package cn.com.memcoach.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import cn.com.memcoach.data.entity.ConversationEntity

/**
 * 会话数据访问对象
 *
 * 提供会话的增删改查操作，支持会话列表查询和分页加载。
 */
@Dao
interface ConversationDao {

    /** 插入新会话，返回自增 ID */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(conversation: ConversationEntity): Long

    /** 更新会话信息 */
    @Update
    suspend fun update(conversation: ConversationEntity)

    /** 根据 ID 获取会话 */
    @Query("SELECT * FROM conversations WHERE id = :id")
    suspend fun getById(id: Long): ConversationEntity?

    /** 获取用户的所有会话，按更新时间倒序 */
    @Query("""
        SELECT * FROM conversations 
        WHERE user_id = :userId AND is_active = 1 
        ORDER BY updated_at DESC
    """)
    suspend fun getAllByUser(userId: String = "default"): List<ConversationEntity>

    /** 分页获取用户会话 */
    @Query("""
        SELECT * FROM conversations 
        WHERE user_id = :userId AND is_active = 1 
        ORDER BY updated_at DESC 
        LIMIT :limit OFFSET :offset
    """)
    suspend fun getByUserPaginated(
        userId: String = "default",
        limit: Int = 20,
        offset: Int = 0
    ): List<ConversationEntity>

    /** 获取用户会话总数 */
    @Query("SELECT COUNT(*) FROM conversations WHERE user_id = :userId AND is_active = 1")
    suspend fun getCountByUser(userId: String = "default"): Int

    /** 更新会话的最后更新时间 */
    @Query("UPDATE conversations SET updated_at = :updatedAt WHERE id = :id")
    suspend fun updateTimestamp(id: Long, updatedAt: Long = System.currentTimeMillis())

    /** 更新会话的消息数量 */
    @Query("UPDATE conversations SET message_count = :count WHERE id = :id")
    suspend fun updateMessageCount(id: Long, count: Int)

    /** 更新会话标题 */
    @Query("UPDATE conversations SET title = :title WHERE id = :id")
    suspend fun updateTitle(id: Long, title: String)

    /** 更新会话摘要 */
    @Query("UPDATE conversations SET summary = :summary WHERE id = :id")
    suspend fun updateSummary(id: Long, summary: String?)

    /** 软删除会话（标记为非活跃） */
    @Query("UPDATE conversations SET is_active = 0 WHERE id = :id")
    suspend fun softDelete(id: Long)

    /** 硬删除会话及其所有消息 */
    @Query("DELETE FROM conversations WHERE id = :id")
    suspend fun delete(id: Long)

    /** 删除用户的所有会话 */
    @Query("DELETE FROM conversations WHERE user_id = :userId")
    suspend fun deleteAllByUser(userId: String)
}