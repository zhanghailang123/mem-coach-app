# MEM Coach 记忆系统设计文档

## 1. 概述

MEM Coach 的记忆系统是 AI 考研教练的核心能力之一，它使 Agent 能够：

- **记住用户的学习偏好**：喜欢什么时间段学习、偏好哪种讲解方式
- **追踪易错模式**：哪些知识点反复出错、错误类型是什么
- **保存学习心得**：用户自己总结的技巧、理解难点的方法
- **智能归档**：自动筛选值得长期保存的信息，避免记忆膨胀

### 设计目标

| 目标 | 说明 |
|------|------|
| **轻量级** | 避免引入向量数据库等重依赖，适合移动端部署 |
| **智能化** | LLM 辅助筛选长期记忆，减少人工维护 |
| **可扩展** | 支持标签、重要性等多维度检索 |
| **向后兼容** | 在没有 LLM 时降级为简单归档 |

### 借鉴来源

本系统的设计借鉴了 OpenOmniBot 的 WorkspaceMemoryService，但做了以下简化：

| 特性 | OpenOmniBot | MEM Coach |
|------|-------------|-----------|
| 向量化搜索 | ✅ text-embedding-3-small | ❌ 仅关键词搜索 |
| 智能 Rollup | ✅ LLM 辅助筛选 | ✅ LLM 辅助筛选 |
| 记忆分类 | 基础分类 | 6 类 + 标签 + 重要性 |
| 存储格式 | SQLite + JSONL | JSONL + Markdown |

---

## 2. 架构设计

### 2.1 双层记忆模型

```
┌─────────────────────────────────────────────────────────────┐
│                      记忆系统架构                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────────┐          ┌──────────────────┐        │
│  │   短期记忆层      │          │   长期记忆层      │        │
│  │  (DailyMemory)    │  ──────► │  (LongTermMemory) │        │
│  │                   │  Rollup  │                   │        │
│  │  • 按日期存储      │          │  • 持久化存储      │        │
│  │  • 自动生成摘要    │          │  • 分类 + 标签     │        │
│  │  • 临时性内容      │          │  • 重要性分级      │        │
│  └──────────────────┘          └──────────────────┘        │
│           │                             │                   │
│           ▼                             ▼                   │
│  ┌──────────────────┐          ┌──────────────────┐        │
│  │  DailyMemoryTool  │          │ LongTermMemoryTool│        │
│  │    Handler        │          │    Handler        │        │
│  └──────────────────┘          └──────────────────┘        │
│           │                             │                   │
│           └──────────────┬──────────────┘                   │
│                          ▼                                  │
│                 ┌──────────────────┐                        │
│                 │   AgentToolRouter │                        │
│                 └──────────────────┘                        │
│                          │                                  │
│                          ▼                                  │
│                 ┌──────────────────┐                        │
│                 │  AgentOrchestrator│                        │
│                 └──────────────────┘                        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 数据流向

```
用户学习行为
      │
      ▼
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│ StudyRecord │───►│ DailyMemory │───►│ LLM Rollup  │
│   (数据库)   │    │  (Markdown) │    │  (智能筛选)  │
└─────────────┘    └─────────────┘    └─────────────┘
                                             │
                                             ▼
                                     ┌─────────────┐
                                     │ LongTermMemory│
                                     │   (JSONL)     │
                                     └─────────────┘
```

---

## 3. 短期记忆层 (DailyMemoryService)

### 3.1 功能概述

短期记忆负责记录**当日**的学习活动，包括：

- 手动追加的学习笔记
- 自动生成的学习摘要
- 用户的临时性需求

### 3.2 存储格式

**目录结构**：
```
/data/data/.../memory/
├── daily/
│   ├── 2026-05-14.md
│   ├── 2026-05-15.md
│   └── ...
└── longterm/
    └── memories.jsonl
```

**文件格式** (Markdown)：
```markdown
## 今日学习摘要

- 做题数: 25
- 正确数: 18
- 正确率: 72%
- 学习时长: 45 分钟

### 薄弱知识点
- 形式逻辑推理
- 论证有效性分析

### 掌握良好
- 假言推理
- 三段论

[14:30] 用户表示需要加强论证有效性分析的练习
[15:45] 完成了 5 道形式逻辑推理题，正确率 60%
```

### 3.3 核心方法

#### `append(text: String)`
追加一条记忆到当日文件。

```kotlin
suspend fun append(text: String): File {
    val today = dateFormat.format(Calendar.getInstance().time)
    val file = File(dailyDir, "$today.md")
    val timestamp = SimpleDateFormat("HH:mm", Locale.US).format(Calendar.getInstance().time)
    val entry = "[$timestamp] $text\n"
    file.appendText(entry)
    return file
}
```

#### `generateDailySummary()`
从数据库自动生成当日学习摘要。

**数据来源**：
- `StudyRecordDao`：做题记录
- `UserMasteryDao`：掌握度数据
- `KnowledgeNodeDao`：知识点信息

**输出内容**：
- 做题数、正确数、正确率
- 学习时长
- 薄弱知识点列表
- 掌握良好的知识点

#### `rollupDay(date: String?)`
简单归档当日记忆，生成摘要并保存。

#### `intelligentRollup(date: String?)`
**智能归档**（新增功能），调用 LLM 筛选值得长期保存的信息。

**流程**：
1. 获取当日记忆内容
2. 调用 LLM 分析，返回 JSON 数组
3. 解析 LLM 返回的候选条目
4. 写入长期记忆服务

**降级策略**：
- 如果 LLM 客户端不可用 → 降级为 `rollupDay()`
- 如果 LLM 调用失败 → 降级为 `rollupDay()`
- 如果 LLM 返回空数组 → 仅生成摘要，不写入长期记忆

### 3.4 工具接口

| 工具名称 | 功能 | 参数 |
|----------|------|------|
| `memory_query_today` | 查询今日学习摘要 | 无 |
| `memory_generate_daily` | 生成并保存今日学习摘要 | 无 |
| `memory_append` | 追加一条记忆 | `text`: 记忆内容 |
| `memory_recent_days` | 获取最近 N 天的记忆 | `days`: 天数 (默认 7) |
| `memory_intelligent_rollup` | 智能归档当日记忆 | `date`: 目标日期 (可选) |

---

## 4. 长期记忆层 (LongTermMemoryService)

### 4.1 功能概述

长期记忆负责持久化存储**有价值**的学习信息，包括：

- 学习偏好
- 易错模式
- 重要心得
- 关键概念
- 公式定理
- 成就里程碑

### 4.2 存储格式

**文件**：`/data/data/.../memory/longterm/memories.jsonl`

**每行格式** (JSON Lines)：
```json
{
  "id": "a1b2c3d4",
  "text": "用户偏好在晚上 9-11 点学习逻辑，此时注意力最集中",
  "category": "preference",
  "tags": ["学习时间", "学习习惯"],
  "importance": 7,
  "created_at": "2026-05-14T19:00:00",
  "updated_at": "2026-05-14T19:00:00"
}
```

### 4.3 记忆分类 (Category)

| 分类 | 说明 | 示例 |
|------|------|------|
| `preference` | 学习偏好 | "喜欢用思维导图整理知识点" |
| `mistake` | 易错模式 | "假言推理的逆否命题经常混淆" |
| `note` | 学习笔记 | "论证有效性分析的常见逻辑谬误" |
| `achievement` | 成就里程碑 | "连续学习 7 天" |
| `concept` | 关键概念 | "充分条件 vs 必要条件的区别" |
| `formula` | 公式定理 | "德摩根定律：¬(A∧B) = ¬A∨¬B" |

### 4.4 标签系统 (Tags)

标签用于多维度检索，例如：

- `["形式逻辑", "假言推理"]` — 按知识点分类
- `["高频错误", "粗心"]` — 按错误类型分类
- `["学习技巧", "记忆方法"]` — 按内容类型分类

**标签命名规范**：
- 使用中文，简洁明了
- 每个标签不超过 4 个字
- 每条记忆最多 5 个标签

### 4.5 重要性分级 (Importance)

| 等级 | 说明 | 使用场景 |
|------|------|----------|
| 1-3 | 可选保存 | 临时性笔记、一般性观察 |
| 4-6 | 建议保存 | 学习心得、常见错误 |
| 7-9 | 强烈建议保存 | 关键概念、高频错误模式 |
| 10 | 必须保存 | 核心公式、重要突破 |

### 4.6 核心方法

#### `upsert(text, category, tags, importance)`
写入长期记忆（自动去重）。

**去重逻辑**：
1. 完全匹配：`existingLower == textLower`
2. 包含关系：`existingLower.contains(textLower)` 或 `textLower.contains(existingLower)`

#### `search(query, limit)`
基于关键词搜索记忆。

**搜索范围**：
- 记忆内容 (`text`)
- 分类名称 (`category`)

#### `searchByTag(tag, limit)`
按标签搜索记忆，按重要性降序排列。

#### `searchByImportance(minImportance, limit)`
按重要性搜索记忆，返回重要性 >= minImportance 的条目。

#### `getAllTags()`
获取所有标签列表，用于标签云展示。

### 4.7 工具接口

| 工具名称 | 功能 | 参数 |
|----------|------|------|
| `memory_search` | 搜索长期记忆 | `query`: 关键词, `limit`: 数量上限 |
| `memory_write_longterm` | 写入长期记忆 | `text`: 内容, `category`: 分类, `tags`: 标签, `importance`: 重要性 |
| `memory_update` | 更新长期记忆 | `id`: 记忆 ID, `text`: 新内容 |
| `memory_delete` | 删除长期记忆 | `id`: 记忆 ID |
| `memory_stats` | 获取记忆统计 | 无 |
| `memory_search_by_tag` | 按标签搜索 | `tag`: 标签名, `limit`: 数量上限 |
| `memory_search_by_importance` | 按重要性搜索 | `min_importance`: 最低重要性, `limit`: 数量上限 |
| `memory_get_tags` | 获取所有标签 | 无 |

---

## 5. 智能 Rollup 机制

### 5.1 设计目标

智能 Rollup 是 MEM Coach 记忆系统的核心创新点，它解决了以下问题：

1. **信息过载**：每天的学习记录很多，但不是所有都值得长期保存
2. **人工维护成本**：让用户手动筛选长期记忆不现实
3. **记忆质量**：需要 LLM 的理解能力来判断信息的价值

### 5.2 工作流程

```
┌─────────────────────────────────────────────────────────────┐
│                    智能 Rollup 流程                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. 获取当日记忆                                              │
│     │                                                       │
│     ▼                                                       │
│  2. 调用 LLM 分析                                            │
│     │                                                       │
│     ├─ 返回 JSON 数组                                        │
│     │  [                                                     │
│     │    {                                                   │
│     │      "text": "用户偏好晚上学习",                         │
│     │      "category": "preference",                         │
│     │      "tags": ["学习时间"],                               │
│     │      "importance": 7                                   │
│     │    },                                                  │
│     │    ...                                                 │
│     │  ]                                                     │
│     │                                                       │
│     ▼                                                       │
│  3. 解析候选条目                                              │
│     │                                                       │
│     ▼                                                       │
│  4. 写入长期记忆（去重）                                       │
│     │                                                       │
│     ▼                                                       │
│  5. 生成当日摘要                                              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 5.3 LLM Prompt 设计

**System Prompt**：
```
你是一个学习记忆管理助手。你的任务是从短期学习记录中筛选出值得长期保存的信息。

筛选标准：
1. **学习偏好**：用户的学习习惯、时间偏好、方法偏好
2. **易错模式**：反复出错的知识点、错误类型、错误原因
3. **重要心得**：用户总结的学习技巧、理解难点的方法
4. **关键概念**：重要的定义、公式、定理
5. **成就里程碑**：连续学习天数、突破性进步

输出格式（JSON数组）：
[
  {
    "text": "记忆内容",
    "category": "preference|mistake|note|concept|formula|achievement",
    "tags": ["标签1", "标签2"],
    "importance": 7
  }
]

重要性等级（1-10）：
- 1-3：可选保存
- 4-6：建议保存
- 7-9：强烈建议保存
- 10：必须保存
```

**User Prompt**：
```
请从以下 {date} 的学习记录中筛选值得长期保存的信息：

{dailyContent}

请返回 JSON 数组格式，如果没有值得保存的内容，返回空数组 []。
```

### 5.4 降级策略

```
智能 Rollup
    │
    ├─ LLM 客户端可用？
    │   │
    │   ├─ 是 → 调用 LLM 分析
    │   │       │
    │   │       ├─ 成功 → 写入长期记忆
    │   │       │
    │   │       └─ 失败 → 降级为简单归档
    │   │
    │   └─ 否 → 降级为简单归档
    │
    └─ 简单归档：仅生成摘要，不筛选长期记忆
```

### 5.5 触发时机

智能 Rollup 可以在以下时机触发：

1. **手动触发**：用户调用 `memory_intelligent_rollup` 工具
2. **定时触发**：每日凌晨自动执行（需配合自动化任务）
3. **事件触发**：当日记忆条数超过阈值时

---

## 6. 与 OpenOmniBot 的对比

### 6.1 架构对比

| 组件 | OpenOmniBot | MEM Coach | 说明 |
|------|-------------|-----------|------|
| 向量化搜索 | ✅ text-embedding-3-small | ❌ 关键词搜索 | MEM Coach 简化实现 |
| 智能 Rollup | ✅ LLM 辅助 | ✅ LLM 辅助 | 核心功能对齐 |
| 记忆分类 | 基础分类 | 6 类 + 标签 | MEM Coach 更细粒度 |
| 存储后端 | SQLite + JSONL | JSONL + Markdown | MEM Coach 更轻量 |
| 多语言支持 | ✅ | ✅ | 通过 prompt_i18n |

### 6.2 功能对比

| 功能 | OpenOmniBot | MEM Coach |
|------|-------------|-----------|
| 记忆写入 | ✅ | ✅ |
| 记忆搜索 | ✅ 语义 + 关键词 | ✅ 关键词 + 标签 + 重要性 |
| 记忆更新 | ✅ | ✅ |
| 记忆删除 | ✅ | ✅ |
| 记忆统计 | ✅ | ✅ |
| 标签系统 | ❌ | ✅ |
| 重要性分级 | ❌ | ✅ |
| 智能 Rollup | ✅ | ✅ |
| 上下文压缩 | ✅ 128K 阈值 | ✅ 128K 阈值 |

### 6.3 简化原因

MEM Coach 选择不实现向量化搜索的原因：

1. **成本考虑**：text-embedding-3-small 不免费（$0.02/百万 token）
2. **部署复杂度**：需要额外的向量数据库或索引
3. **移动端限制**：设备资源有限，不适合运行大型 embedding 模型
4. **需求匹配**：考研学习场景下，关键词 + 标签搜索已足够

**未来可扩展**：
- 接入免费 embedding 模型（如 all-MiniLM-L6-v2）
- 使用 Ollama 本地部署开源模型
- 接入 Cohere 免费层

---

## 7. 使用示例

### 7.1 记录学习笔记

**Agent 调用**：
```json
{
  "tool": "memory_append",
  "arguments": {
    "text": "用户表示假言推理的逆否命题总是搞混，需要多做练习"
  }
}
```

**结果**：
```json
{
  "success": true,
  "path": "/data/data/.../memory/daily/2026-05-15.md",
  "message": "已记录到今日记忆。"
}
```

### 7.2 智能归档

**Agent 调用**：
```json
{
  "tool": "memory_intelligent_rollup",
  "arguments": {
    "date": "2026-05-15"
  }
}
```

**LLM 返回**：
```json
[
  {
    "text": "用户在晚上 9-11 点学习效率最高，偏好先做题再看讲解",
    "category": "preference",
    "tags": ["学习时间", "学习方法"],
    "importance": 7
  },
  {
    "text": "假言推理的逆否命题是薄弱点，需要加强练习",
    "category": "mistake",
    "tags": ["形式逻辑", "假言推理", "高频错误"],
    "importance": 8
  }
]
```

**结果**：
```json
{
  "success": true,
  "date": "2026-05-15",
  "candidates_count": 2,
  "inserted_count": 2,
  "entries": [
    {"text": "用户在晚上 9-11 点学习效率最高...", "category": "preference"},
    {"text": "假言推理的逆否命题是薄弱点...", "category": "mistake"}
  ]
}
```

### 7.3 按标签搜索

**Agent 调用**：
```json
{
  "tool": "memory_search_by_tag",
  "arguments": {
    "tag": "假言推理",
    "limit": 5
  }
}
```

**结果**：
```json
{
  "tag": "假言推理",
  "count": 3,
  "results": [
    {
      "id": "a1b2c3d4",
      "text": "假言推理的逆否命题是薄弱点",
      "category": "mistake",
      "tags": ["形式逻辑", "假言推理", "高频错误"],
      "importance": 8,
      "created_at": "2026-05-15T19:00:00",
      "updated_at": "2026-05-15T19:00:00"
    },
    ...
  ]
}
```

### 7.4 获取记忆统计

**Agent 调用**：
```json
{
  "tool": "memory_stats",
  "arguments": {}
}
```

**结果**：
```json
{
  "total": 42,
  "by_category": {
    "preference": 8,
    "mistake": 15,
    "note": 12,
    "achievement": 3,
    "concept": 3,
    "formula": 1
  }
}
```

---

## 8. 配置与扩展

### 8.1 场景配置

记忆相关的 Prompt 已配置在 `model_scenes_default.json` 中：

```json
{
  "scene.memory.rollup": {
    "model": "qwen-plus",
    "prompt": "你是一个学习记忆管理助手...",
    "prompt_i18n": {
      "zh-CN": "你是一个学习记忆管理助手...",
      "en-US": "You are a learning memory management assistant..."
    }
  }
}
```

### 8.2 自定义分类

如需添加新的记忆分类，修改 `LongTermMemoryService.kt`：

```kotlin
// 在 upsert 方法中添加新的分类
val validCategories = setOf(
    "preference", "mistake", "note", 
    "achievement", "concept", "formula",
    "custom_category"  // 新增
)
```

### 8.3 调整重要性阈值

修改 `searchByImportance` 的默认阈值：

```kotlin
fun searchByImportance(
    minImportance: Int = 7,  // 修改此值
    limit: Int = 5
): List<MemoryEntry> {
    // ...
}
```

### 8.4 扩展向量化搜索

如需添加向量化搜索，可以：

1. 接入免费 embedding 模型
2. 在 `LongTermMemoryService` 中添加向量索引
3. 修改 `search` 方法，结合语义搜索和关键词搜索

---

## 9. 最佳实践

### 9.1 记忆内容规范

**好的记忆**：
- ✅ "用户偏好晚上 9-11 点学习逻辑，此时注意力最集中"
- ✅ "假言推理的逆否命题是薄弱点，已连续 3 天出错"
- ✅ "德摩根定律：¬(A∧B) = ¬A∨¬B，适用于否定联言命题"

**不好的记忆**：
- ❌ "今天学习了逻辑" （太笼统）
- ❌ "用户做了 10 道题" （临时性数据）
- ❌ "第 3 题选 B" （无长期价值）

### 9.2 标签命名规范

**推荐**：
- 使用中文：`"假言推理"` 而非 `"hypothetical_reasoning"`
- 简洁明了：`"高频错误"` 而非 `"经常出错的知识点"`
- 有层次：`"形式逻辑"` → `"假言推理"` → `"逆否命题"`

**避免**：
- 过长：`"用户经常在晚上学习的习惯"` → `"学习时间"`
- 过于具体：`"2026年5月15日的学习记录"` → `"学习笔记"`

### 9.3 重要性设置建议

| 场景 | 建议重要性 |
|------|------------|
| 用户明确表示的偏好 | 7-8 |
| 连续 3 天以上的错误模式 | 8-9 |
| 核心公式/定理 | 9-10 |
| 一般性学习笔记 | 4-5 |
| 临时性观察 | 1-3 |

---

## 10. 未来规划

### 10.1 短期 (1-2 个月)

- [ ] 添加记忆导出功能（JSON/CSV）
- [ ] 支持记忆手动编辑（Flutter UI）
- [ ] 添加记忆搜索历史

### 10.2 中期 (3-6 个月)

- [ ] 接入免费 embedding 模型
- [ ] 支持语义搜索
- [ ] 添加记忆关联图谱

### 10.3 长期 (6-12 个月)

- [ ] 支持多设备同步
- [ ] 记忆分析报告
- [ ] 个性化学习建议

---

## 附录 A：API 参考

### LongTermMemoryService

```kotlin
class LongTermMemoryService(private val memoryDir: File) {
    
    // 搜索
    fun search(query: String, limit: Int = 5): List<MemoryEntry>
    fun searchByTag(tag: String, limit: Int = 5): List<MemoryEntry>
    fun searchByImportance(minImportance: Int = 7, limit: Int = 5): List<MemoryEntry>
    
    // 写入
    fun upsert(text: String, category: String = "note", tags: List<String> = emptyList(), importance: Int = 5): Boolean
    
    // 更新/删除
    fun update(id: String, newText: String): Boolean
    fun delete(id: String): Boolean
    
    // 查询
    fun getAll(): List<MemoryEntry>
    fun getByCategory(category: String): List<MemoryEntry>
    fun getAllTags(): List<String>
    fun getStats(): Map<String, Any>
}
```

### DailyMemoryService

```kotlin
class DailyMemoryService(
    private val memoryDir: File,
    private val studyRecordDao: StudyRecordDao,
    private val userMasteryDao: UserMasteryDao,
    private val knowledgeNodeDao: KnowledgeNodeDao,
    private val longTermMemoryService: LongTermMemoryService? = null,
    private val llmClient: AgentLlmClient? = null
) {
    // 追加
    suspend fun append(text: String): File
    
    // 查询
    fun getToday(): String
    fun getForDate(date: String): String
    fun getRecentDays(days: Int = 7): List<Map<String, String>>
    fun listAll(): List<String>
    
    // 生成摘要
    suspend fun generateDailySummary(): String
    
    // 归档
    suspend fun rollupDay(date: String? = null): Map<String, Any?>
    suspend fun intelligentRollup(date: String? = null): Map<String, Any?>
}
```

---

## 附录 B：错误处理

### 常见错误

| 错误 | 原因 | 解决方案 |
|------|------|----------|
| `text 不能为空` | 写入空内容 | 检查输入 |
| `id 不能为空` | 更新/删除时未提供 ID | 检查输入 |
| `记忆已存在` | 去重检测到重复 | 无需处理 |
| `LLM 调用失败` | 网络或 API 错误 | 自动降级为简单归档 |

### 日志查看

```bash
# 查看记忆系统日志
adb logcat | grep -E "(LongTermMemory|DailyMemory|MemoryTool)"
```

---

**文档版本**：v1.0  
**最后更新**：2026-05-15  
**作者**：MEM Coach 开发团队
