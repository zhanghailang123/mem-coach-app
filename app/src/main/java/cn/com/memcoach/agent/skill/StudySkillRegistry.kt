package cn.com.memcoach.agent.skill

import android.content.Context
import java.io.File

/**
 * 学习 Skill 注册表
 * 
 * 管理所有可用的学习 Skill，包括内置 Skill 和用户自定义 Skill
 * 提供 Skill 的注册、查询、启用/禁用等功能
 */
class StudySkillRegistry(
    private val context: Context,
    private val skillsDir: File? = null
) {
    /** 内置 Skill 存储 */
    private val builtinSkills = mutableMapOf<String, StudySkill>()
    
    /** 用户自定义 Skill 存储 */
    private val userSkills = mutableMapOf<String, StudySkill>()
    
    /** Skill 加载器 */
    private val loader = StudySkillLoader()
    
    init {
        // 初始化时加载内置 Skill
        registerBuiltinSkills()
        
        // 如果指定了用户 Skill 目录，加载用户 Skill
        if (skillsDir != null) {
            loadUserSkills(skillsDir)
        }
    }
    
    /**
     * 注册内置 Skill
     */
    private fun registerBuiltinSkills() {
        // 1. 逻辑解题策略
        registerBuiltinSkill(StudySkill(
            id = "logic-problem-solving",
            name = "逻辑解题策略",
            description = "针对逻辑推理题的解题策略和技巧，帮助快速识别题型、应用正确逻辑规则",
            supportedScenes = listOf(StudyScene.PROBLEM_SOLVING, StudyScene.ERROR_ANALYSIS),
            priority = 8,
            instructions = """
## 逻辑解题策略

### 解题步骤
1. **识别题型**：假言推理、直言推理、削弱加强、假设支持等
2. **提取逻辑关系**：找出前提和结论之间的逻辑连接词
3. **应用规则**：根据题型应用对应的逻辑规则
4. **验证答案**：检查答案是否符合逻辑规则

### 常见题型及技巧

#### 假言推理
- **充分条件**：如果P则Q，P真则Q真，Q假则P假
- **必要条件**：只有P才Q，Q真则P真，P假则Q假
- **技巧**：画箭头图，明确方向性

#### 削弱加强题
- **削弱**：否定论点、否定论据、切断联系
- **加强**：肯定论点、补充论据、建立联系
- **技巧**：找准论点和论据的关系

#### 假设支持题
- **假设**：论点成立的必要条件
- **支持**：使论点更可能成立的条件
- **技巧**：取非验证法

### 常见错误模式
- 混淆必要条件和充分条件
- 忽略隐含前提
- 过度推理
- 偷换概念

### 工具使用建议
- 优先使用 `exam_question_search` 查找相似题型
- 使用 `knowledge_search` 查找相关逻辑规则
- 使用 `pdf_query` 查找教材中的讲解
""".trimIndent(),
            toolPreferences = listOf("exam_question_search", "knowledge_search", "pdf_query"),
            successPatterns = listOf("正确识别题型", "应用正确逻辑规则", "验证答案合理性"),
            failurePatterns = listOf("混淆必要充分条件", "忽略隐含前提", "过度推理", "偷换概念")
        ))

        // 1.5. 数学真题解题策略
        registerBuiltinSkill(StudySkill(
            id = "math-problem-solving",
            name = "数学真题解题策略",
            description = "针对管综数学真题的解题策略，覆盖条件充分性、排列组合、概率、几何、代数和应用题",
            supportedScenes = listOf(
                StudyScene.PROBLEM_SOLVING,
                StudyScene.CONCEPT_EXPLAIN,
                StudyScene.ERROR_ANALYSIS,
                StudyScene.MOCK_EXAM
            ),
            priority = 9,
            instructions = """
## 数学真题解题策略

### 解题总流程
1. **先确认题型**：区分“问题求解”和“条件充分性判断”。
2. **抽取已知量**：把题干中的数量关系、范围条件、图形关系写清楚。
3. **选择方法**：优先用考试中稳定、低计算量的方法。
4. **验证选项**：代入、排除、边界值、特殊值都可以作为快速检验。
5. **标记易错点**：讲清楚用户容易漏掉的隐含条件或计算陷阱。

### 条件充分性判断
- 先分别判断条件(1)、条件(2)是否单独充分。
- 如果都不单独充分，再判断二者联合是否充分。
- 注意“能推出唯一答案”才是充分，不是“看起来更接近答案”。
- 输出时明确对应 A/B/C/D/E 五种标准选项规则。

### 常见模块策略

#### 代数与方程
- 优先建立等式/不等式关系，注意取值范围。
- 遇到二次方程、根与系数关系时，检查判别式和正负条件。

#### 排列组合与概率
- 先判断是“分类加法”还是“分步乘法”。
- 对“至少/至多”优先考虑反面计数。
- 概率题先明确样本空间是否等可能。

#### 几何与解析几何
- 画图标注已知量，优先找相似、勾股、面积关系。
- 解析几何题注意斜率、距离、圆和直线位置关系。

#### 应用题
- 明确单位和变量含义，防止把比例、增长率、速度、效率混用。
- 优先列最小必要方程，避免过度设未知数。

### 公式与渲染要求
- 公式使用 LaTeX：行内用 `\(...\)`，块级用 `\[...\]`。
- 不要把公式写成纯文本截图式表达。
- 如果工具返回的原解析公式格式不清晰，可以建议 `propose_content_patch` 改进解析。

### 工具使用建议
- 优先使用 `exam_question_search` 搜索同年份、同题型或同知识点真题。
- 使用 `exam_question_explain` 获取题干、答案、解析和来源。
- 使用 `knowledge_search` 查找对应数学知识点。
- 深度讲解数学题时优先委派 `delegate_to_math_tutor`。
""".trimIndent(),
            toolPreferences = listOf(
                "exam_question_search",
                "exam_question_explain",
                "exam_similar_find",
                "knowledge_search",
                "delegate_to_math_tutor"
            ),
            successPatterns = listOf("准确区分题型", "列出关键数量关系", "验证条件充分性", "指出计算陷阱"),
            failurePatterns = listOf("忽略取值范围", "条件充分性判断顺序错误", "样本空间不清", "公式渲染不规范")
        ))
        
        // 2. 写作评分策略
        registerBuiltinSkill(StudySkill(
            id = "writing-essay-scoring",
            name = "写作评分策略",
            description = "论证有效性分析和论说文写作指导，帮助识别逻辑错误、提升写作质量",
            supportedScenes = listOf(StudyScene.PROBLEM_SOLVING, StudyScene.CONCEPT_EXPLAIN),
            priority = 7,
            instructions = """
## 写作评分策略

### 论证有效性分析

#### 评分要点
1. **逻辑错误识别**：找出论证中的逻辑漏洞
2. **错误类型分类**：以偏概全、因果倒置、类比不当等
3. **分析深度**：不仅要指出错误，还要分析为什么是错误
4. **改进建议**：给出如何改进论证的建议

#### 常见逻辑错误
- **以偏概全**：用个别案例推断整体
- **因果倒置**：混淆原因和结果
- **类比不当**：两个事物本质不同
- **非黑即白**：忽略中间状态
- **诉诸权威**：盲目相信权威观点
- **循环论证**：用结论证明前提

#### 分析模板
```
该论证存在以下问题：
1. [错误类型]：[具体分析]
2. [错误类型]：[具体分析]
...
因此，该论证的有效性值得商榷。
```

### 论说文写作

#### 评分标准
1. **审题立意**：准确理解题目要求
2. **结构规划**：总分总结构，论点清晰
3. **论据选择**：使用真实、有说服力的论据
4. **语言表达**：简洁、准确、有逻辑性

#### 写作模板
```
第一段：引出话题，提出中心论点
第二段：分论点1 + 论据 + 分析
第三段：分论点2 + 论据 + 分析
第四段：分论点3 + 论据 + 分析
第五段：总结升华，呼应开头
```

### 工具使用建议
- 使用 `exam_question_search` 查找历年真题范文
- 使用 `pdf_query` 查找写作技巧和评分标准
""".trimIndent(),
            toolPreferences = listOf("exam_question_search", "pdf_query"),
            successPatterns = listOf("准确识别逻辑错误", "分析深入透彻", "建议具体可行"),
            failurePatterns = listOf("分析表面化", "缺乏改进建议", "遗漏重要错误")
        ))
        
        // 3. 间隔重复策略
        registerBuiltinSkill(StudySkill(
            id = "spaced-repetition",
            name = "间隔重复策略",
            description = "基于遗忘曲线的科学记忆方法，帮助高效记忆公式、定理和知识点",
            supportedScenes = listOf(StudyScene.MEMORIZATION, StudyScene.REVIEW_PLANNING),
            priority = 6,
            instructions = """
## 间隔重复策略

### 核心原则
1. **主动回忆**：不要只是看，要尝试回忆
2. **间隔重复**：按照遗忘曲线安排复习
3. **测试效应**：通过测试加强记忆
4. **精细加工**：将新知识与已有知识联系

### 遗忘曲线规律
- **20分钟后**：遗忘42%
- **1小时后**：遗忘56%
- **1天后**：遗忘74%
- **1周后**：遗忘77%
- **1个月后**：遗忘79%

### 记忆间隔安排
```
第1次复习：学习后5分钟
第2次复习：学习后30分钟
第3次复习：学习后12小时
第4次复习：学习后1天
第5次复习：学习后2天
第6次复习：学习后4天
第7次复习：学习后7天
第8次复习：学习后15天
```

### 记忆技巧

#### 口诀记忆
将复杂内容编成口诀，如：
- 逻辑联结词："如果就，只有才，除非否则不"

#### 联想记忆
创建生动的联想图像，如：
- 充分条件→箭头（单向）
- 必要条件→双向箭头

#### 位置记忆法
将知识点放在熟悉的位置，如：
- 客厅：假言推理
- 卧室：直言推理
- 厨房：削弱加强

#### 故事记忆法
将知识点串联成故事，如：
- "小明如果努力学习（P），就能考上研究生（Q）"

### 工具使用建议
- 使用 `knowledge_search` 查找需要记忆的知识点
- 使用 `pdf_query` 查找记忆技巧和口诀
""".trimIndent(),
            toolPreferences = listOf("knowledge_search", "pdf_query"),
            successPatterns = listOf("主动回忆成功", "间隔复习规律", "应用记忆技巧"),
            failurePatterns = listOf("被动重复阅读", "复习间隔不当", "缺乏记忆策略")
        ))
        
        // 4. 薄弱点分析策略
        registerBuiltinSkill(StudySkill(
            id = "weakness-analysis",
            name = "薄弱点分析策略",
            description = "系统分析学习薄弱点，制定针对性改进计划，提升学习效率",
            supportedScenes = listOf(StudyScene.WEAKNESS_ANALYSIS, StudyScene.REVIEW_PLANNING),
            priority = 9,
            instructions = """
## 薄弱点分析策略

### 分析维度

#### 1. 知识点维度
- 哪些知识点掌握度低于60%？
- 哪些知识点错误率最高？
- 哪些知识点从未练习过？

#### 2. 题型维度
- 哪些题型错误率高？
- 哪些题型耗时过长？
- 哪些题型从未练习过？

#### 3. 时间维度
- 哪些时间段效率低？
- 哪些时间段容易分心？
- 哪些时间段适合学习新内容？

#### 4. 难度维度
- 哪个难度级别问题最多？
- 是否在某个难度级别停滞不前？
- 是否需要调整难度进阶策略？

### 分析方法

#### 错题分析法
1. 收集近期错题
2. 按知识点分类
3. 分析错误原因
4. 找出规律性错误

#### 正确率分析法
1. 统计各知识点正确率
2. 识别低于60%的知识点
3. 分析正确率低的原因
4. 制定提升计划

#### 时间分析法
1. 记录学习时间分布
2. 识别效率低下的时间段
3. 分析原因（疲劳、分心等）
4. 调整学习时间安排

### 改进策略

#### 针对性练习
- 针对薄弱知识点专项练习
- 每天至少练习10道相关题目
- 逐步提升难度

#### 错题重做
- 每周重做一次错题
- 分析错误原因是否改变
- 总结教训

#### 概念澄清
- 重新学习薄弱概念
- 查阅教材和参考资料
- 请教老师或同学

#### 技巧训练
- 针对薄弱题型训练解题技巧
- 学习快速解题方法
- 练习时间管理

### 工具使用建议
- 使用 `exam_question_search` 查找薄弱知识点的练习题
- 使用 `knowledge_search` 查找相关概念和规则
- 使用 `pdf_query` 查找学习方法和技巧
""".trimIndent(),
            toolPreferences = listOf("exam_question_search", "knowledge_search", "pdf_query"),
            successPatterns = listOf("准确识别薄弱点", "制定针对性计划", "持续跟踪改进"),
            failurePatterns = listOf("分析不全面", "计划不具体", "缺乏跟踪反馈")
        ))
    }
    
    /**
     * 注册内置 Skill
     * 
     * @param skill 要注册的 Skill
     */
    private fun registerBuiltinSkill(skill: StudySkill) {
        builtinSkills[skill.id] = skill
    }
    
    /**
     * 加载用户自定义 Skill
     * 
     * @param dir Skill 文件目录
     */
    private fun loadUserSkills(dir: File) {
        if (!dir.exists() || !dir.isDirectory) {
            return
        }
        
        dir.listFiles()?.forEach { file ->
            if (file.isFile && file.name.endsWith(".md")) {
                val content = loader.loadFromFile(file.absolutePath)
                if (content != null) {
                    val skill = loader.parseSkillFile(content)
                    if (skill != null) {
                        userSkills[skill.id] = skill
                    }
                }
            }
        }
    }
    
    /**
     * 注册用户自定义 Skill
     * 
     * @param skill 要注册的 Skill
     */
    fun registerUserSkill(skill: StudySkill) {
        userSkills[skill.id] = skill
    }
    
    /**
     * 获取所有已启用的 Skill
     * 
     * @return 已启用的 Skill 列表
     */
    fun getAllEnabledSkills(): List<StudySkill> {
        val allSkills = mutableListOf<StudySkill>()
        allSkills.addAll(builtinSkills.values.filter { it.isEnabled })
        allSkills.addAll(userSkills.values.filter { it.isEnabled })
        return allSkills
    }
    
    /**
     * 获取所有 Skill（包括禁用的）
     * 
     * @return 所有 Skill 列表
     */
    fun getAllSkills(): List<StudySkill> {
        val allSkills = mutableListOf<StudySkill>()
        allSkills.addAll(builtinSkills.values)
        allSkills.addAll(userSkills.values)
        return allSkills
    }
    
    /**
     * 根据 ID 获取 Skill
     * 
     * @param id Skill ID
     * @return Skill 对象，如果不存在返回 null
     */
    fun getSkill(id: String): StudySkill? {
        return builtinSkills[id] ?: userSkills[id]
    }
    
    /**
     * 启用/禁用 Skill
     * 
     * @param id Skill ID
     * @param enabled 是否启用
     * @return 是否操作成功
     */
    fun setSkillEnabled(id: String, enabled: Boolean): Boolean {
        val skill = getSkill(id) ?: return false
        
        val updatedSkill = skill.copy(isEnabled = enabled)
        
        if (skill.isBuiltin) {
            builtinSkills[id] = updatedSkill
        } else {
            userSkills[id] = updatedSkill
        }
        
        return true
    }
    
    /**
     * 删除用户自定义 Skill
     * 
     * @param id Skill ID
     * @return 是否删除成功
     */
    fun deleteUserSkill(id: String): Boolean {
        val skill = userSkills[id] ?: return false
        
        // 删除文件
        if (skillsDir != null) {
            val file = File(skillsDir, "${skill.name}.md")
            if (file.exists()) {
                file.delete()
            }
        }
        
        userSkills.remove(id)
        return true
    }
    
    /**
     * 保存用户自定义 Skill 到文件
     * 
     * @param skill 要保存的 Skill
     * @return 是否保存成功
     */
    fun saveUserSkill(skill: StudySkill): Boolean {
        if (skillsDir == null) {
            return false
        }
        
        if (!skillsDir.exists()) {
            skillsDir.mkdirs()
        }
        
        val file = File(skillsDir, "${skill.name}.md")
        
        val content = buildString {
            appendLine("---")
            appendLine("name: ${skill.name}")
            appendLine("description: ${skill.description}")
            appendLine("scenes: ${skill.supportedScenes.joinToString(",") { it.name }}")
            appendLine("priority: ${skill.priority}")
            appendLine("---")
            appendLine()
            append(skill.instructions)
        }
        
        return try {
            file.writeText(content)
            userSkills[skill.id] = skill
            true
        } catch (e: Exception) {
            false
        }
    }
    
    /**
     * 获取内置 Skill 列表
     * 
     * @return 内置 Skill 列表
     */
    fun getBuiltinSkills(): List<StudySkill> {
        return builtinSkills.values.toList()
    }
    
    /**
     * 获取用户自定义 Skill 列表
     * 
     * @return 用户自定义 Skill 列表
     */
    fun getUserSkills(): List<StudySkill> {
        return userSkills.values.toList()
    }
    
    /**
     * 检查 Skill 是否存在
     * 
     * @param id Skill ID
     * @return 是否存在
     */
    fun hasSkill(id: String): Boolean {
        return builtinSkills.containsKey(id) || userSkills.containsKey(id)
    }
    
    /**
     * 获取 Skill 数量统计
     * 
     * @return Map<类型, 数量>
     */
    fun getSkillCountStats(): Map<String, Int> {
        return mapOf(
            "total" to (builtinSkills.size + userSkills.size),
            "builtin" to builtinSkills.size,
            "user" to userSkills.size,
            "enabled" to getAllEnabledSkills().size,
            "disabled" to (getAllSkills().size - getAllEnabledSkills().size)
        )
    }
}
