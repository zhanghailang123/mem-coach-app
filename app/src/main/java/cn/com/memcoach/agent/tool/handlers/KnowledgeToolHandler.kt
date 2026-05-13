package cn.com.memcoach.agent.tool.handlers

import cn.com.memcoach.agent.tool.ToolDefinition
import cn.com.memcoach.agent.tool.ToolHandler
import cn.com.memcoach.data.dao.KnowledgeEdgeDao
import cn.com.memcoach.data.dao.KnowledgeNodeDao
import cn.com.memcoach.data.entity.KnowledgeEdge
import cn.com.memcoach.data.entity.KnowledgeNode
import org.json.JSONArray
import org.json.JSONObject

/**
 * 知识点工具处理器 —— 提供知识点搜索、详情查询、知识图谱展开等工具。
 *
 * 覆盖工具：
 * - knowledge_search        —— 按科目、关键词搜索知识点
 * - knowledge_node_detail   —— 获取知识点详细信息（定义、核心概念、考频）
 * - knowledge_graph_expand  —— 以某节点为中心展开知识图谱
 *
 * 图谱展开同时使用：
 * - KnowledgeNode.parentId：稳定表达章节/父子层级；
 * - KnowledgeEdge：表达先修、相关、应用等跨层级关系。
 */
class KnowledgeToolHandler(
    private val knowledgeNodeDao: KnowledgeNodeDao,
    private val knowledgeEdgeDao: KnowledgeEdgeDao
) : ToolHandler {

    override val toolNames = setOf(
        "knowledge_search",
        "knowledge_node_detail",
        "knowledge_graph_expand"
    )

    override suspend fun execute(toolName: String, arguments: String): String {
        return try {
            val args = JSONObject(arguments)
            when (toolName) {
                "knowledge_search" -> searchKnowledge(args)
                "knowledge_node_detail" -> getNodeDetail(args)
                "knowledge_graph_expand" -> expandGraph(args)
                else -> errorJson("unknown tool: $toolName")
            }
        } catch (e: Exception) {
            errorJson("execute error: ${e.message?.replace("\"", "'")}")
        }
    }

    override fun getDefinitions(): List<ToolDefinition> = listOf(
        ToolDefinition(
            name = "knowledge_search",
            description = "搜索知识点库，支持按科目、关键词查找。返回匹配的知识点列表（含ID、名称、描述、考频）。",
            parameters = """
{
  "type": "object",
  "properties": {
    "subject": {
      "type": "string",
      "description": "科目：logic/writing/math/english",
      "enum": ["logic", "writing", "math", "english"]
    },
    "keyword": {
      "type": "string",
      "description": "搜索关键词，模糊匹配知识点名称和描述"
    },
    "limit": {
      "type": "integer",
      "default": 10,
      "description": "返回数量上限"
    }
  },
  "required": ["subject"]
}
""".trimIndent()
        ),
        ToolDefinition(
            name = "knowledge_node_detail",
            description = "获取指定知识点的完整详情：定义、核心概念、完整知识点正文（Markdown）、考频、排序权重。",
            parameters = """
{
  "type": "object",
  "properties": {
    "node_id": {
      "type": "string",
      "description": "知识点ID，如 logic_conditional_inference"
    }
  },
  "required": ["node_id"]
}
""".trimIndent()
        ),
        ToolDefinition(
            name = "knowledge_graph_expand",
            description = "以指定知识点节点为中心展开知识图谱。返回父子层级、先修关系、相关知识点和应用关系。用于展示知识点关联结构。",
            parameters = """
{
  "type": "object",
  "properties": {
    "node_id": {
      "type": "string",
      "description": "中心节点ID"
    },
    "depth": {
      "type": "integer",
      "default": 2,
      "description": "展开深度，1=仅直接子节点，2=子节点+孙节点"
    }
  },
  "required": ["node_id"]
}
""".trimIndent()
        )
    )

    // ─── 工具实现 ───

    private suspend fun searchKnowledge(args: JSONObject): String {
        val subject = args.optString("subject", "")
        if (subject.isBlank()) return errorJson("subject 必填")
        val keyword = args.optString("keyword", "")
        val limit = args.optInt("limit", 10)

        val allNodes = knowledgeNodeDao.getBySubject(subject)

        val filtered = if (keyword.isNotBlank()) {
            allNodes.filter {
                it.name.contains(keyword, ignoreCase = true) ||
                (it.description?.contains(keyword, ignoreCase = true) == true)
            }
        } else {
            allNodes
        }.take(limit)

        val json = JSONObject()
        json.put("count", filtered.size)
        json.put("knowledge_nodes", JSONArray().apply {
            filtered.forEach { node ->
                put(JSONObject().apply {
                    put("id", node.id)
                    put("name", node.name)
                    put("subject", node.subject)
                    put("chapter", node.chapter ?: JSONObject.NULL)
                    put("description", node.description ?: JSONObject.NULL)
                    put("exam_frequency", node.examFrequency)
                    put("sort_weight", node.sortWeight)
                })
            }
        })
        return json.toString()
    }

    private suspend fun getNodeDetail(args: JSONObject): String {
        val nodeId = args.optString("node_id", "")
        if (nodeId.isBlank()) return errorJson("node_id 必填")

        val node = knowledgeNodeDao.getById(nodeId)
            ?: return errorJson("知识点不存在: $nodeId")

        val json = JSONObject()
        json.put("id", node.id)
        json.put("name", node.name)
        json.put("subject", node.subject)
        json.put("chapter", node.chapter ?: JSONObject.NULL)
        json.put("parent_id", node.parentId ?: JSONObject.NULL)
        json.put("description", node.description ?: JSONObject.NULL)
        json.put("content", node.content ?: JSONObject.NULL)
        json.put("exam_frequency", node.examFrequency)
        json.put("sort_weight", node.sortWeight)
        return json.toString()
    }

    private suspend fun expandGraph(args: JSONObject): String {
        val nodeId = args.optString("node_id", "")
        if (nodeId.isBlank()) return errorJson("node_id 必填")
        val depth = args.optInt("depth", 2).coerceIn(1, 3)

        val centerNode = knowledgeNodeDao.getById(nodeId)
            ?: return errorJson("知识点不存在: $nodeId")

        val json = JSONObject()
        json.put("center", buildNodeJson(centerNode))

        // 获取父节点
        if (centerNode.parentId != null) {
            val parent = knowledgeNodeDao.getById(centerNode.parentId!!)
            if (parent != null) {
                json.put("parent", buildNodeJson(parent))
            }
        }

        // 获取子节点（可按深度递归展开）
        val children = knowledgeNodeDao.getChildren(nodeId)
        json.put("children", JSONArray().apply {
            children.forEach { child ->
                val childJson = buildNodeJson(child)
                if (depth > 1) {
                    val grandchildren = knowledgeNodeDao.getChildren(child.id)
                    childJson.put("children", JSONArray().apply {
                        grandchildren.forEach { gc ->
                            put(buildNodeJson(gc))
                        }
                    })
                }
                put(childJson)
            }
        })

        val edges = knowledgeEdgeDao.getNeighborhood(nodeId)
        json.put("edges", JSONArray().apply {
            edges.forEach { edge -> put(buildEdgeJson(edge)) }
        })
        json.put("prerequisites", buildRelatedNodeArray(edges, nodeId, KnowledgeEdge.TYPE_PREREQUISITE, incoming = true))
        json.put("next_to_learn", buildRelatedNodeArray(edges, nodeId, KnowledgeEdge.TYPE_PREREQUISITE, incoming = false))
        json.put("related", buildRelatedNodeArray(edges, nodeId, KnowledgeEdge.TYPE_RELATED, incoming = null))
        json.put("applications", buildRelatedNodeArray(edges, nodeId, KnowledgeEdge.TYPE_APPLIED_IN, incoming = false))

        return json.toString()
    }

    private suspend fun buildRelatedNodeArray(
        edges: List<KnowledgeEdge>,
        centerNodeId: String,
        type: String,
        incoming: Boolean?
    ): JSONArray {
        return JSONArray().apply {
            edges.filter { edge ->
                edge.type == type && when (incoming) {
                    true -> edge.toId == centerNodeId
                    false -> edge.fromId == centerNodeId
                    null -> edge.fromId == centerNodeId || edge.toId == centerNodeId
                }
            }.forEach { edge ->
                val targetId = when {
                    edge.fromId == centerNodeId -> edge.toId
                    else -> edge.fromId
                }
                val target = knowledgeNodeDao.getById(targetId) ?: return@forEach
                put(buildNodeJson(target).apply {
                    put("relation_type", edge.type)
                    put("strength", edge.strength)
                    put("direction", if (edge.fromId == centerNodeId) "outgoing" else "incoming")
                })
            }
        }
    }

    private fun buildEdgeJson(edge: KnowledgeEdge): JSONObject {
        return JSONObject().apply {
            put("from_id", edge.fromId)
            put("to_id", edge.toId)
            put("type", edge.type)
            put("strength", edge.strength)
        }
    }

    private fun buildNodeJson(node: KnowledgeNode): JSONObject {
        return JSONObject().apply {
            put("id", node.id)
            put("name", node.name)
            put("subject", node.subject)
            put("chapter", node.chapter ?: JSONObject.NULL)
            put("description", node.description ?: JSONObject.NULL)
            put("exam_frequency", node.examFrequency)
        }
    }

    private fun errorJson(msg: String): String {
        // 安全地转义消息中的双引号
        val escaped = msg.replace("\\", "\\\\").replace("\"", "\\\"")
        return """{"error":"$escaped"}"""
    }
}
