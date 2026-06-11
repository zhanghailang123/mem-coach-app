# 真题库功能实现

## 📱 UI 结构设计

### 1. 底部导航（4个Tab）
```
┌─────────────────────────────────────┐
│  AI教练  |  真题  |  学情  |  知识  │
└─────────────────────────────────────┘
```

### 2. 真题库页面（3个Tab）

#### Tab 1: 按年份
```
┌─────────────────────────┐
│ [数学] [逻辑] [写作]      │  ← 科目筛选
├─────────────────────────┤
│ ┌───────────────────┐   │
│ │ 2025  2025年真题   │   │
│ │       30道逻辑题   │   │
│ └───────────────────┘   │
│ ┌───────────────────┐   │
│ │ 2024  2024年真题   │   │
│ └───────────────────┘   │
└─────────────────────────┘
```

#### Tab 2: 错题本
```
┌─────────────────────────┐
│ 错 3/5                   │  ← 错误次数/总次数
│ 1991年6月15日，菲律宾...  │  ← 题干预览
└─────────────────────────┘
```

#### Tab 3: 收藏
```
待实现
```

---

## 🎯 页面流程

### 流程1：按年份刷题
```
真题库 → 选择科目 → 选择年份 → 题目列表 → 题目详情 → 答题 → 自动记录
```

### 流程2：错题本复习
```
真题库 → 错题本Tab → 选择题目 → 题目详情 → 重新答题 → 连续2次对 → 移出错题本
```

---

## 🔧 核心组件

### 1. ExamBankPage（真题库首页）
- 3个Tab切换
- 科目筛选（数学/逻辑/写作）
- 年份卡片列表（2012-2025）
- 错题本列表

### 2. QuestionListPage（题目列表）
- 显示指定年份+科目的所有题
- 题目预览卡片
- 点击进入详情

### 3. QuestionDetailPage（题目详情）
- 题干展示
- 选项选择（单选）
- 提交答案按钮
- 答案和解析展示
- **自动调用 `answer_submit` 记录答题**

---

## 📊 数据流

### 查询真题
```dart
await MemCoachNativeBridge.callAgentTool('exam_question_search', {
  'subject': 'logic',
  'year': 2023,
  'limit': 100,
});
```

### 获取题目详情
```dart
await MemCoachNativeBridge.callAgentTool('exam_question_explain', {
  'question_id': '2023-logic-q26',
});
```

### 提交答题记录
```dart
await MemCoachNativeBridge.callAgentTool('answer_submit', {
  'question_id': '2023-logic-q26',
  'user_answer': 'B',
  'correct_answer': 'E',
  'is_correct': false,
});
```

### 获取错题本
```dart
await MemCoachNativeBridge.callAgentTool('wrong_book_list', {
  'limit': 50,
});
```

---

## ✅ 已实现功能

### 数据层
- [x] 799道真题（SQLite）
- [x] 答题记录（AnswerRecord）
- [x] 错题本查询（SQL聚合）

### Agent工具
- [x] exam_question_search - 搜索真题
- [x] exam_question_explain - 获取详情
- [x] answer_submit - 提交答题
- [x] wrong_book_list - 错题本

### UI层
- [x] ExamBankPage - 真题库首页
- [x] QuestionListPage - 题目列表
- [x] QuestionDetailPage - 题目详情
- [x] 底部导航集成

---

## 🚀 下一步

### Phase 1: 完善细节
- [ ] 编译测试
- [ ] 优化UI样式
- [ ] 添加加载状态

### Phase 2: 增强功能
- [ ] 收藏功能
- [ ] 做题进度条
- [ ] 答题计时器
- [ ] 分享错题

### Phase 3: 题目集合
- [ ] 自定义题集
- [ ] 模拟考试
- [ ] 专项练习
