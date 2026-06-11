package cn.com.memcoach.data.dao

import androidx.room.*
import cn.com.memcoach.data.entity.LearningInsight

@Dao
interface LearningInsightDao {

    @Insert
    suspend fun insert(insight: LearningInsight): Long

    @Update
    suspend fun update(insight: LearningInsight)

    @Query("SELECT * FROM learning_insights WHERE id = :id")
    suspend fun getById(id: Long): LearningInsight?

    @Query("SELECT * FROM learning_insights WHERE status = :status ORDER BY created_at DESC")
    suspend fun getByStatus(status: String): List<LearningInsight>

    @Query("SELECT * FROM learning_insights WHERE category = :category ORDER BY created_at DESC LIMIT :limit")
    suspend fun getByCategory(category: String, limit: Int = 20): List<LearningInsight>

    @Query("SELECT * FROM learning_insights WHERE status = 'confirmed' ORDER BY created_at DESC LIMIT :limit")
    suspend fun getConfirmed(limit: Int = 50): List<LearningInsight>

    @Query("UPDATE learning_insights SET status = :status, user_notes = :notes, updated_at = :updatedAt WHERE id = :id")
    suspend fun updateStatus(id: Long, status: String, notes: String?, updatedAt: Long = System.currentTimeMillis())

    @Delete
    suspend fun delete(insight: LearningInsight)
}
