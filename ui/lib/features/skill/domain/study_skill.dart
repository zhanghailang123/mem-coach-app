/// 学习场景枚举
enum StudyScene {
  /// 解题场景："这道题怎么做"、"帮我解这道逻辑题"
  problemSolving,
  
  /// 概念讲解："什么是假言推理"、"解释一下这个概念"
  conceptExplain,
  
  /// 错题分析："我为什么做错了"、"分析一下这道错题"
  errorAnalysis,
  
  /// 复习规划："帮我制定复习计划"、"安排一下本周复习"
  reviewPlanning,
  
  /// 背诵辅助："帮我背诵这个公式"、"记忆这个知识点"
  memorization,
  
  /// 模拟考试："给我出一套模拟题"、"进行一次模拟测试"
  mockExam,
  
  /// 薄弱点分析："我哪里比较薄弱"、"分析我的弱项"
  weaknessAnalysis,
}

/// 学习场景扩展方法
extension StudySceneExtension on StudyScene {
  /// 获取场景的中文显示名称
  String get displayName {
    switch (this) {
      case StudyScene.problemSolving:
        return '解题模式';
      case StudyScene.conceptExplain:
        return '概念讲解';
      case StudyScene.errorAnalysis:
        return '错题分析';
      case StudyScene.reviewPlanning:
        return '复习规划';
      case StudyScene.memorization:
        return '背诵辅助';
      case StudyScene.mockExam:
        return '模拟考试';
      case StudyScene.weaknessAnalysis:
        return '薄弱点分析';
    }
  }
  
  /// 获取场景的图标名称
  String get iconName {
    switch (this) {
      case StudyScene.problemSolving:
        return 'edit_note';
      case StudyScene.conceptExplain:
        return 'school';
      case StudyScene.errorAnalysis:
        return 'error_outline';
      case StudyScene.reviewPlanning:
        return 'calendar_today';
      case StudyScene.memorization:
        return 'psychology';
      case StudyScene.mockExam:
        return 'quiz';
      case StudyScene.weaknessAnalysis:
        return 'analytics';
    }
  }
}

/// 学习 Skill 数据模型
class StudySkill {
  /// Skill 唯一标识符，如 "logic-problem-solving"
  final String id;
  
  /// Skill 名称，如 "逻辑解题策略"
  final String name;
  
  /// 简短描述
  final String description;
  
  /// 支持的学习场景列表
  final List<StudyScene> supportedScenes;
  
  /// 优先级（1-10），数值越高优先级越高
  final int priority;
  
  /// 核心指令，将注入到 system prompt 中
  final String instructions;
  
  /// 偏好使用的工具列表
  final List<String> toolPreferences;
  
  /// 成功模式列表（用于学习优化）
  final List<String> successPatterns;
  
  /// 失败模式列表（用于避免和改进）
  final List<String> failurePatterns;
  
  /// 是否启用
  final bool isEnabled;
  
  /// 是否为内置 Skill
  final bool isBuiltin;
  
  /// 创建时间
  final DateTime? createdAt;
  
  /// 更新时间
  final DateTime? updatedAt;
  
  const StudySkill({
    required this.id,
    required this.name,
    required this.description,
    required this.supportedScenes,
    required this.priority,
    required this.instructions,
    this.toolPreferences = const [],
    this.successPatterns = const [],
    this.failurePatterns = const [],
    this.isEnabled = true,
    this.isBuiltin = true,
    this.createdAt,
    this.updatedAt,
  });
  
  /// 从 JSON 创建 StudySkill
  factory StudySkill.fromJson(Map<String, dynamic> json) {
    return StudySkill(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      supportedScenes: (json['supportedScenes'] as List<dynamic>)
          .map((e) => StudyScene.values.firstWhere(
                (scene) => scene.name == e,
                orElse: () => StudyScene.problemSolving,
              ))
          .toList(),
      priority: json['priority'] as int,
      instructions: json['instructions'] as String,
      toolPreferences: (json['toolPreferences'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      successPatterns: (json['successPatterns'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      failurePatterns: (json['failurePatterns'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      isEnabled: json['isEnabled'] as bool? ?? true,
      isBuiltin: json['isBuiltin'] as bool? ?? true,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
    );
  }
  
  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'supportedScenes': supportedScenes.map((e) => e.name).toList(),
      'priority': priority,
      'instructions': instructions,
      'toolPreferences': toolPreferences,
      'successPatterns': successPatterns,
      'failurePatterns': failurePatterns,
      'isEnabled': isEnabled,
      'isBuiltin': isBuiltin,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
  
  /// 复制并修改部分属性
  StudySkill copyWith({
    String? id,
    String? name,
    String? description,
    List<StudyScene>? supportedScenes,
    int? priority,
    String? instructions,
    List<String>? toolPreferences,
    List<String>? successPatterns,
    List<String>? failurePatterns,
    bool? isEnabled,
    bool? isBuiltin,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StudySkill(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      supportedScenes: supportedScenes ?? this.supportedScenes,
      priority: priority ?? this.priority,
      instructions: instructions ?? this.instructions,
      toolPreferences: toolPreferences ?? this.toolPreferences,
      successPatterns: successPatterns ?? this.successPatterns,
      failurePatterns: failurePatterns ?? this.failurePatterns,
      isEnabled: isEnabled ?? this.isEnabled,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
  
  /// 计算与指定场景的匹配度
  double calculateSceneMatchScore(StudyScene scene) {
    if (supportedScenes.contains(scene)) {
      // 基础匹配度 + 优先级加成
      return 0.7 + (priority / 10.0) * 0.3;
    }
    return 0.0;
  }
  
  /// 获取场景名称列表
  List<String> get sceneNames {
    return supportedScenes.map((scene) => scene.displayName).toList();
  }
  
  /// 获取工具偏好显示文本
  String get toolPreferencesText {
    if (toolPreferences.isEmpty) return '无';
    return toolPreferences.map((tool) => '`$tool`').join('、');
  }
}

/// Skill 匹配结果
class StudySkillMatchResult {
  /// 匹配到的 Skill
  final StudySkill skill;
  
  /// 匹配置信度（0.0 - 1.0）
  final double confidence;
  
  /// 触发原因描述
  final String triggerReason;
  
  const StudySkillMatchResult({
    required this.skill,
    required this.confidence,
    required this.triggerReason,
  });
  
  /// 从 JSON 创建 StudySkillMatchResult
  factory StudySkillMatchResult.fromJson(Map<String, dynamic> json) {
    return StudySkillMatchResult(
      skill: StudySkill.fromJson(json['skill'] as Map<String, dynamic>),
      confidence: (json['confidence'] as num).toDouble(),
      triggerReason: json['triggerReason'] as String,
    );
  }
  
  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'skill': skill.toJson(),
      'confidence': confidence,
      'triggerReason': triggerReason,
    };
  }
}