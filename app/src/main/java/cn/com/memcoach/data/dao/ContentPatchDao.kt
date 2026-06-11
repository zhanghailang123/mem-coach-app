package cn.com.memcoach.data.dao

import androidx.room.*
import cn.com.memcoach.data.entity.ContentPatch

@Dao
interface ContentPatchDao {

    @Insert
    suspend fun insert(patch: ContentPatch): Long

    @Update
    suspend fun update(patch: ContentPatch)

    @Query("SELECT * FROM content_patches WHERE id = :id")
    suspend fun getById(id: Long): ContentPatch?

    @Query("SELECT * FROM content_patches WHERE status = :status ORDER BY created_at DESC")
    suspend fun getByStatus(status: String): List<ContentPatch>

    @Query("SELECT * FROM content_patches WHERE target_type = :type AND target_id = :id ORDER BY created_at DESC")
    suspend fun getByTarget(type: String, id: String): List<ContentPatch>

    @Query("SELECT * FROM content_patches ORDER BY created_at DESC LIMIT :limit")
    suspend fun getRecent(limit: Int = 50): List<ContentPatch>

    @Query("UPDATE content_patches SET status = :status, review_notes = :notes, updated_at = :updatedAt WHERE id = :id")
    suspend fun updateStatus(id: Long, status: String, notes: String?, updatedAt: Long = System.currentTimeMillis())

    @Delete
    suspend fun delete(patch: ContentPatch)
}
