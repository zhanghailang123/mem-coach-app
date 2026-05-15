package cn.com.memcoach.agent.memory

import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * 长期记忆服务 —— 持久化用户的学习偏好、易错模式、重要笔记。
 *
 * 设计借鉴：OpenOmniBot WorkspaceMemoryService 的长期记忆机制。
 *
 * 核心功能：
 * 1. 存储长期记忆（用户偏好、易错模式、学习心得）
 * 2. 搜索记忆（基于关键词匹配、标签、重要性）
 * 3. 去重写入（避免重复记录）
 *
 * 存储格式：JSON Lines 文件
 *   /data/data/.../memory/longterm/memories.jsonl
 *
 * 每条记忆格式：
 * {
 *   "id": "uuid",
 *   "text": "记忆内容",
 *   "category": "preference|mistake|note|achievement|concept|formula",
 *   "tags": ["标签1", "标签2"],
 *   "importance": 5,
 *   "created_at": "2026-05-14T19:00:00",
 *   "updated_at": "2026-05-14T19:00:00"
 * }
 */
class LongTermMemoryService(
    private val memoryDir: File
) {
    private val longTermDir = File(memoryDir, "longterm")
    private val memoriesFile = File(longTermDir, "memories.jsonl")
    private val dateFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)

    // 内存中的记忆索引（启动时加载）
    private val memories = mutableListOf<MemoryEntry>()

    init {
        longTermDir.mkdirs()
        loadMemories()
    }

    /**
     * 记忆条目
     */
    data class MemoryEntry(
        val id: String,
        val text: String,
        val category: String,
        val tags: List<String> = emptyList(),
        val importance: Int = 5,
        val createdAt: String,
        val updatedAt: String
    ) {
        fun toJson(): String {
            val tagsJson = tags.joinToString(",") { "\"${it.replace("\"", "\\\"").replace("\n", "\\n")}\"" }
            return """{"id":"$id","text":"${text.replace("\"", "\\\"").replace("\n", "\\n")}","category":"$category","tags":[$tagsJson],"importance":$importance,"created_at":"$createdAt","updated_at":"$updatedAt"}"""
        }

        companion object {
            fun fromJson(json: String): MemoryEntry? {
                return try {
                    val obj = org.json.JSONObject(json)
                    val tagsArray = obj.optJSONArray("tags")
                    val tags = mutableListOf<String>()
                    if (tagsArray != null) {
                        for (i in 0 until tagsArray.length()) {
                            tags.add(tagsArray.getString(i))
                        }
                    }
                    
                    MemoryEntry(
                        id = obj.getString("id"),
                        text = obj.getString("text"),
                        category = obj.optString("category", "note"),
                        tags = tags,
                        importance = obj.optInt("importance", 5),
                        createdAt = obj.optString("created_at", ""),
                        updatedAt = obj.optString("updated_at", "")
                    )
                } catch (e: Exception) {
                    null
                }
            }
        }
    }

    /**
     * 搜索记忆
     */
    fun search(query: String, limit: Int = 5): List<MemoryEntry> {
        if (query.isBlank()) return memories.take(limit)

        val queryLower = query.lowercase()
        return memories
            .filter { entry ->
                entry.text.lowercase().contains(queryLower) ||
                entry.category.lowercase().contains(queryLower)
            }
            .sortedByDescending { it.updatedAt }
            .take(limit)
    }

    /**
     * 写入长期记忆（去重）
     */
    fun upsert(
        text: String, 
        category: String = "note",
        tags: List<String> = emptyList(),
        importance: Int = 5
    ): Boolean {
        if (text.isBlank()) return false

        // 简单去重：检查是否已存在相似内容
        val textLower = text.lowercase().trim()
        val exists = memories.any { entry ->
            val existingLower = entry.text.lowercase().trim()
            existingLower == textLower ||
            existingLower.contains(textLower) ||
            textLower.contains(existingLower)
        }

        if (exists) {
            return false // 已存在，跳过
        }

        val now = dateFormat.format(Calendar.getInstance().time)
        val entry = MemoryEntry(
            id = java.util.UUID.randomUUID().toString().take(8),
            text = text.trim(),
            category = category,
            tags = tags,
            importance = importance.coerceIn(1, 10),
            createdAt = now,
            updatedAt = now
        )

        memories.add(entry)
        appendToFile(entry)
        return true
    }

    /**
     * 更新记忆
     */
    fun update(id: String, newText: String): Boolean {
        val index = memories.indexOfFirst { it.id == id }
        if (index < 0) return false

        val old = memories[index]
        val now = dateFormat.format(Calendar.getInstance().time)
        val updated = old.copy(
            text = newText.trim(),
            updatedAt = now
        )

        memories[index] = updated
        rewriteFile()
        return true
    }

    /**
     * 删除记忆
     */
    fun delete(id: String): Boolean {
        val removed = memories.removeAll { it.id == id }
        if (removed) {
            rewriteFile()
        }
        return removed
    }

    /**
     * 获取所有记忆
     */
    fun getAll(): List<MemoryEntry> = memories.toList()

    /**
     * 按分类获取记忆
     */
    fun getByCategory(category: String): List<MemoryEntry> {
        return memories.filter { it.category == category }
    }

    /**
     * 按标签搜索记忆
     */
    fun searchByTag(tag: String, limit: Int = 5): List<MemoryEntry> {
        return memories
            .filter { it.tags.contains(tag) }
            .sortedByDescending { it.importance }
            .take(limit)
    }

    /**
     * 按重要性搜索记忆
     */
    fun searchByImportance(minImportance: Int = 7, limit: Int = 5): List<MemoryEntry> {
        return memories
            .filter { it.importance >= minImportance }
            .sortedByDescending { it.importance }
            .take(limit)
    }

    /**
     * 获取所有标签
     */
    fun getAllTags(): List<String> {
        return memories
            .flatMap { it.tags }
            .distinct()
            .sorted()
    }

    /**
     * 获取记忆统计
     */
    fun getStats(): Map<String, Any> {
        val byCategory = memories.groupBy { it.category }
        return mapOf(
            "total" to memories.size,
            "by_category" to byCategory.mapValues { it.value.size }
        )
    }

    // ─── 内部方法 ───

    private fun loadMemories() {
        if (!memoriesFile.exists()) return

        memoriesFile.readLines()
            .filter { it.isNotBlank() }
            .forEach { line ->
                MemoryEntry.fromJson(line)?.let { memories.add(it) }
            }
    }

    private fun appendToFile(entry: MemoryEntry) {
        memoriesFile.appendText(entry.toJson() + "\n")
    }

    private fun rewriteFile() {
        memoriesFile.writeText(memories.joinToString("\n") { it.toJson() } + "\n")
    }
}
