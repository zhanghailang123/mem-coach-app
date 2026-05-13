package cn.com.memcoach.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import cn.com.memcoach.data.entity.KnowledgeNode

/**
 * 知识点数据访问对象
 *
 * 支持按科目/章节查询知识点树，以及知识图谱的展开遍历。
 */
@Dao
interface KnowledgeNodeDao {

    /** 按ID获取单个知识点 */
    @Query("SELECT * FROM knowledge_nodes WHERE id = :id")
    suspend fun getById(id: String): KnowledgeNode?

    /** 按科目获取所有知识点 */
    @Query("SELECT * FROM knowledge_nodes WHERE subject = :subject ORDER BY sort_weight ASC, exam_frequency DESC")
    suspend fun getBySubject(subject: String): List<KnowledgeNode>

    /** 按科目和章节获取 */
    @Query("SELECT * FROM knowledge_nodes WHERE subject = :subject AND chapter = :chapter ORDER BY sort_weight ASC")
    suspend fun getByChapter(subject: String, chapter: String): List<KnowledgeNode>

    /** 获取某节点的直接子节点 */
    @Query("SELECT * FROM knowledge_nodes WHERE parent_id = :parentId ORDER BY sort_weight ASC")
    suspend fun getChildren(parentId: String): List<KnowledgeNode>

    /** 获取某科目的根节点（无父节点的知识点） */
    @Query("SELECT * FROM knowledge_nodes WHERE subject = :subject AND parent_id IS NULL ORDER BY sort_weight ASC")
    suspend fun getRootNodes(subject: String): List<KnowledgeNode>

    /** 按名称搜索知识点 */
    @Query("SELECT * FROM knowledge_nodes WHERE name LIKE '%' || :keyword || '%' ORDER BY exam_frequency DESC LIMIT :limit")
    suspend fun searchByName(keyword: String, limit: Int = 10): List<KnowledgeNode>

    /** 获取考频最高的知识点 */
    @Query("SELECT * FROM knowledge_nodes WHERE subject = :subject ORDER BY exam_frequency DESC LIMIT :limit")
    suspend fun getTopFrequent(subject: String, limit: Int = 10): List<KnowledgeNode>

    /** 获取某科目的知识点总数 */
    @Query("SELECT COUNT(*) FROM knowledge_nodes WHERE subject = :subject")
    suspend fun countBySubject(subject: String): Int

    /** 插入单个知识点 */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(node: KnowledgeNode)

    /** 批量插入 */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(nodes: List<KnowledgeNode>)

    /** 删除知识点 */
    @Query("DELETE FROM knowledge_nodes WHERE id = :id")
    suspend fun deleteById(id: String)

    /** 按学习顺序权重升序获取下N个待学知识点 */
    @Query("""
        SELECT * FROM knowledge_nodes 
        WHERE id NOT IN (
            SELECT knowledge_id FROM user_mastery 
            WHERE mastery_level >= 0.8
        )
        ORDER BY sort_weight ASC 
        LIMIT :limit
    """)
    suspend fun getNextToLearn(limit: Int = 5): List<KnowledgeNode>
}
