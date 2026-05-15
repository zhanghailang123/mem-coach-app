# MEM Coach - Skill 与 MCP 完整调用链路解析

> 本文档详细解析了 Skill（学习策略）与 MCP（模型上下文协议）在 MEM Coach（及 OpenOmniBot 架构）中的完整生命周期与调用链路。

## 1. 核心问题：只有在对话中才会调用吗？

**答案是：不只是在对话中。**

虽然用户在前端页面的“对话”是最常见的触发方式，但在当前架构下，Skill 和 MCP 的调用是由底层的 `AgentOrchestrator`（ReAct 核心引擎）驱动的。只要触发了 Agent 引擎，就可能调用它们。

常见的触发场景包括：
1. **主动对话 (Chat)**：用户在教练首页发送消息请求辅导。
2. **状态机驱动 (StateMachine)**：用户进入“复习模式”或“模考模式”时，系统后台自动向 Agent 发送隐式 Prompt（如：“请根据用户的薄弱点出 5 道题”），此时 Agent 会结合 Skill 出题，并可能调用 MCP 获取外部题库。
3. **后台管道 (Pipeline)**：例如在 `PdfPipelineService` 处理用户上传的 PDF 时，后台 Agent 会被唤醒，它可能会使用特定的“文档解析 Skill”来规范输出，并调用本地的 OCR 工具。
4. **自动化任务 (Automations)**：如每日生成学习总结（智能 Rollup），后台会自动触发 Agent。

---

## 2. 完整调用链路时序图

以下是 Skill 和 MCP 从初始化到最终被 LLM 调用的完整时序图：

```mermaid
sequenceDiagram
    participant UI as Flutter UI / Trigger
    participant DB as SQLite (Skill/Config)
    participant Router as AgentToolRouter
    participant MCP as RemoteMcpClient
    participant Prompt as AgentSystemPrompt
    participant Orch as AgentOrchestrator
    participant LLM as AgentLlmClient

    %% 阶段 1：MCP 工具发现与注册 (应用启动或配置更新时)
    rect rgb(240, 248, 255)
        Note over Router, MCP: 阶段 1：MCP 初始化与注册
        MCP ->> ExternalServer: GET /tools/list (获取远程工具)
        ExternalServer -->> MCP: 返回工具列表 (如 github_search)
        MCP ->> Router: 注册动态获取的 Tools
        Router -->> Orch: 工具库准备就绪
    end

    %% 阶段 2：Skill 加载与注入 (每次请求发起前)
    rect rgb(255, 240, 245)
        Note over UI, Prompt: 阶段 2：Skill 组装与注入
        UI ->> Orch: 发起请求 (对话/后台任务)
        Orch ->> DB: 查询当前激活的 Skill 列表
        DB -->> Orch: 返回 Skills (如 费曼技巧, 逻辑解析)
        Orch ->> Prompt: 将 Skills 注入系统提示词 (System Prompt)
        Prompt -->> Orch: 返回完整的 Context Messages
    end

    %% 阶段 3：核心 ReAct 循环 (执行阶段)
    rect rgb(240, 255, 240)
        Note over Orch, LLM: 阶段 3：Agent 核心循环 (ReAct)
        loop while (true) 达到最大轮数前
            Orch ->> LLM: streamTurn(Messages + 工具 JSON Schema)
            Note over LLM: LLM 结合 Skill 思考，决定是否调用工具
            
            alt 需要调用 MCP 工具
                LLM -->> Orch: 返回 ToolCall (name: github_search, args: {...})
                Orch ->> Router: execute(toolName, args)
                Router ->> MCP: 路由到对应的 MCP Client
                MCP ->> ExternalServer: POST /tools/call
                ExternalServer -->> MCP: 返回外部数据
                MCP -->> Router: 返回执行结果
                Router -->> Orch: 结果封装为 Observation
                Orch ->> Orch: 将结果追加到 Messages，进入下一轮循环
            else 不需要调用工具 (完成任务)
                LLM -->> Orch: 返回纯文本 (Final Answer)
                Note over LLM: LLM 运用 Skill 中的教学模板格式化输出
                Orch -->> UI: 返回最终结果
                break 结束循环
            end
        end
    end
```

---

## 3. 链路核心节点源码级解析

### 3.1 阶段一：MCP 的挂载 (手脚的延伸)
在应用启动（`MainActivity.kt`）或用户在“MCP 管理页面”添加新服务器时，系统会初始化 `RemoteMcpClient`。
```kotlin
// 1. 初始化 MCP 客户端
val mcpClient = RemoteMcpClient("http://localhost:8080")
mcpClient.initialize() // 内部向远程服务器请求工具列表

// 2. 注册到全局路由
val toolRouter = AgentToolRouter(listOf(
    ExamToolHandler(),
    mcpClient // MCP 提供的工具和本地原生工具被同等对待
))
```

### 3.2 阶段二：Skill 的注入 (大脑的武装)
每次 `AgentOrchestrator.run()` 被调用时，不管是前端对话还是后台定时任务，都会先组装上下文。
```kotlin
// AgentPromptContext.kt 或 AgentSystemPrompt.kt
fun buildSystemPrompt(activeSkills: List<StudySkill>): String {
    var prompt = "你是 MEM Coach，一个专业的考研教练。\n"
    
    // 动态注入 Skill
    if (activeSkills.isNotEmpty()) {
        prompt += "请严格遵循以下教学策略（Skills）：\n"
        activeSkills.forEach { skill ->
            prompt += "- 【${skill.name}】: ${skill.instruction}\n"
        }
    }
    return prompt
}
```

### 3.3 阶段三：ReAct 循环中的协同
在 `AgentOrchestrator` 的 `while(true)` 循环中，Skill 和 MCP 发生了奇妙的化学反应：
1. **LLM 接收指令**：大模型收到了包含 **Skill（费曼技巧）** 的 System Prompt，以及包含 **MCP（github_search）** 的可用工具列表。
2. **LLM 决策**：大模型分析用户请求（比如“找点资料讲讲微积分”），发现自己缺资料，于是输出一个工具调用请求。
3. **Android 执行**：`AgentToolRouter` 拦截到工具调用，发现属于 MCP，于是通过 HTTP 发送给外部服务器，拿到资料。
4. **LLM 融合**：大模型拿到了 MCP 返回的冰冷资料，**此时 Skill 发挥作用**，大模型严格按照 Skill 要求的“费曼技巧”模板，将资料转化为通俗易懂的对话输出给用户。

## 4. 总结

在 MEM Coach (OpenOmniBot 架构) 中：
* **Skill 和 MCP 的调用是解耦的**。
* **触发是全局的**：不仅限于聊天框，后台任务、状态机流转均可触发整条链路。
* **MCP 负责“获取数据”（输入），Skill 负责“规范逻辑与表达”（处理与输出）**。两者在 `AgentOrchestrator` 的 ReAct 循环中完美闭环。