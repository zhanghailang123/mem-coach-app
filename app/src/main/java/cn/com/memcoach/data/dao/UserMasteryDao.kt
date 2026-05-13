package cn.com.memcoach.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import cn.com.memcoach.data.entity.UserMastery

/**
 * 用户掌握度数据访问对象
 *
 * 管理用户对每个知识点的掌握程度，支持 SM-2 间隔重复算法的复习排期查询。
 */
@Dao
interface UserMasteryDao {

    /** 获取用户对某个知识点的掌握度 */
    @Query("SELECT * FROM user_mastery WHERE user_id = :userId AND knowledge_id = :knowledgeId")
    suspend fun getByUserAndKnowledge(userId: String = "default", knowledgeId: String): UserMastery?

    /** 获取用户所有掌握度记录 */
    @Query("SELECT * FROM user_mastery WHERE user_id = :userId ORDER BY mastery_level ASC")
    suspend fun getAllByUser(userId: String = "default"): List<UserMastery>

    /** 获取用户最薄弱的 N 个知识点（按掌握度升序） */
    @Query("""
        SELECT um.* FROM user_mastery um
        INNER JOIN knowledge_nodes kn ON um.knowledge_id = kn.id
        WHERE um.user_id = :userId
        ORDER BY um.mastery_level ASC
        LIMIT :limit
    """)
    suspend fun getWeakest(userId: String = "default", limit: Int = 5): List<UserMastery>

    /** 获取用户按科目分组的最薄弱知识点 */
    @Query("""
        SELECT um.* FROM user_mastery um
        INNER JOIN knowledge_nodes kn ON um.knowledge_id = kn.id
        WHERE um.user_id = :userId AND kn.subject = :subject
        ORDER BY um.mastery_level ASC
        LIMIT :limit
    """)
    suspend fun getWeakestBySubject(userId: String = "default", subject: String, limit: Int = 5): List<UserMastery>

    /** 获取掌握度 >= 指定阈值的知识点数量 */
    @Query("SELECT COUNT(*) FROM user_mastery WHERE user_id = :userId AND mastery_level >= :threshold")
    suspend fun countMastered(userId: String = "default", threshold: Float = 0.8f): Int

    /** 获取总知识点数量 */
    @Query("SELECT COUNT(*) FROM user_mastery WHERE user_id = :userId")
    suspend fun countTotal(userId: String = "default"): Int

    /** 获取今天需要复习的知识点（SM-2 间隔重复） */
    @Query("""
        SELECT * FROM user_mastery 
        WHERE user_id = :userId 
          AND next_review_date <= :now
          AND next_review_date > 0
        ORDER BY mastery_level ASC
        LIMIT :limit
    """)
    suspend fun getDueForReview(userId: String = "default", now: Long = System.currentTimeMillis(), limit: Int = 20): List<UserMastery>

    /** 获取需要复习的数量 */
    @Query("""
        SELECT COUNT(*) FROM user_mastery 
        WHERE user_id = :userId 
          AND next_review_date <= :now 
          AND next_review_date > 0
    """)
    suspend fun countDueForReview(userId: String = "default", now: Long = System.currentTimeMillis()): Int

    /** 获取用户某科目的掌握度进度 */
    @Query("""
        SELECT 
            COUNT(*) as total,
            SUM(CASE WHEN mastery_level >= 0.8 THEN 1 ELSE 0 END) as mastered
        FROM user_mastery um
        INNER JOIN knowledge_nodes kn ON um.knowledge_id = kn.id
        WHERE um.user_id = :userId AND kn.subject = :subject
    """)
    suspend fun getProgressBySubject(userId: String = "default", subject: String): Map<String, Int>

    /** 插入或更新掌握度 */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(mastery: UserMastery)

    /** 批量插入或更新 */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(masteries: List<UserMastery>)

    /** 删除某用户的所有掌握度记录 */
    @Query("DELETE FROM user_mastery WHERE user_id = :userId")
    suspend fun deleteByUser(userId: String)
}
