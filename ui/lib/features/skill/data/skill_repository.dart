import 'dart:convert';
import 'package:flutter/services.dart';
import '../domain/study_skill.dart';

/// Skill 数据仓库
/// 
/// 负责从本地资源或远程 API 获取 Skill 数据
class SkillRepository {
  /// 内置 Skill 列表
  List<StudySkill>? _builtinSkills;
  
  /// 用户自定义 Skill 列表
  List<StudySkill>? _userSkills;
  
  /// 获取所有内置 Skill
  Future<List<StudySkill>> getBuiltinSkills() async {
    if (_builtinSkills != null) {
      return _builtinSkills!;
    }
    
    try {
      // 从 assets 加载内置 Skill
      final List<StudySkill> skills = [];
      
      // 加载逻辑解题策略
      final logicSkill = await _loadSkillFromAsset('assets/skills/logic-problem-solving.md');
      if (logicSkill != null) {
        skills.add(logicSkill);
      }
      
      // 加载写作评分策略
      final writingSkill = await _loadSkillFromAsset('assets/skills/writing-essay-scoring.md');
      if (writingSkill != null) {
        skills.add(writingSkill);
      }
      
      // 加载间隔重复策略
      final spacedSkill = await _loadSkillFromAsset('assets/skills/spaced-repetition.md');
      if (spacedSkill != null) {
        skills.add(spacedSkill);
      }
      
      // 加载薄弱点分析策略
      final weaknessSkill = await _loadSkillFromAsset('assets/skills/weakness-analysis.md');
      if (weaknessSkill != null) {
        skills.add(weaknessSkill);
      }
      
      _builtinSkills = skills;
      return skills;
    } catch (e) {
      print('加载内置 Skill 失败: $e');
      return [];
    }
  }
  
  /// 从 assets 加载单个 Skill
  Future<StudySkill?> _loadSkillFromAsset(String assetPath) async {
    try {
      final content = await rootBundle.loadString(assetPath);
      return _parseSkillFile(content);
    } catch (e) {
      print('加载 Skill 文件失败 $assetPath: $e');
      return null;
    }
  }
  
  /// 解析 Skill 文件内容
  StudySkill? _parseSkillFile(String content) {
    final lines = content.split('\n');
    if (lines.isEmpty || lines[0].trim() != '---') {
      return null;
    }
    
    final frontmatterEnd = lines.indexOf('---', 1);
    if (frontmatterEnd <= 0) {
      return null;
    }
    
    final frontmatterLines = lines.sublist(1, frontmatterEnd);
    final bodyLines = lines.sublist(frontmatterEnd + 1);
    
    // 解析 frontmatter
    final frontmatter = <String, String>{};
    for (final line in frontmatterLines) {
      final colonIndex = line.indexOf(':');
      if (colonIndex > 0) {
        final key = line.substring(0, colonIndex).trim();
        final value = line.substring(colonIndex + 1).trim();
        frontmatter[key] = value;
      }
    }
    
    // 提取字段
    final name = frontmatter['name'];
    if (name == null || name.isEmpty) {
      return null;
    }
    
    final description = frontmatter['description'] ?? '';
    final scenesStr = frontmatter['scenes'] ?? '';
    final priorityStr = frontmatter['priority'] ?? '5';
    
    // 解析场景
    final scenes = scenesStr.split(',').map((sceneStr) {
      switch (sceneStr.trim().toUpperCase()) {
        case 'PROBLEM_SOLVING':
          return StudyScene.problemSolving;
        case 'CONCEPT_EXPLAIN':
          return StudyScene.conceptExplain;
        case 'ERROR_ANALYSIS':
          return StudyScene.errorAnalysis;
        case 'REVIEW_PLANNING':
          return StudyScene.reviewPlanning;
        case 'MEMORIZATION':
          return StudyScene.memorization;
        case 'MOCK_EXAM':
          return StudyScene.mockExam;
        case 'WEAKNESS_ANALYSIS':
          return StudyScene.weaknessAnalysis;
        default:
          return StudyScene.problemSolving;
      }
    }).toList();
    
    // 解析优先级
    final priority = int.tryParse(priorityStr) ?? 5;
    
    // 提取正文
    final body = bodyLines.join('\n').trim();
    
    return StudySkill(
      id: name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-'),
      name: name,
      description: description,
      supportedScenes: scenes,
      priority: priority,
      instructions: body,
      isEnabled: true,
      isBuiltin: true,
    );
  }
  
  /// 获取所有用户自定义 Skill
  Future<List<StudySkill>> getUserSkills() async {
    if (_userSkills != null) {
      return _userSkills!;
    }
    
    // TODO: 从本地存储或远程 API 获取用户自定义 Skill
    // 目前返回空列表
    _userSkills = [];
    return _userSkills!;
  }
  
  /// 获取所有已启用的 Skill
  Future<List<StudySkill>> getAllEnabledSkills() async {
    final builtinSkills = await getBuiltinSkills();
    final userSkills = await getUserSkills();
    
    final allSkills = <StudySkill>[];
    allSkills.addAll(builtinSkills.where((skill) => skill.isEnabled));
    allSkills.addAll(userSkills.where((skill) => skill.isEnabled));
    
    return allSkills;
  }
  
  /// 根据 ID 获取 Skill
  Future<StudySkill?> getSkillById(String id) async {
    final allSkills = await getAllEnabledSkills();
    return allSkills.where((skill) => skill.id == id).firstOrNull;
  }
  
  /// 根据场景获取推荐的 Skill
  Future<List<StudySkill>> getRecommendedSkills(StudyScene scene) async {
    final allSkills = await getAllEnabledSkills();
    
    // 过滤支持该场景的 Skill
    final matchingSkills = allSkills.where((skill) {
      return skill.supportedScenes.contains(scene);
    }).toList();
    
    // 按优先级排序
    matchingSkills.sort((a, b) => b.priority.compareTo(a.priority));
    
    // 返回前 3 个
    return matchingSkills.take(3).toList();
  }
  
  /// 启用/禁用 Skill
  Future<bool> setSkillEnabled(String id, bool enabled) async {
    // TODO: 实现 Skill 启用/禁用功能
    // 需要更新本地存储或调用远程 API
    return false;
  }
  
  /// 保存用户自定义 Skill
  Future<bool> saveUserSkill(StudySkill skill) async {
    // TODO: 实现用户自定义 Skill 保存功能
    // 需要保存到本地存储或调用远程 API
    return false;
  }
  
  /// 删除用户自定义 Skill
  Future<bool> deleteUserSkill(String id) async {
    // TODO: 实现用户自定义 Skill 删除功能
    // 需要从本地存储或调用远程 API 删除
    return false;
  }
  
  /// 清除缓存
  void clearCache() {
    _builtinSkills = null;
    _userSkills = null;
  }
}