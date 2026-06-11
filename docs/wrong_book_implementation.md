## 错题本功能实现完成

### 已实现

#### 1. 数据层
- ✅ `AnswerRecord` 实体 - 答题记录
- ✅ `WrongQuestion` 聚合视图 - 错题统计
- ✅ `AnswerRecordDao` - 数据访问
- ✅ 数据库升级到 v8

#### 2. Agent 工具
- ✅ `wrong_book_list` - 获取错题本
- ✅ `answer_submit` - 提交答题
- ✅ `study_stats` - 学习统计

### 核心逻辑

#### 错题判定
```sql
-- 至少做错1次 且 最近2次未连续正确
wrongCount > 0 AND (最近2次连续正确) = false
```

#### 掌握判定
```sql
-- 最近2次连续答对 → 移出错题本
SELECT is_correct FROM answer_records
WHERE question_id = ?
ORDER BY created_at DESC LIMIT 2
-- 如果都是 true，则 isMastered = true
```

### 使用示例

#### Agent 调用
```json
// 提交答题
{
  "tool": "answer_submit",
  "arguments": {
    "question_id": "2023-logic-q26",
    "user_answer": "B",
    "correct_answer": "E",
    "is_correct": false,
    "time_spent": 120
  }
}

// 查询错题本
{
  "tool": "wrong_book_list",
  "arguments": {"limit": 20}
}

// 今日统计
{
  "tool": "study_stats",
  "arguments": {}
}
```

#### Kotlin 调用
```kotlin
// 保存答题记录
answerRecordDao.insert(
    AnswerRecord(
        questionId = "2023-logic-q26",
        userAnswer = "B",
        correctAnswer = "E",
        isCorrect = false,
        timeSpent = 120
    )
)

// 获取错题本
val wrongQuestions = answerRecordDao.getWrongBook()
```

### 下一步

需要注册 `WrongBookToolHandler` 到 `AgentToolRouter`。
