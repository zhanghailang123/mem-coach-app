package cn.com.memcoach.data.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * 知识点节点实体
 *
 * 存储MEM管综的知识点树形结构。
 * 通过 parentId 构成层级关系，通过 KnowledgeEdge 表存储跨层级关联。
 */
@Entity(
    tableName = "knowledge_nodes",
    foreignKeys = [
        ForeignKey(
            entity = KnowledgeNode::class,
            parentColumns = ["id"],
            childColumns = ["parent_id"],
            onDelete = ForeignKey.SET_NULL
        )
    ],
    indices = [
        Index("subject"),
        Index("parent_id")
    ]
)
data class KnowledgeNode(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,                    // logic_conditional_inference

    @ColumnInfo(name = "name")
    val name: String,                  // 条件推理

    @ColumnInfo(name = "subject")
    val subject: String,               // math / logic / writing / english

    @ColumnInfo(name = "chapter")
    val chapter: String?,              // formal_logic / analytical_logic

    @ColumnInfo(name = "parent_id")
    val parentId: String?,             // 上级知识点ID（自引用外键）

    @ColumnInfo(name = "description")
    val description: String?,          // 定义和核心概念（Markdown格式）

    @ColumnInfo(name = "content")
    val content: String?,              // 知识点详细正文（Markdown格式）

    @ColumnInfo(name = "exam_frequency")
    val examFrequency: Int = 0,        // 近10年考频（出现年份数，最大10）

    @ColumnInfo(name = "sort_weight")
    val sortWeight: Int = 0            // 学习顺序权重（数值越小越先学）
)
