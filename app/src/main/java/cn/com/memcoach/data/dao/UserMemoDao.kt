package cn.com.memcoach.data.dao

import androidx.room.*
import cn.com.memcoach.data.entity.UserMemo

@Dao
interface UserMemoDao {

    @Insert
    suspend fun insert(memo: UserMemo): Long

    @Update
    suspend fun update(memo: UserMemo)

    @Query("SELECT * FROM user_memos WHERE id = :id")
    suspend fun getById(id: Long): UserMemo?

    @Query("SELECT * FROM user_memos WHERE type = :type AND target_id = :targetId ORDER BY created_at DESC")
    suspend fun getByTarget(type: String, targetId: String): List<UserMemo>

    @Query("SELECT * FROM user_memos WHERE type = :type ORDER BY created_at DESC LIMIT :limit")
    suspend fun getByType(type: String, limit: Int = 50): List<UserMemo>

    @Query("SELECT * FROM user_memos WHERE is_pinned = 1 ORDER BY created_at DESC")
    suspend fun getPinned(): List<UserMemo>

    @Query("SELECT * FROM user_memos ORDER BY created_at DESC LIMIT :limit")
    suspend fun getRecent(limit: Int = 50): List<UserMemo>

    @Query("UPDATE user_memos SET is_pinned = :pinned, updated_at = :updatedAt WHERE id = :id")
    suspend fun updatePinned(id: Long, pinned: Boolean, updatedAt: Long = System.currentTimeMillis())

    @Delete
    suspend fun delete(memo: UserMemo)
}
