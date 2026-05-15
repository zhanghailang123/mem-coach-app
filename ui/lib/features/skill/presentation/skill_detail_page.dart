import 'package:flutter/material.dart';
import '../domain/study_skill.dart';
import '../data/skill_repository.dart';

/// Skill 详情页面
/// 
/// 显示 Skill 的详细信息，包括描述、支持场景、核心指令等
class SkillDetailPage extends StatefulWidget {
  final StudySkill skill;
  
  const SkillDetailPage({
    super.key,
    required this.skill,
  });
  
  @override
  State<SkillDetailPage> createState() => _SkillDetailPageState();
}

class _SkillDetailPageState extends State<SkillDetailPage> {
  final SkillRepository _repository = SkillRepository();
  late StudySkill _skill;
  
  @override
  void initState() {
    super.initState();
    _skill = widget.skill;
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_skill.name),
        actions: [
          IconButton(
            icon: Icon(_skill.isEnabled ? Icons.toggle_on : Icons.toggle_off),
            onPressed: () => _toggleSkill(!_skill.isEnabled),
            tooltip: _skill.isEnabled ? '禁用' : '启用',
          ),
          if (!_skill.isBuiltin)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteSkill,
              tooltip: '删除',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            _buildInfoSection(),
            const SizedBox(height: 24),
            _buildScenesSection(),
            const SizedBox(height: 24),
            _buildToolsSection(),
            const SizedBox(height: 24),
            _buildInstructionsSection(),
            if (_skill.successPatterns.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildPatternsSection('成功模式', _skill.successPatterns, Colors.green),
            ],
            if (_skill.failurePatterns.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildPatternsSection('失败模式', _skill.failurePatterns, Colors.red),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: _skill.isEnabled
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                  child: Icon(
                    _getSkillIcon(),
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _skill.name,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _skill.description,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfoChip('优先级', '${_skill.priority}/10'),
                _buildInfoChip('类型', _skill.isBuiltin ? '内置' : '自定义'),
                _buildInfoChip('状态', _skill.isEnabled ? '已启用' : '已禁用'),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildInfoChip(String label, String value) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Text(
          label[0],
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
      label: Text('$label: $value'),
    );
  }
  
  Widget _buildInfoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '基本信息',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _buildInfoRow('ID', _skill.id),
            _buildInfoRow('名称', _skill.name),
            _buildInfoRow('描述', _skill.description),
            _buildInfoRow('优先级', '${_skill.priority}/10'),
            _buildInfoRow('类型', _skill.isBuiltin ? '内置策略' : '用户自定义'),
            _buildInfoRow('状态', _skill.isEnabled ? '已启用' : '已禁用'),
            if (_skill.createdAt != null)
              _buildInfoRow('创建时间', _skill.createdAt.toString()),
            if (_skill.updatedAt != null)
              _buildInfoRow('更新时间', _skill.updatedAt.toString()),
          ],
        ),
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
  
  Widget _buildScenesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '支持场景',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _skill.supportedScenes.map((scene) {
                return Chip(
                  avatar: Icon(
                    _getSceneIcon(scene),
                    size: 18,
                  ),
                  label: Text(scene.displayName),
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildToolsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '推荐工具',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (_skill.toolPreferences.isEmpty)
              const Text('无特定推荐工具')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _skill.toolPreferences.map((tool) {
                  return Chip(
                    avatar: const Icon(Icons.build, size: 18),
                    label: Text(tool),
                    backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildInstructionsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '核心指令',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Text(
                _skill.instructions,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildPatternsSection(String title, List<String> patterns, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Column(
              children: patterns.map((pattern) {
                return ListTile(
                  leading: Icon(
                    Icons.check_circle,
                    color: color,
                    size: 20,
                  ),
                  title: Text(pattern),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
  
  IconData _getSkillIcon() {
    if (_skill.id.contains('logic')) {
      return Icons.psychology;
    } else if (_skill.id.contains('writing')) {
      return Icons.edit;
    } else if (_skill.id.contains('spaced')) {
      return Icons.repeat;
    } else if (_skill.id.contains('weakness')) {
      return Icons.analytics;
    } else {
      return Icons.lightbulb;
    }
  }
  
  IconData _getSceneIcon(StudyScene scene) {
    switch (scene) {
      case StudyScene.problemSolving:
        return Icons.edit_note;
      case StudyScene.conceptExplain:
        return Icons.school;
      case StudyScene.errorAnalysis:
        return Icons.error_outline;
      case StudyScene.reviewPlanning:
        return Icons.calendar_today;
      case StudyScene.memorization:
        return Icons.psychology;
      case StudyScene.mockExam:
        return Icons.quiz;
      case StudyScene.weaknessAnalysis:
        return Icons.analytics;
    }
  }
  
  Future<void> _toggleSkill(bool enabled) async {
    final success = await _repository.setSkillEnabled(_skill.id, enabled);
    if (success) {
      setState(() {
        _skill = _skill.copyWith(isEnabled: enabled);
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(enabled ? '已启用 ${_skill.name}' : '已禁用 ${_skill.name}'),
          ),
        );
      }
    }
  }
  
  Future<void> _deleteSkill() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除策略 "${_skill.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final success = await _repository.deleteUserSkill(_skill.id);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除 ${_skill.name}')),
        );
        Navigator.pop(context);
      }
    }
  }
}