import 'package:flutter/material.dart';
import '../domain/study_skill.dart';
import '../data/skill_repository.dart';
import 'skill_detail_page.dart';
import 'skill_store_page.dart';

/// Skill 管理页面
/// 
/// 显示所有已安装的 Skill，支持启用/禁用、查看详情、删除等操作
class SkillManagementPage extends StatefulWidget {
  const SkillManagementPage({super.key});
  
  @override
  State<SkillManagementPage> createState() => _SkillManagementPageState();
}

class _SkillManagementPageState extends State<SkillManagementPage> {
  final SkillRepository _repository = SkillRepository();
  List<StudySkill> _builtinSkills = [];
  List<StudySkill> _userSkills = [];
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _loadSkills();
  }
  
  Future<void> _loadSkills() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final builtinSkills = await _repository.getBuiltinSkills();
      final userSkills = await _repository.getUserSkills();
      
      setState(() {
        _builtinSkills = builtinSkills;
        _userSkills = userSkills;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载 Skill 失败: $e')),
        );
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('学习策略管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.store),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SkillStorePage(),
                ),
              );
            },
            tooltip: '策略商店',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSkills,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadSkills,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  _buildSectionHeader('内置策略', Icons.extension),
                  const SizedBox(height: 8),
                  _buildSkillList(_builtinSkills, isBuiltin: true),
                  const SizedBox(height: 24),
                  _buildSectionHeader('自定义策略', Icons.build),
                  const SizedBox(height: 8),
                  _buildSkillList(_userSkills, isBuiltin: false),
                  const SizedBox(height: 16),
                  _buildAddCustomSkillButton(),
                ],
              ),
            ),
    );
  }
  
  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
  
  Widget _buildSkillList(List<StudySkill> skills, {required bool isBuiltin}) {
    if (skills.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: Text(
              isBuiltin ? '暂无内置策略' : '暂无自定义策略',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey,
              ),
            ),
          ),
        ),
      );
    }
    
    return Column(
      children: skills.map((skill) => _buildSkillCard(skill)).toList(),
    );
  }
  
  Widget _buildSkillCard(StudySkill skill) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: skill.isEnabled
              ? Theme.of(context).colorScheme.primary
              : Colors.grey,
          child: Icon(
            _getSkillIcon(skill),
            color: Colors.white,
          ),
        ),
        title: Text(
          skill.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: skill.isEnabled ? null : Colors.grey,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              skill.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: skill.sceneNames.take(3).map((scene) {
                return Chip(
                  label: Text(
                    scene,
                    style: const TextStyle(fontSize: 10),
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: skill.isEnabled,
              onChanged: (value) => _toggleSkill(skill, value),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios),
              onPressed: () => _showSkillDetail(skill),
            ),
          ],
        ),
        onTap: () => _showSkillDetail(skill),
      ),
    );
  }
  
  IconData _getSkillIcon(StudySkill skill) {
    if (skill.id.contains('logic')) {
      return Icons.psychology;
    } else if (skill.id.contains('writing')) {
      return Icons.edit;
    } else if (skill.id.contains('spaced')) {
      return Icons.repeat;
    } else if (skill.id.contains('weakness')) {
      return Icons.analytics;
    } else {
      return Icons.lightbulb;
    }
  }
  
  Future<void> _toggleSkill(StudySkill skill, bool enabled) async {
    final success = await _repository.setSkillEnabled(skill.id, enabled);
    if (success) {
      setState(() {
        final index = _builtinSkills.indexWhere((s) => s.id == skill.id);
        if (index != -1) {
          _builtinSkills[index] = skill.copyWith(isEnabled: enabled);
        }
        
        final userIndex = _userSkills.indexWhere((s) => s.id == skill.id);
        if (userIndex != -1) {
          _userSkills[userIndex] = skill.copyWith(isEnabled: enabled);
        }
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(enabled ? '已启用 ${skill.name}' : '已禁用 ${skill.name}'),
          ),
        );
      }
    }
  }
  
  void _showSkillDetail(StudySkill skill) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SkillDetailPage(skill: skill),
      ),
    );
  }
  
  Widget _buildAddCustomSkillButton() {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: ListTile(
        leading: const Icon(Icons.add_circle_outline),
        title: const Text('添加自定义策略'),
        subtitle: const Text('创建自己的学习策略'),
        onTap: () {
          // TODO: 实现添加自定义 Skill 功能
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('自定义策略功能即将推出')),
          );
        },
      ),
    );
  }
}