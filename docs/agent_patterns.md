# AI Agent 模式详解 — MEM Coach 中的前沿技术应用

> 本文档既是项目技术说明，也可作为面试/分享的技术素材。

---

## 1. 什么是 AI Agent

**一句话定义**：AI Agent = LLM（大脑） + Tools（手脚） + Memory（记忆） + Planning（规划）

传统 LLM 只能输出文本，Agent 可以：
- 自主决定**何时**调用工具
- 根据工具返回结果**调整**下一步行动
- 在**多轮循环**中逐步完成复杂任务
- 通过**记忆系统**跨会话保持上下文

MEM Coach 是一个**教育领域的垂直 Agent**——它不只是"问什么答什么"的 chatbot，而是能主动规划学习路径、诊断薄弱点、出题讲解的**AI 教练**。

---

## 2. ReAct 模式（Reasoning + Acting）

### 2.1 核心思想

ReAct 是 Google DeepMind 2022 年提出的范式，核心是让 LLM 在**推理（Thought）**和**行动（Action）**之间交替：

```
Thought → Action → Observation → Thought → Action → ... → Final Answer
```

### 2.2 在 MEM Coach 中的实现

AgentOrchestrator 的 while(true) 主循环就是 ReAct 的工程实现：

```kotlin
class AgentOrchestrator {
    
    suspend fun run(input: Input): AgentResult {
        var round = 0
        val maxRounds = 50 // 安全护栏
        
        while (round < maxRounds) {
            round++
            
            // 1. LLM 推理阶段 (Thinking)
            //    LLM 分析上下文，决定是否需要调用工具
            val response = llmClient.streamTurn(messages, tools)
            
            if (!response.isToolCall()) {
                // 2. 没有工具调用 → 输出最终答案
                return AgentResult(response.content)
            }
            
            // 3. 工具执行阶段 (Acting)
            val toolResult = toolRouter.execute(
                response.toolName, 
                response.arguments
            )
            
            // 4. 观察阶段 (Observation)
            //    工具结果追加到消息历史，下一轮 LLM 根据结果继续推理
            messages.add(toolResultMessage(response.toolCallId, toolResult))
        }
        
        throw MaxRoundsExceededException()
    }
}
```

### 2.3 System Prompt 中的 ReAct 格式

```markdown
## 工作模式

当你面对用户问题时，请按以下格式响应：

**Thought**: 分析当前问题和已有信息
**Action**: 如果需要调用工具，说明调用哪个工具和参数
**Observation**: 工具执行结果（由系统填充）
**Final Answer**: 最终回答（当不再需要工具时）

## 示例

用户："这道条件推理题怎么做？"

Thought: 用户需要解题帮助。我需要先获取题目信息，再决定讲解方式。
Action: exam_question_search({subject: "logic", type: "conditional_inference", limit: 1})
Observation: {题目数据}

Thought: 题目已获取，这是一道否定后件式的题。用户可能卡在逆否转换这一步。
我需要检查用户之前这道题的做题记录，看是不是错题。
Action: exam_mastery_update({question_id: "logic_2023_5", action: "query"})
Observation: {mastery_level: 0.4, last_correct: false}

Thought: 用户上次做错了，掌握度只有40%。我应该在讲解时多给提示，分步引导。
Final Answer: 这道题是典型的否定后件式...（分步讲解）
```

### 2.4 为什么 ReAct 优于简单 Chain

| | 简单 Chain | ReAct |
|---|---|---|
| 错误恢复 | 一步错全盘错 | 每步可观察可纠正 |
| 灵活性 | 固定流程 | 动态决策 |
| 可解释性 | 黑盒 | 每步有 Thought |
| 面试价值 | ⭐⭐ | ⭐⭐⭐⭐⭐ "实现了生产级 ReAct Agent" |

---

## 3. Plan-and-Execute 模式

### 3.1 核心思想

复杂任务不应边想边做，而应**先规划、再执行**。参考 Google Brain 的 LLM+P 和 Plan-and-Solve 论文。

### 3.2 在 MEM Coach 中的实现

学习路径规划采用此模式：

```
阶段 1: Planner（规划）
  用户："帮我制定一个逻辑复习计划，还有90天考试"
  → Agent 调用 study_plan_generate 工具
  → LLM分析：用户掌握度、剩余时间、薄弱点
  → 输出完整 JSON 学习计划：
  {
    "phases": [
      {"week": 1-2, "focus": "形式逻辑基础", "tasks": [...], "target_mastery": 0.7},
      {"week": 3-4, "focus": "分析推理", "tasks": [...], "target_mastery": 0.75},
      ...
    ],
    "daily_schedule": [
      {"day": 1, "tasks": ["逆否等价", "肯定前件式练习"], "time": "30min"},
      ...
    ]
  }

阶段 2: Execute（执行）
  → Agent 每日按计划推送任务
  → 执行中调用 progress_analyze 检查进度
  → 如果偏离计划 ≥ 20%，触发 Re-Plan（重新规划）
  → Self-Reflection 输出调整理由
```

### 3.3 面试吹逼要点

```
"我参考了 Plan-and-Solve 范式，设计了两阶段架构：
 1. Planner 阶段用强模型（如 GPT-4）生成结构化学习计划
 2. Executor 阶段用中等模型逐日执行，每天检查进度
 3. 偏差超过阈值时自动触发 Re-Plan
这个设计解决了长周期任务中 Agent 容易迷失方向的问题。"
```

---

## 4. Self-Reflection 反思机制

### 4.1 核心思想

Agent 在执行后对自己的回答进行**自我评估**，识别错误并调整后续策略。这是提升 Agent 可靠性的关键设计。

### 4.2 在 MEM Coach 中的实现

```markdown
## 反思要求

每轮练习结束后，你必须输出一段 Reflection：

**Reflection**:
- 我的讲解方法有效吗？（用户答对率是否提升？）
- 我是否遗漏了用户的知识盲区？
- 下一步应该调整什么？（难度？题型？教学策略？）

示例：
Reflection:
  本轮 5 道条件推理题，用户正确率 60%（3/5）。
  错误的两题都涉及"只有...才..."的逆否转换。
  我的讲解只讲了"如果...就..."的转换，没有覆盖"只有...才..."的特殊情况。
  → 调整策略：下一轮专门讲解"只有...才..."的转换规则，出 3 道专项练习。
```

### 4.3 代码中的反思触发点

```kotlin
// AgentOrchestrator 中的反思检查点
if (currentState == StudyState.REVIEW) {
    // 每轮练习结束后触发反思
    val reflectionPrompt = """
        请回顾本轮练习，进行自我反思：
        1. 学生的薄弱点是什么？
        2. 我的教学策略是否有效？
        3. 下一轮应该调整什么？
    """
    messages.add(ChatMessage(role = "user", content = reflectionPrompt))
    // LLM 输出反思内容，写入学习记忆
}
```

### 4.4 面试吹逼要点

```
"我实现了 Agent 的自我反思机制（Self-Reflection）。
关键设计是在每轮教学后强制 Agent 评估自己的教学效果：
- 分析用户错题模式
- 识别教学方法是否有效
- 自动调整下一轮策略
这使得 Agent 的讲解质量随着使用不断提升，不会重复同样的错误教法。"
```

---

## 5. GraphRAG 知识检索

### 5.1 核心思想

传统 RAG 只用向量相似度检索，GraphRAG 结合了**知识图谱的结构化关系**：
- 向量检索 → 找"语义相似"的内容
- 图谱遍历 → 找"关系关联"的内容（前置知识、相关知识点、应用场景）

### 5.2 在 MEM Coach 中的实现

```kotlin
class KnowledgeToolHandler {
    
    // GraphRAG 混合检索：向量 + 图谱
    suspend fun findSimilarQuestions(questionId: String, limit: Int = 5): List<Question> {
        val source = questionDao.getById(questionId)
        
        // 1. 向量检索：找语义相似的题
        val vectorResults = vectorIndex.search(
            queryEmbedding = source.embedding,
            topK = limit * 2 // 多取一些，后面融合会用
        )
        
        // 2. 图谱遍历：找同知识点及其前置/关联知识点的题
        val graphResults = knowledgeGraph.expand(
            nodeId = source.topic,
            depth = 1,  // 只展开一层
            edgeTypes = listOf(EdgeType.PREREQUISITE, EdgeType.RELATED)
        ).flatMap { node ->
            questionDao.searchByTopic(node.id)
        }
        
        // 3. 融合排序：向量分 + 图谱关联分
        return mergeAndRank(vectorResults, graphResults, limit)
    }
    
    // 加权融合
    private fun mergeAndRank(
        vector: List<ScoredQuestion>,
        graph: List<Question>,
        limit: Int
    ): List<Question> {
        val scores = mutableMapOf<String, Double>()
        
        // 向量相似度权重 0.6
        vector.forEach { scores[it.id] = (scores[it.id] ?: 0.0) + it.score * 0.6 }
        
        // 图谱关联权重 0.4
        graph.forEach { scores[it.id] = (scores[it.id] ?: 0.0) + 0.4 }
        
        return scores.entries
            .sortedByDescending { it.value }
            .take(limit)
            .map { questionDao.getById(it.key)!! }
    }
}
```

### 5.3 面试吹逼要点

```
"传统的 RAG 只做向量相似度检索，对于教育场景不够——
语义相似的题不一定是学生需要练的题。
我引入了 GraphRAG 混合检索：
- 向量层找语义相似
- 图谱层按知识点关系（前置、关联、应用）遍历
- 融合权重 6:4，确保推荐的题既有相似性又有学习价值"
```

---

## 6. 分层 LLM 路由（Model Router）

### 6.1 核心思想

不同复杂度的任务调用不同能力的模型，优化成本和质量：
- 简单任务（搜索、判断对错）→ 便宜模型
- 中等任务（知识点讲解）→ 中档模型
- 复杂任务（出题、批改、规划）→ 高端模型

### 6.2 实现

```kotlin
class AgentLlmRouter(
    private val config: ModelConfig
) {
    enum class Tier { FAST, STANDARD, PREMIUM }
    
    fun selectModel(toolName: String, contextComplexity: Int): String {
        return when {
            // 简单查询 → 便宜模型
            toolName in setOf("exam_question_search", "exam_answer_check",
                               "memorize_query", "exam_mastery_update") ->
                config.models[Tier.FAST]!!
            
            // 中等讲解 → 标准模型
            toolName in setOf("exam_question_explain", "knowledge_search",
                               "knowledge_graph_expand", "memorize_record") ->
                config.models[Tier.STANDARD]!!
            
            // 复杂生成 → 高端模型
            toolName in setOf("exam_mock_generate", "note_generate",
                               "study_plan_generate", "progress_analyze") ->
                config.models[Tier.PREMIUM]!!
            
            // 默认根据上下文复杂度决定
            else -> when {
                contextComplexity < 1000 -> config.models[Tier.FAST]!!
                contextComplexity < 4000 -> config.models[Tier.STANDARD]!!
                else -> config.models[Tier.PREMIUM]!!
            }
        }
    }
}
```

### 6.3 成本对比

| 模型 | 回答搜索 | 讲解题目 | 出模拟卷 |
|------|---------|---------|---------|
| GPT-4o (全部) | $0.01 | $0.10 | $0.30 |
| 分层路由 | $0.001 (GPT-4o-mini) | $0.02 (GPT-4o) | $0.30 (GPT-4o) |
| **节省** | **90%** | **80%** | 持平 |

### 6.4 面试吹逼要点

```
"我设计了分层 LLM 路由（Model Router），让 Agent 根据任务复杂度自动选择模型。
简单任务用 GPT-4o-mini（成本降低 90%），复杂任务仍然用 GPT-4o 保证质量。
这个设计在保证体验的前提下，将日均 LLM 成本从 $5 降到 $1。"
```

---

## 7. ToolHandler 插件化架构

### 7.1 核心思想

工具不是硬编码在 Agent 代码里，而是通过**接口 + 注册表**实现可插拔：

```kotlin
// 统一的工具接口
interface ToolHandler {
    val toolNames: Set<String>
    suspend fun execute(toolName: String, arguments: JsonObject): String
}

// 注册到路由器
class AgentToolRouter(
    private val handlers: List<ToolHandler>
) {
    private val handlerMap: Map<String, ToolHandler> = buildMap {
        for (handler in handlers) {
            for (name in handler.toolNames) {
                put(name, handler)
            }
        }
    }
    
    suspend fun execute(toolName: String, arguments: JsonObject): String {
        return handlerMap[toolName]?.execute(toolName, arguments)
            ?: """{"error": "unknown tool: $toolName"}"""
    }
}
```

### 7.2 注册示例

```kotlin
// 在 Application 初始化时注册
val toolRouter = AgentToolRouter(listOf(
    ExamToolHandler(questionDao, vectorSearch, masteryDao),
    KnowledgeToolHandler(knowledgeDao, graphDao),
    MemoryToolHandler(memoryDao),
    PDFToolHandler(pdfProcessor, ocrService)
))
```

### 7.3 面试吹逼要点

```
"工具系统采用了插件化架构（Plugin Architecture）：
- 每个 ToolHandler 是独立模块，定义自己的工具名称和执行逻辑
- 新增功能只需实现 ToolHandler 接口并注册，不影响已有代码
- 这遵循了开闭原则（OCP），也是 MCP 协议的核心思想"
```

---

## 8. 技术栈全景总结（面试速查表）

| 技术点 | 在本项目中的体现 | 面试关键词 |
|--------|-----------------|-----------|
| ReAct | AgentOrchestrator while(true) 循环 | "实现了生产级 ReAct Agent" |
| Plan-and-Execute | study_plan_generate + 逐日执行 | "Plan-and-Solve 范式的教育场景应用" |
| Self-Reflection | 每轮练习后的 Reflection 检查点 | "Agent 自我反思机制，持续优化教学策略" |
| GraphRAG | 向量+图谱混合检索 | "GraphRAG 混合检索，兼顾语义和结构化关联" |
| Model Router | AgentLlmRouter 分层路由 | "LLM 分层路由，成本降低 70-90%" |
| Plugin Architecture | ToolHandler 接口+注册表 | "插件化架构，工具可插拔" |
| State Machine | StudyStateMachine 7 状态 | "状态机驱动的学习流程编排" |
| SM-2 Algorithm | SpacedRepetition 间隔重复 | "记忆曲线算法的端侧实现" |
| MCP 兼容 | Function Calling JSON Schema | "工具定义兼容 OpenAI Function Calling 标准" |
