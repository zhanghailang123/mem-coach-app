package cn.com.memcoach.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update
import cn.com.memcoach.data.entity.Vocabulary
import cn.com.memcoach.data.entity.VocabularyReview

@Dao
interface VocabularyDao {

    @Insert
    suspend fun insert(vocab: Vocabulary)

    @Update
    suspend fun update(vocab: Vocabulary)

    @Query("SELECT * FROM vocabulary WHERE id = :id")
    suspend fun getById(id: String): Vocabulary?

    @Query("SELECT * FROM vocabulary WHERE word = :word LIMIT 1")
    suspend fun getByWord(word: String): Vocabulary?

    @Query("SELECT * FROM vocabulary WHERE lower(word) = lower(:word) LIMIT 1")
    suspend fun getByWordIgnoreCase(word: String): Vocabulary?

    @Query("DELETE FROM vocabulary WHERE id = :id")
    suspend fun deleteById(id: String): Int

    /** 获取待复习单词（间隔重复算法） */
    @Query("""
        SELECT * FROM vocabulary
        WHERE next_review_at IS NOT NULL AND next_review_at <= :now
        ORDER BY next_review_at ASC
        LIMIT :limit
    """)
    suspend fun getDueForReview(now: Long, limit: Int = 20): List<Vocabulary>

    /** 按状态查询 */
    @Query("SELECT * FROM vocabulary WHERE status = :status ORDER BY updated_at DESC LIMIT :limit")
    suspend fun getByStatus(status: String, limit: Int = 100): List<Vocabulary>

    /** 搜索单词 */
    @Query("SELECT * FROM vocabulary WHERE word LIKE '%' || :query || '%' LIMIT :limit")
    suspend fun search(query: String, limit: Int = 50): List<Vocabulary>

    /** 获取所有标签 */
    @Query("SELECT DISTINCT tags FROM vocabulary WHERE tags IS NOT NULL")
    suspend fun getAllTags(): List<String>

    /** 统计 */
    @Query("SELECT COUNT(*) FROM vocabulary WHERE status = :status")
    suspend fun countByStatus(status: String): Int

    @Query("SELECT COUNT(*) FROM vocabulary")
    suspend fun countAll(): Int
}

@Dao
interface VocabularyReviewDao {

    @Insert
    suspend fun insert(review: VocabularyReview)

    @Query("SELECT * FROM vocabulary_reviews WHERE vocab_id = :vocabId ORDER BY created_at DESC")
    suspend fun getReviewHistory(vocabId: String): List<VocabularyReview>

    @Query("SELECT COUNT(*) FROM vocabulary_reviews WHERE created_at >= :since")
    suspend fun getReviewCount(since: Long): Int
}
