package cn.com.memcoach.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import cn.com.memcoach.data.entity.AnswerRecord
import cn.com.memcoach.data.entity.WrongQuestion

@Dao
interface AnswerRecordDao {

    @Insert
    suspend fun insert(record: AnswerRecord)

    /** 获取错题本（只做错过且未掌握的题） */
    @Query("""
        SELECT
            question_id as questionId,
            COUNT(*) as totalAttempts,
            SUM(CASE WHEN is_correct = 0 THEN 1 ELSE 0 END) as wrongCount,
            SUM(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END) as correctCount,
            MAX(created_at) as lastAttemptAt,
            (SELECT COUNT(*) FROM (
                SELECT is_correct FROM answer_records ar2
                WHERE ar2.question_id = ar.question_id
                ORDER BY created_at DESC LIMIT 2
            ) WHERE is_correct = 1) = 2 as isMastered
        FROM answer_records ar
        GROUP BY question_id
        HAVING wrongCount > 0 AND isMastered = 0
        ORDER BY lastAttemptAt DESC
    """)
    suspend fun getWrongBook(): List<WrongQuestion>

    /** 获取某题的答题历史 */
    @Query("SELECT * FROM answer_records WHERE question_id = :questionId ORDER BY created_at DESC")
    suspend fun getRecordsByQuestion(questionId: String): List<AnswerRecord>

    /** 今日做题数 */
    @Query("SELECT COUNT(*) FROM answer_records WHERE created_at >= :todayStart")
    suspend fun getTodayCount(todayStart: Long): Int

    /** 今日正确率 */
    @Query("""
        SELECT CAST(SUM(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*)
        FROM answer_records WHERE created_at >= :todayStart
    """)
    suspend fun getTodayAccuracy(todayStart: Long): Float?
}
