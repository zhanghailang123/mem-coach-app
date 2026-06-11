## 真题数据为空排查

### 可能原因

1. **数据库预加载未触发**
   - `DatabasePreloader` 只在首次创建时执行
   - 如果数据库已存在，不会重新加载

2. **查询条件问题**
   - ExamToolHandler 的 `search` 方法可能需要调整默认值

3. **DAO 查询条件过滤太严格**
   - `parse_status = 'parsed'` 但导入数据是 `'imported'`

### 快速修复

#### 方案1：修复 DAO 默认值（推荐）
修改 `ExamQuestionDao.kt`：
```kotlin
parseStatus: String? = null,  // 改为 null，不过滤
minConfidence: Float = 0.0f,  // 改为 0，不过滤
```

#### 方案2：修复导入数据的 parse_status
修改 `migrate_code199_data.py`，将：
```python
'imported'
```
改为：
```python
'parsed'
```

#### 方案3：临时验证
在 Android Studio 的 Database Inspector 中查看：
- 打开 `mem_coach.db`
- 查看 `exam_questions` 表
- 检查是否有 799 条数据

### 建议操作

1. 卸载 App 重装（清除旧数据库）
2. 查看 Logcat 过滤 "DatabasePreloader"
3. 检查是否输出 "成功预加载 799 道真题"
