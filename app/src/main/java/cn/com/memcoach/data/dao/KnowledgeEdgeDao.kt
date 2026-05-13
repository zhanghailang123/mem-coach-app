package cn.com.memcoach.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import cn.com.memcoach.data.entity.KnowledgeEdge

/**
 * 知识图谱关系边 DAO。
 *
 * 用于查询先修、相关、应用等跨知识点关系，补足 KnowledgeNode.parentId 只能表达树状层级的问题。
 */
@Dao
interface KnowledgeEdgeDao {

    /** 获取从某个知识点出发的关系边 */
    @Query("SELECT * FROM knowledge_edges WHERE from_id = :nodeId ORDER BY strength DESC")
    suspend fun getOutgoing(nodeId: String): List<KnowledgeEdge>

    /** 获取指向某个知识点的关系边 */
    @Query("SELECT * FROM knowledge_edges WHERE to_id = :nodeId ORDER BY strength DESC")
    suspend fun getIncoming(nodeId: String): List<KnowledgeEdge>

    /** 按关系类型获取出边 */
    @Query("SELECT * FROM knowledge_edges WHERE from_id = :nodeId AND type = :type ORDER BY strength DESC")
    suspend fun getOutgoingByType(nodeId: String, type: String): List<KnowledgeEdge>

    /** 获取某节点周边全部关系边 */
    @Query("""
        SELECT * FROM knowledge_edges
        WHERE from_id = :nodeId OR to_id = :nodeId
        ORDER BY strength DESC
    """)
    suspend fun getNeighborhood(nodeId: String): List<KnowledgeEdge>

    /** 插入或更新一条关系边 */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(edge: KnowledgeEdge)

    /** 批量插入或更新关系边 */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(edges: List<KnowledgeEdge>)

    /** 删除某节点相关的全部关系边 */
    @Query("DELETE FROM knowledge_edges WHERE from_id = :nodeId OR to_id = :nodeId")
    suspend fun deleteByNode(nodeId: String)
}
