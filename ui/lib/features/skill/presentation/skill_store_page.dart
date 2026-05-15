import 'package:flutter/material.dart';
import '../domain/study_skill.dart';
import '../data/skill_repository.dart';
import 'skill_detail_page.dart';

/// Skill 商店页面
/// 
/// 浏览和安装新的学习策略
class SkillStorePage extends StatefulWidget {
  const SkillStorePage({super.key});
  
  @override
  State<SkillStorePage> createState() => _SkillStorePageState();
}

class _SkillStorePageState extends State<SkillStorePage> {
  final SkillRepository _repository = SkillRepository();
  List<StudySkill> _availableSkills = [];
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _loadAvailableSkills();
  }
  
  Future<void> _loadAvailableSkills() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // 目前只显示内置 Skill，后续可以扩展为从远程 API 获取
      final builtinSkills = await _repository.getBuiltinSkills();
      
      setState(() {
        _availableSkills = builtinSkills;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载策略商店失败: $e')),
        );
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('策略商店'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: 实现搜索功能
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('搜索功能即将推出')),
              );
            },
            tooltip: '搜索',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAvailableSkills,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAvailableSkills,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 16),
                  _buildCategorySection('推荐策略', _availableSkills.take(3).toList()),
                  const SizedBox(height: 24),
                  _buildCategorySection('全部策略', _availableSkills),
                ],
              ),
            ),
    );
  }
  
  Widget _buildHeader() {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '发现学习策略',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '浏览和安装各种学习策略，提升学习效率',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCategorySection(String title, List<StudySkill> skills) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (skills.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  '暂无可用策略',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
                ),
              ),
            ),
          )
        else
          Column(
            children: skills.map((skill) => _buildSkillCard(skill)).toList(),
          ),
      ],
    );
  }
  
  Widget _buildSkillCard(StudySkill skill) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Icon(
            _getSkillIcon(skill),
            color: Colors.white,
          ),
        ),
        title: Text(
          skill.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
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
            Row(
              children: [
                Icon(Icons.star, size: 16, color: Colors.amber),
                const SizedBox(width: 4),
                Text('${skill.priority}/10'),
                const SizedBox(width: 16),
                Icon(Icons.category, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text('${skill.supportedScenes.length} 个场景'),
              ],
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.arrow_forward_ios),
          onPressed: () => _showSkillDetail(skill),
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
  
  void _showSkillDetail(StudySkill skill) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SkillDetailPage(skill: skill),
      ),
    );
  }
}