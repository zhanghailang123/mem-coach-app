package cn.com.memcoach.data.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index

/**
 * 知识点关系（边）实体
 *
 * 存储知识图谱中节点之间的有向边关系。
 * 关系类型包括：包含(PARENT)、前置(PREREQUISITE)、关联(RELATED)、应用(APPLIED_IN)
 */
@Entity(
    tableName = "knowledge_edges",
    primaryKeys = ["from_id", "to_id", "type"],
    foreignKeys = [
        ForeignKey(
            entity = KnowledgeNode::class,
            parentColumns = ["id"],
            childColumns = ["from_id"],
            onDelete = ForeignKey.CASCADE
        ),
        ForeignKey(
            entity = KnowledgeNode::class,
            parentColumns = ["id"],
            childColumns = ["to_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index("from_id"),
        Index("to_id")
    ]
)
data class KnowledgeEdge(
    @ColumnInfo(name = "from_id")
    val fromId: String,                // 起点知识点ID

    @ColumnInfo(name = "to_id")
    val toId: String,                  // 终点知识点ID

    @ColumnInfo(name = "type")
    val type: String,                  // PARENT / PREREQUISITE / RELATED / APPLIED_IN

    @ColumnInfo(name = "strength")
    val strength: Float = 1.0f         // 关联强度 0.0~1.0
) {
    companion object {
        /** 包含关系：条件推理 → 肯定前件式 */
        const val TYPE_PARENT = "PARENT"

        /** 前置关系：必须先学A才能学B */
        const val TYPE_PREREQUISITE = "PREREQUISITE"

        /** 关联关系：两个知识点可以互相参考 */
        const val TYPE_RELATED = "RELATED"

        /** 应用关系：A知识在B场景中用到 */
        const val TYPE_APPLIED_IN = "APPLIED_IN"
    }
}
