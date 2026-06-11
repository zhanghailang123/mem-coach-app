# code-199 数据迁移记录

## 迁移概况

**迁移时间**: 2026-06-11  
**源项目**: D:\newIDeaProject\code-199  
**目标项目**: D:\newIDeaProject\mem-coach-app  

---

## 📊 数据统计

### 总体情况
- **总题数**: 799 道
- **覆盖年份**: 2012-2025 年（14 年真题）
- **数据库大小**: 4.5 MB

### 按科目分布
| 科目 | 题数 | 占比 |
|------|------|------|
| 逻辑 (logic) | 421 | 52.7% |
| 数学 (math) | 350 | 43.8% |
| 写作 (writing) | 28 | 3.5% |

### 按年份分布
每年稳定：
- 数学：25 道
- 逻辑：30 道  
- 写作：2 道

---

## 🔧 迁移方案

### 1. 数据格式转换
**源格式**: Markdown + YAML Frontmatter
```yaml
---
id: 2012-logic-q26
subject: logic
difficulty: 3
knowledge_points: [削弱题, 类比论证]
tags: [论证逻辑, 易错题]
---

## 题目
...
```

**目标格式**: SQLite (Room)
```sql
CREATE TABLE exam_questions (
    id TEXT PRIMARY KEY,
    year INTEGER,
    subject TEXT,
    section TEXT,
    stem TEXT,
    options TEXT,
    answer TEXT,
    explanation TEXT,
    ...
)
```

### 2. 字段映射

| code-199 | mem-coach-app | 说明 |
|----------|---------------|------|
| `id` | `id` | 直接映射 |
| `subject` | `subject` | 直接映射 (logic/math/writing) |
| - | `year` | 从 ID 提取 (2012-2025) |
| - | `section` | 从 knowledge_points[0] 提取 |
| - | `question_number` | 从 ID 提取 (q26 → 26) |
| `type` | `type` | choice/essay 等 |
| `difficulty` | `difficulty` | 1-5 难度值 |
| `knowledge_points` | `knowledge_points` | JSON 数组 |
| `tags` | `tags` | JSON 数组 |
| `source` | `source` | 来源描述 |

### 3. 迁移脚本
**位置**: `scripts/migrate_code199_data.py`

**功能**:
- 解析 Markdown 文件
- 提取 YAML frontmatter
- 分离题干、选项、答案、解析
- 写入 SQLite 数据库

**执行命令**:
```bash
python scripts/migrate_code199_data.py
```

**结果**: 
- ✅ 成功: 799 道
- ❌ 失败: 0 道

---

## 🚀 集成方案

### 1. 数据库预加载

**文件**: `app/src/main/assets/exam_questions.db`  
**大小**: 4.5 MB

**预加载器**: `DatabasePreloader.kt`
```kotlin
class DatabasePreloader(context: Context) : RoomDatabase.Callback() {
    override fun onCreate(db: SupportSQLiteDatabase) {
        // 首次创建时从 assets 复制预置数据
        preloadExamQuestions(db)
    }
}
```

### 2. DAO 查询支持

`ExamQuestionDao` 已支持：
- ✅ 按年份查询: `getByYearAndSubject(2023, "logic")`
- ✅ 按科目查询: `searchByTopic("logic", "削弱题")`
- ✅ 多维搜索: `search(subject, section, year, difficulty, limit)`
- ✅ 批量获取: `getByIds(listOf("2012-logic-q26", ...))`

### 3. ExamToolHandler 工具

已实现工具：
- `exam_question_search` - 搜索真题
- `exam_question_explain` - 获取详解
- `exam_answer_check` - 检查答案
- `exam_similar_find` - 查找相似题
- `exam_mastery_update` - 更新掌握度
- `exam_mock_generate` - 生成模拟卷

---

## 📝 验证结果

### 数据完整性
```
按年份和科目统计:
年份       科目         题数    
------------------------------
2012     logic      30    
2012     math       25    
2012     writing    2     
...
2025     logic      30    
2025     math       25    
2025     writing    2     

总计: 799 道题
```

### 示例题目
```
[1] ID: 2012-logic-q26
    科目: logic | 年份: 2012
    题干: 1991年6月15日，菲律宾吕宋岛上的皮纳图博火山突然大喷发...
```

---

## 🎯 下一步计划

### 短期（已完成）
- [x] 数据库预加载
- [x] DAO 查询优化
- [x] ExamToolHandler 集成

### 中期
- [ ] 知识点图谱迁移
- [ ] 学习路径 (curriculum) 迁移
- [ ] 题目集合 (collections) 迁移
- [ ] 英语专项数据迁移

### 长期
- [ ] 题目向量化索引
- [ ] 相似题推荐优化
- [ ] 用户做题记录分析

---

## 📖 参考文件

- 迁移脚本: `scripts/migrate_code199_data.py`
- 验证脚本: `scripts/verify_db.py`
- 数据库文件: `app/src/main/assets/exam_questions.db`
- 预加载器: `app/src/main/java/cn/com/memcoach/data/DatabasePreloader.kt`
- DAO: `app/src/main/java/cn/com/memcoach/data/dao/ExamQuestionDao.kt`
- 工具处理器: `app/src/main/java/cn/com/memcoach/agent/tool/handlers/ExamToolHandler.kt`
