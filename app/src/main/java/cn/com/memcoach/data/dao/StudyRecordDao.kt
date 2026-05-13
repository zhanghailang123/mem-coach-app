package cn.com.memcoach.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import cn.com.memcoach.data.entity.StudyRecord

/**
 * 学习记录数据访问对象
 *
 * 记录用户每次做题的详细信息，支持按时间、科目、学习模式等维度统计分析。
 */
@Dao
interface StudyRecordDao {

    /** 插入单条学习记录 */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(record: StudyRecord): Long

    /** 批量插入学习记录 */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(records: List<StudyRecord>)

    /** 按日期范围获取学习记录 */
    @Query("""
        SELECT * FROM study_records 
        WHERE user_id = :userId 
          AND created_at >= :startTime 
          AND created_at < :endTime
        ORDER BY created_at DESC
    """)
    suspend fun getByDateRange(
        userId: String = "default",
        startTime: Long,
        endTime: Long
    ): List<StudyRecord>

    /** 获取指定时间段内的做题总数 */
    @Query("""
        SELECT COUNT(*) FROM study_records 
        WHERE user_id = :userId AND created_at >= :startTime
    """)
    suspend fun getTotalCountSince(userId: String = "default", startTime: Long): Int

    /** 获取指定时间段内的正确题数 */
    @Query("""
        SELECT COUNT(*) FROM study_records 
        WHERE user_id = :userId 
          AND is_correct = 1 
          AND created_at >= :startTime
    """)
    suspend fun getCorrectCountSince(userId: String = "default", startTime: Long): Int

    /** 获取某道题的所有学习记录 */
    @Query("SELECT * FROM study_records WHERE user_id = :userId AND question_id = :questionId ORDER BY created_at DESC")
    suspend fun getByQuestionId(userId: String = "default", questionId: String): List<StudyRecord>

    /** 获取某知识点的所有学习记录 */
    @Query("SELECT * FROM study_records WHERE user_id = :userId AND knowledge_id = :knowledgeId ORDER BY created_at DESC")
    suspend fun getByKnowledgeId(userId: String = "default", knowledgeId: String): List<StudyRecord>

    /** 获取某道题的最新学习记录 */
    @Query("SELECT * FROM study_records WHERE user_id = :userId AND question_id = :questionId ORDER BY created_at DESC LIMIT 1")
    suspend fun getLatestByQuestionId(userId: String = "default", questionId: String): StudyRecord?

    /** 按学习模式统计数量 */
    @Query("""
        SELECT study_mode, COUNT(*) as count 
        FROM study_records 
        WHERE user_id = :userId AND created_at >= :startTime
        GROUP BY study_mode
    """)
    suspend fun getCountByMode(userId: String = "default", startTime: Long): List<Map<String, Any>>

    /** 获取最近 N 天的每日学习记录数（用于热力图） */
    @Query("""
        SELECT DATE(created_at / 1000, 'unixepoch') as date, COUNT(*) as count
        FROM study_records 
        WHERE user_id = :userId AND created_at >= :startTime
        GROUP BY date
        ORDER BY date ASC
    """)
    suspend fun getDailyCountSince(userId: String = "default", startTime: Long): List<Map<String, Any>>

    /** 获取最近 N 天的每日正确率趋势 */
    @Query("""
        SELECT 
            DATE(created_at / 1000, 'unixepoch') as date, 
            COUNT(*) as total,
            SUM(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END) as correct
        FROM study_records 
        WHERE user_id = :userId AND created_at >= :startTime
        GROUP BY date
        ORDER BY date ASC
    """)
    suspend fun getDailyAccuracySince(userId: String = "default", startTime: Long): List<Map<String, Any>>

    /** 获取连续学习天数 */
    @Query("""
        SELECT DISTINCT DATE(created_at / 1000, 'unixepoch') as date
        FROM study_records 
        WHERE user_id = :userId
        ORDER BY date DESC
    """)
    suspend fun getDistinctStudyDates(userId: String = "default"): List<String>

    /** 获取用户总学习时间（秒） */
    @Query("SELECT SUM(time_spent_seconds) FROM study_records WHERE user_id = :userId")
    suspend fun getTotalTimeSpent(userId: String = "default"): Int?

    /** 获取某时间段的平均答题时间 */
    @Query("""
        SELECT AVG(time_spent_seconds) FROM study_records 
        WHERE user_id = :userId AND created_at >= :startTime
    """)
    suspend fun getAverageTimeSpentSince(userId: String = "default", startTime: Long): Float?

    /** 删除所有学习记录 */
    @Query("DELETE FROM study_records WHERE user_id = :userId")
    suspend fun deleteByUser(userId: String)
}
