package cn.com.memcoach.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import cn.com.memcoach.data.entity.ExamQuestion

/**
 * 真题数据访问对象
 *
 * 支持按年份、科目、知识点、题型、难度等多维度筛选，
 * 以及去重检测和批量插入。
 */
@Dao
interface ExamQuestionDao {

    /** 按ID获取单道题 */
    @Query("SELECT * FROM exam_questions WHERE id = :id")
    suspend fun getById(id: String): ExamQuestion?

    /** 按科目和知识点搜索（最常用） */
    @Query("""
        SELECT * FROM exam_questions 
        WHERE subject = :subject 
          AND (:topic IS NULL OR topic = :topic)
        ORDER BY year DESC, id ASC
        LIMIT :limit
    """)
    suspend fun searchByTopic(
        subject: String,
        topic: String? = null,
        limit: Int = 5
    ): List<ExamQuestion>

    /** 按年份和科目获取真题 */
    @Query("""
        SELECT * FROM exam_questions 
        WHERE year = :year AND subject = :subject
        ORDER BY id ASC
    """)
    suspend fun getByYearAndSubject(year: Int, subject: String): List<ExamQuestion>

    /** 多维搜索 */
    @Query("""
        SELECT * FROM exam_questions 
        WHERE (:subject IS NULL OR subject = :subject)
          AND (:chapter IS NULL OR chapter = :chapter)
          AND (:topic IS NULL OR topic = :topic)
          AND (:type IS NULL OR type = :type)
          AND (:difficulty IS NULL OR difficulty = :difficulty)
          AND (:year IS NULL OR year = :year)
        ORDER BY year DESC, id ASC
        LIMIT :limit
    """)
    suspend fun search(
        subject: String? = null,
        chapter: String? = null,
        topic: String? = null,
        type: String? = null,
        difficulty: String? = null,
        year: Int? = null,
        limit: Int = 20
    ): List<ExamQuestion>

    /** 获取某科目的所有知识点列表 */
    @Query("SELECT DISTINCT topic FROM exam_questions WHERE subject = :subject AND topic IS NOT NULL ORDER BY topic")
    suspend fun getTopics(subject: String): List<String>

    /** 获取某科目的所有章节列表 */
    @Query("SELECT DISTINCT chapter FROM exam_questions WHERE subject = :subject AND chapter IS NOT NULL ORDER BY chapter")
    suspend fun getChapters(subject: String): List<String>

    /** 获取某知识点下的题目数量 */
    @Query("SELECT COUNT(*) FROM exam_questions WHERE topic = :topic")
    suspend fun countByTopic(topic: String): Int

    /** 获取总题目数量 */
    @Query("SELECT COUNT(*) FROM exam_questions WHERE subject = :subject")
    suspend fun countBySubject(subject: String): Int

    /** 按ID列表批量获取 */
    @Query("SELECT * FROM exam_questions WHERE id IN (:ids)")
    suspend fun getByIds(ids: List<String>): List<ExamQuestion>

    /** 根据题干哈希检查是否已存在（去重） */
    @Query("SELECT COUNT(*) FROM exam_questions WHERE stem = :stem AND subject = :subject")
    suspend fun countByStemAndSubject(stem: String, subject: String): Int

    /** 插入单题 */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(question: ExamQuestion)

    /** 批量插入 */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(questions: List<ExamQuestion>)

    /** 删除单个题目 */
    @Query("DELETE FROM exam_questions WHERE id = :id")
    suspend fun deleteById(id: String)
}
