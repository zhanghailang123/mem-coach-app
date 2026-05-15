import 'package:flutter/material.dart';

import '../../../core/native/mem_coach_native_bridge.dart';
import '../../coach/presentation/practice_page.dart';

class KnowledgePage extends StatefulWidget {
  const KnowledgePage({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<KnowledgePage> createState() => _KnowledgePageState();
}

class _KnowledgePageState extends State<KnowledgePage> {
  late int _selectedTab;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('知识库'),
        actions: [
          IconButton(
            onPressed: () => _uploadFile(context),
            icon: const Icon(Icons.upload_file_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _SegmentTabs(
            selected: _selectedTab,
            onChanged: (value) => setState(() => _selectedTab = value),
          ),
          const SizedBox(height: 16),
          if (_selectedTab == 0) const _FileGroupSection(),
          if (_selectedTab == 1) const _KnowledgeTreeSection(),
          if (_selectedTab == 2) const _MemorizeSection(),
        ],
      ),
    );
  }

  Future<void> _uploadFile(BuildContext context) async {
    // 复用已有的 PDF 上传逻辑
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('请在首页使用"上传真题"功能')),
    );
  }
}

class _SegmentTabs extends StatelessWidget {
  const _SegmentTabs({
    required this.selected,
    required this.onChanged,
  });

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: 0, label: Text('真题')),
        ButtonSegment(value: 1, label: Text('图谱')),
        ButtonSegment(value: 2, label: Text('背诵')),
      ],
      selected: {selected},
      onSelectionChanged: (values) => onChanged(values.first),
    );
  }
}

/// 真题文件列表区域
class _FileGroupSection extends StatefulWidget {
  const _FileGroupSection();

  @override
  State<_FileGroupSection> createState() => _FileGroupSectionState();
}

class _FileGroupSectionState extends State<_FileGroupSection> {
  List<Map<String, dynamic>> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _loading = true);
    try {
      final files = await MemCoachNativeBridge.listPdfs();
      if (mounted) {
        setState(() {
          _files = files;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _deleteFile(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('确定要删除 "$name" 吗？这将同时清理手机存储。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await MemCoachNativeBridge.deletePdf(id);
        _loadFiles(); // 重新加载列表
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _KbCard(
      title: '真题文件',
      child: _loading
          ? const Center(child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ))
          : _files.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('暂无真题文件，请先上传 PDF', style: TextStyle(color: Colors.black54)),
                )
              : Column(
                  children: _files.map((f) {
                    final name = f['file_name']?.toString() ?? '未命名';
                    final pageCount = f['page_count']?.toString() ?? '?';
                    final subject = f['subject']?.toString();
                    final year = f['year']?.toString();

                    final id = f['id']?.toString() ?? '';

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFEF476F)),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('$pageCount 页${subject != null ? ' · $subject' : ''}${year != null ? ' · $year' : ''}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.black38),
                        onPressed: () => _deleteFile(id, name),
                      ),
                      onTap: () {
                        // 跳转到练习页面，练习该文件的题目
                        PracticePage.navigate(
                          context,
                          title: name,
                          subject: subject ?? 'logic',
                          count: 5,
                        );
                      },
                    );
                  }).toList(),
                ),
    );
  }
}

/// 知识图谱区域
class _KnowledgeTreeSection extends StatefulWidget {
  const _KnowledgeTreeSection();

  @override
  State<_KnowledgeTreeSection> createState() => _KnowledgeTreeSectionState();
}

class _KnowledgeTreeSectionState extends State<_KnowledgeTreeSection> {
  List<Map<String, dynamic>> _nodes = [];
  bool _loading = true;
  String _subject = 'logic';

  @override
  void initState() {
    super.initState();
    _loadTree();
  }

  Future<void> _loadTree() async {
    try {
      final nodes = await MemCoachNativeBridge.getKnowledgeTree(subject: _subject);
      if (mounted) {
        setState(() {
          _nodes = nodes;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _KbCard(
      title: '逻辑知识树',
      child: _loading
          ? const Center(child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ))
          : _nodes.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('暂无知识图谱数据', style: TextStyle(color: Colors.black54)),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _nodes.map((node) {
                    final level = node['level'] as int? ?? 0;
                    final name = node['name']?.toString() ?? '';
                    final examFreq = node['exam_frequency'] as int? ?? 0;

                    return Padding(
                      padding: EdgeInsets.only(left: level * 20.0, bottom: 10),
                      child: Row(
                        children: [
                          Icon(
                            level == 0 ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                            size: 18,
                            color: level == 0 ? Theme.of(context).colorScheme.primary : Colors.black38,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(
                                fontWeight: level == 0 ? FontWeight.w900 : FontWeight.w600,
                              ),
                            ),
                          ),
                          if (examFreq > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '考频 $examFreq',
                                style: const TextStyle(fontSize: 11, color: Colors.orange),
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
    );
  }
}

/// 背诵学习区域
class _MemorizeSection extends StatefulWidget {
  const _MemorizeSection();

  @override
  State<_MemorizeSection> createState() => _MemorizeSectionState();
}

class _MemorizeSectionState extends State<_MemorizeSection> {
  int _dueCount = 0;
  int _totalCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      // 通过 Native Bridge 获取背诵统计
      // 暂时使用模拟数据，后续可添加专门的 bridge 方法
      setState(() {
        _dueCount = 5;
        _totalCount = 12;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _KbCard(
      title: '背诵学习',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ))
          else ...[
            Text(
              '🔴 待背 $_dueCount 条   🟡 复习 $_totalCount 条',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  // 开始背诵 - 导航到背诵模式
                  PracticePage.navigate(
                    context,
                    title: '背诵模式',
                    subject: 'logic',
                    count: _dueCount > 0 ? _dueCount : 5,
                  );
                },
                child: const Text('开始背诵'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 通用知识库卡片
class _KbCard extends StatelessWidget {
  const _KbCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
