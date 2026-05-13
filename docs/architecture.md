# MEM Coach - 项目架构设计文档

> 版本：MVP v0.1.0 | 日期：2026-05-11 | 作者：个人项目

---

## 1. 项目概述

MEM Coach 是一个面向 MEM（工程管理硕士）考生的 AI Agent 学习应用。核心定位为「AI 教练驱动」的备考工具，帮助在职考生在有限时间内高效过线。项目同时作为 AI Agent 前沿技术的学习实践平台。

### 1.1 目标用户

| 特征 | 描述 | 设计含义 |
|------|------|----------|
| 在职备考 | 白天上班，碎片化学习 | 支持 3-30 分钟片段学习 |
| 毕业多年 | 基础遗忘严重 | 需要"从零唤醒" |
| 年龄 28-40 | 理解力强，记忆力下降 | 少背诵，多理解，重方法 |
| 目标务实 | 过线即可 (~170/300) | 强调"性价比"路径 |

### 1.2 核心差异化

```
传统备考 App：视频课 → 题库 → 模考 → 死记解析（被动接受）
MEM Coach：  真题入库 → AI 诊断 → 精准推送 → 分步讲解 → 变式巩固（主动解决薄弱点）
```

---

## 2. 系统架构

### 2.1 整体架构图

```
┌────────────────────────────────────────────────────┐
│                   Flutter UI Layer                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐         │
│  │ 教练首页  │  │ 学情看板  │  │ 知识库   │         │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘         │
│       │              │              │                │
│       └──────────────┼──────────────┘                │
│                      │ MethodChannel                 │
├──────────────────────┼──────────────────────────────┤
│                      ▼                               │
│              Agent Orchestration Layer               │
│  ┌───────────────────────────────────────────┐     │
│  │  AgentOrchestrator (ReAct Loop)            │     │
│  │  ┌─────────┐  ┌──────────┐  ┌──────────┐ │     │
│  │  │StateMachine│  │ToolRouter│  │LLMRouter│ │     │
│  │  └─────────┘  └──────────┘  └──────────┘ │     │
│  └───────────────────────────────────────────┘     │
│                      │                               │
├──────────────────────┼──────────────────────────────┤
│                      ▼                               │
│                 Tool Handlers Layer                  │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐      │
│  │ExamHandler │ │KnowledgeH  │ │MemoryH     │      │
│  │真题搜索/讲解│ │知识图谱    │ │学情记忆    │      │
│  └────────────┘ └────────────┘ └────────────┘      │
│  ┌────────────┐                                     │
│  │PDFHandler  │                                     │
│  │PDF上传/OCR │                                     │
│  └────────────┘                                     │
│                      │                               │
├──────────────────────┼──────────────────────────────┤
│                      ▼                               │
│                 AI & Data Layer                      │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐           │
│  │LLM Client │ │SQLite/Room│ │ML Kit   │           │
│  │分层路由   │ │4张核心表  │ │OCR      │           │
│  └──────────┘ └──────────┘ └──────────┘           │
│  ┌──────────┐ ┌──────────┐                          │
│  │向量索引   │ │MMKV      │                          │
│  │JSON索引   │ │键值存储   │                          │
│  └──────────┘ └──────────┘                          │
└────────────────────────────────────────────────────┘
```

### 2.2 模块依赖关系

```
app (Android Application)
├── agent/         # Agent 编排核心
│   ├── AgentOrchestrator   # ReAct 主循环
│   ├── AgentSystemPrompt   # Prompt 注入
│   ├── AgentLlmClient      # LLM 调用
│   ├── AgentLlmRouter      # 分层路由
│   └── tool/
│       ├── AgentToolRouter
│       ├── AgentToolDefinitions
│       └── handlers/        # 4 个 ToolHandler
├── statemachine/   # 学习状态机
├── data/           # Room 数据库 + DAO
├── ocr/            # ML Kit OCR
├── pdf/            # PDF 处理
├── vector/         # 向量索引
├── memorization/   # 间隔重复算法
├── channel/        # Flutter 通信
└── config/         # 模型配置

ui/ (Flutter Module)
├── features/
│   ├── coach/      # 教练首页 (对话流+卡片)
│   ├── insight/    # 学情看板
│   └── knowledge/  # 知识库
└── shared/
    ├── models/     # 共享数据模型
    ├── services/   # Agent 通信服务
    └── theme/      # Cyberpunk Academia 主题
```

---

## 3. 核心设计决策

### 3.1 为什么复用 OpenOmniBot 架构

| 组件 | OpenOmniBot 实现 | 复用方式 |
|------|-----------------|----------|
| AgentOrchestrator | while(true) 多轮工具调用 | 直接复用框架，改造为 ReAct 模式 |
| ToolHandler 接口 | plugin 式工具注册 | 复用接口定义和路由机制 |
| OCR | ML Kit text-recognition-chinese | 直接复用 OcrUtil 封装 |
| 记忆系统 | WorkspaceMemoryService | 改造为学情记忆三层架构 |
| ChannelManager | Flutter-Native 通信 | 复用 MethodChannel 模式 |
| StateMachine | 任务状态机 | 改造为 7 个学习状态 |

### 3.2 为何选择端侧 SQLite 而非云端数据库

- 个人自用，数据量小（几百道题），SQLite 完全够用
- 隐私考虑——学习记录、错题数据留在手机本地
- 离线可用——地铁上没网也能做题
- 后期可通过 Room 的 Migration 机制平滑升级

### 3.3 向量检索：JSON 索引 → sqlite-vec 的演进路径

| 阶段 | 方案 | 适用规模 |
|------|------|----------|
| MVP (当前) | JSON 索引 + 余弦相似度 | < 1000 题 |
| V1.5 | sqlite-vec 扩展 | < 10000 题 |
| V2.0 | 支持元数据过滤的向量检索 | 全量 |

### 3.4 前端：为什么选 Flutter

- OpenOmniBot 已验证 Flutter + Kotlin 混合架构
- 一套代码跑 Android，后续可扩展到 iOS
- Riverpod 状态管理，GoRouter 路由——成熟稳定
- Material Design 3 组件库，快速出 UI

---

## 4. 数据模型

### 4.1 ER 图

```
exam_questions (真题)         knowledge_nodes (知识点)
┌──────────────┐            ┌──────────────┐
│ id (PK)      │            │ id (PK)      │
│ year         │            │ name         │
│ subject      │◄───────────│ subject      │
│ chapter      │   topic    │ chapter      │
│ topic        │            │ parent_id (FK)│
│ type         │            │ description  │
│ stem         │            │ exam_frequency│
│ options      │            └──────┬───────┘
│ answer       │                   │
│ explanation  │          knowledge_edges (关系)
│ source_file  │          ┌──────────────┐
│ embedding    │          │ from_id (FK) │
└──────┬───────┘          │ to_id (FK)   │
       │                  │ type         │
       │                  └──────────────┘
study_records (记录)       user_mastery (掌握度)
┌──────────────┐          ┌──────────────┐
│ id (PK)      │          │ user_id      │
│ question_id  │          │ knowledge_id │
│ user_answer  │          │ mastery_level│
│ is_correct   │          │ review_count │
│ time_spent   │          │ next_review  │
│ study_mode   │          └──────────────┘
└──────────────┘
```

### 4.2 关键查询场景

```
场景1: "找 2023 年逻辑的条件推理题"
  → SELECT * FROM exam_questions
    WHERE year=2023 AND subject='logic' AND topic='conditional_inference'

场景2: "我的薄弱点 TOP 5"
  → SELECT * FROM user_mastery
    ORDER BY mastery_level ASC LIMIT 5

场景3: "今天该复习哪些知识点"
  → SELECT * FROM user_mastery
    WHERE next_review_date <= :now

场景4: "找和这道题语义相似的题"
  → 向量余弦相似度 Top-K + WHERE topic 过滤
```

---

## 5. 安全与配置

### 5.1 LLM API Key 管理（关键！）

```
开发阶段：gradle.properties / 环境变量注入
  → buildConfigField("String", "LLM_API_KEY", "\"${System.getenv("LLM_API_KEY")}\"")

发布阶段：自建代理服务
  用户 App → 后端代理 → LLM API
  API Key 只存后端，App 用用户 token 认证
```

### 5.2 签名配置

```
release {
    storeFile = file("mem-coach-release.jks")
    storePassword = System.getenv("KEYSTORE_PASSWORD")
    keyAlias = "mem-coach"
    keyPassword = System.getenv("KEY_PASSWORD")
}
```

---

## 6. 项目目录结构

```
mem-coach-app/
├── app/                              # Android 原生模块
│   ├── build.gradle.kts
│   └── src/main/java/cn/com/memcoach/
│       ├── App.kt                    # Application 入口
│       ├── MainActivity.kt           # Flutter 桥接
│       ├── agent/                    # Agent 核心
│       │   ├── AgentOrchestrator.kt
│       │   ├── AgentSystemPrompt.kt
│       │   ├── AgentLlmClient.kt
│       │   ├── AgentLlmRouter.kt
│       │   └── tool/
│       │       ├── AgentToolRouter.kt
│       │       ├── AgentToolDefinitions.kt
│       │       └── handlers/
│       │           ├── ToolHandler.kt
│       │           ├── ExamToolHandler.kt
│       │           ├── KnowledgeToolHandler.kt
│       │           ├── MemoryToolHandler.kt
│       │           └── PDFToolHandler.kt
│       ├── statemachine/
│       │   └── StudyStateMachine.kt
│       ├── data/
│       │   ├── AppDatabase.kt
│       │   ├── dao/
│       │   │   ├── ExamQuestionDao.kt
│       │   │   ├── KnowledgeNodeDao.kt
│       │   │   ├── UserMasteryDao.kt
│       │   │   └── StudyRecordDao.kt
│       │   └── entity/
│       │       ├── ExamQuestion.kt
│       │       ├── KnowledgeNode.kt
│       │       ├── KnowledgeEdge.kt
│       │       ├── UserMastery.kt
│       │       └── StudyRecord.kt
│       ├── ocr/OcrService.kt
│       ├── pdf/PDFProcessor.kt
│       ├── vector/VectorIndexService.kt
│       ├── memorization/SpacedRepetition.kt
│       ├── channel/ChannelManager.kt
│       └── config/ModelConfig.kt
├── ui/                               # Flutter UI 模块
│   └── lib/
│       ├── main.dart
│       ├── app.dart
│       └── features/
│           ├── coach/                # 教练首页
│           │   ├── pages/coach_page.dart
│           │   └── widgets/
│           │       ├── agent_greeting.dart
│           │       ├── question_card.dart
│           │       ├── reasoning_chain_card.dart
│           │       ├── memorize_card.dart
│           │       ├── note_card.dart
│           │       ├── progress_card.dart
│           │       └── quick_actions.dart
│           ├── insight/              # 学情看板
│           └── knowledge/            # 知识库
├── docs/                             # 文档
│   ├── architecture.md
│   ├── agent_patterns.md
│   └── prompt_engineering.md
├── build.gradle.kts
├── settings.gradle.kts
└── gradle.properties
```

---

## 7. MVP 里程碑

| 周 | 里程碑 | 关键产出 |
|----|--------|----------|
| W1 | 项目脚手架 + 数据库 | Flutter 项目结构、Room 数据库、核心实体 |
| W2 | PDF 识别 Pipeline | PDF → OCR → LLM 结构化 → 入库 |
| W3 | Agent 工具框架 | ExamToolHandler、AgentToolRouter 集成 |
| W4 | 逐题练习 + 答案检查 | 做题卡片、分步讲解、掌握度更新 |
| W5 | 相似题 + 模拟组卷 | 向量检索、组卷算法 |
| W6 | 背诵学习 + 知识图谱 | SM-2 间隔重复、图谱数据结构 |
| W7 | Flutter UI 联调 | 教练首页、学情页、知识库页 |
| W8 | 内测 + 修复 | 端到端测试、Bug 修复 |
