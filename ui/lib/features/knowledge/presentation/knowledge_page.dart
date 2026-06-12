import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/native/mem_coach_native_bridge.dart';
import '../../../core/widgets/markdown_math.dart';
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
        padding:
            const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 100),
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
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final result = await MemCoachNativeBridge.deletePdf(id);
        _loadFiles(); // 重新加载列表
        if (mounted) {
          final deletedCount = result['deleted_question_count'] ?? 0;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已删除文件，并清理 $deletedCount 道关联真题')),
          );
        }
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
          ? const Center(
              child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ))
          : _files.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('暂无真题文件，请先上传 PDF',
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      )),
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
                      leading: const Icon(Icons.picture_as_pdf_rounded,
                          color: Color(0xFFEF476F)),
                      title: Text(name,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                          '$pageCount 页${subject != null ? ' · $subject' : ''}${year != null ? ' · $year' : ''}'),
                      trailing: IconButton(
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.38),
                        ),
                        onPressed: () => _deleteFile(id, name),
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PdfQuestionManagementPage(
                              documentId: id,
                              title: name,
                            ),
                          ),
                        );
                      },
                    );
                  }).toList(),
                ),
    );
  }
}

class PdfQuestionManagementPage extends StatefulWidget {
  const PdfQuestionManagementPage({
    super.key,
    required this.documentId,
    required this.title,
  });

  final String documentId;
  final String title;

  @override
  State<PdfQuestionManagementPage> createState() =>
      _PdfQuestionManagementPageState();
}

class _PdfQuestionManagementPageState extends State<PdfQuestionManagementPage> {
  List<Map<String, dynamic>> _questions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    setState(() => _loading = true);
    try {
      final questions =
          await MemCoachNativeBridge.listPdfQuestions(widget.documentId);
      if (mounted) {
        setState(() {
          _questions = questions;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载真题失败: $e')),
        );
      }
    }
  }

  Future<void> _deleteQuestions() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除关联真题'),
        content: Text('确定删除 "${widget.title}" 已解析出的全部真题吗？PDF 文件本身会保留。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除真题', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      final result =
          await MemCoachNativeBridge.deletePdfQuestions(widget.documentId);
      await _loadQuestions();
      if (mounted) {
        final deletedCount = result['deleted_question_count'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除 $deletedCount 道真题')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除真题失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: _questions.isEmpty ? null : _deleteQuestions,
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: '删除关联真题',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _questions.isEmpty
              ? const Center(child: Text('暂无从该 PDF 解析出的真题'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _questions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final question = _questions[index];
                    final number = question['question_number']?.toString();
                    final stem = question['stem']?.toString() ?? '';
                    final page = question['source_page']?.toString() ?? '-';
                    final status = question['parse_status']?.toString() ?? '';
                    final confidence = question['parse_confidence'];
                    return _KbCard(
                      title: number == null || number == 'null'
                          ? '第 ${index + 1} 题'
                          : '第 $number 题',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MarkdownMathPreview(
                            data: stem,
                            maxLines: 3,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              height: 1.5,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.87),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ..._buildOptionTexts(question['options']?.toString())
                              .map(
                            (option) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: MarkdownMathPreview(
                                data: option,
                                maxLines: 2,
                                style: TextStyle(
                                  height: 1.45,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.87),
                                ),
                              ),
                            ),
                          ),
                          const Divider(height: 24),
                          Wrap(
                            spacing: 10,
                            runSpacing: 6,
                            children: [
                              _MetaChip(label: '页码 $page'),
                              if (status.isNotEmpty) _MetaChip(label: status),
                              if (confidence != null)
                                _MetaChip(label: '置信度 $confidence'),
                            ],
                          ),
                          if ((question['answer']?.toString() ?? '')
                              .isNotEmpty) ...[
                            const SizedBox(height: 10),
                            MarkdownMathPreview(
                              data: '答案：${question['answer']}',
                              maxLines: 2,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.87),
                              ),
                            ),
                          ],
                          if ((question['explanation']?.toString() ?? '')
                              .isNotEmpty) ...[
                            const SizedBox(height: 8),
                            MarkdownMathPreview(
                              data: '解析：${question['explanation']}',
                              maxLines: 3,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.87),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  List<String> _buildOptionTexts(String? rawOptions) {
    if (rawOptions == null || rawOptions.isEmpty || rawOptions == '{}')
      return const [];
    try {
      final decoded = jsonDecode(rawOptions);
      if (decoded is Map) {
        return decoded.entries
            .map((entry) => '${entry.key}. ${entry.value}')
            .toList();
      }
    } catch (_) {}
    return [rawOptions];
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.6),
          )),
    );
  }
}

String _cleanText(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text == 'null') return '';
  return text;
}

int _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _subjectLabel(String subject) {
  return switch (subject) {
    'math' => '数学',
    'writing' => '写作',
    'english' => '英语',
    _ => '逻辑',
  };
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
  String? _error;
  String _subject = 'logic';
  String _query = '';
  Timer? _searchDebounce;
  final TextEditingController _searchController = TextEditingController();

  static const _subjects = [
    _KnowledgeSubject('logic', '逻辑', Icons.account_tree_outlined),
    _KnowledgeSubject('math', '数学', Icons.functions_rounded),
    _KnowledgeSubject('writing', '写作', Icons.edit_note_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _loadNodes();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNodes() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await MemCoachNativeBridge.callAgentTool(
        'knowledge_search',
        {
          'subject': _subject,
          'keyword': _query,
          'limit': 120,
        },
      );
      final error = result['error']?.toString();
      if (error != null && error.isNotEmpty && error != 'null') {
        throw Exception(error);
      }
      final rawNodes = result['knowledge_nodes'];
      final nodes = rawNodes is List
          ? rawNodes
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
          : <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          _nodes = nodes;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  void _changeSubject(String subject) {
    if (_subject == subject) return;
    setState(() => _subject = subject);
    _loadNodes();
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      final query = value.trim();
      if (_query == query) return;
      _query = query;
      _loadNodes();
    });
  }

  @override
  Widget build(BuildContext context) {
    return _KbCard(
      title: '${_subjectLabel(_subject)}知识点',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<String>(
            segments: _subjects
                .map(
                  (subject) => ButtonSegment<String>(
                    value: subject.id,
                    icon: Icon(subject.icon, size: 18),
                    label: Text(subject.label),
                  ),
                )
                .toList(),
            selected: {_subject},
            onSelectionChanged: (values) => _changeSubject(values.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: '搜索${_subjectLabel(_subject)}知识点',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchController.clear();
                        _searchDebounce?.cancel();
                        _query = '';
                        _loadNodes();
                      },
                    ),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null)
            _KnowledgeEmptyState(
              icon: Icons.error_outline_rounded,
              text: '加载失败：$_error',
              action: IconButton(
                onPressed: _loadNodes,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: '重试',
              ),
            )
          else if (_nodes.isEmpty)
            const _KnowledgeEmptyState(
              icon: Icons.search_off_rounded,
              text: '没有匹配的知识点',
            )
          else
            _buildNodeList(),
        ],
      ),
    );
  }

  Widget _buildNodeList() {
    final children = <Widget>[];
    String? lastChapter;

    for (final node in _nodes) {
      final chapter = _cleanText(node['chapter']);
      if (chapter.isNotEmpty && chapter != lastChapter) {
        children.add(_KnowledgeChapterLabel(label: chapter));
        lastChapter = chapter;
      }
      children.add(
        _KnowledgeNodeTile(
          node: node,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => KnowledgeNodeDetailPage(
                nodeId: node['id']?.toString() ?? '',
              ),
            ),
          ),
        ),
      );
      children.add(const Divider(height: 1));
    }

    return Column(children: children);
  }
}

class _KnowledgeSubject {
  const _KnowledgeSubject(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;
}

class _KnowledgeChapterLabel extends StatelessWidget {
  const _KnowledgeChapterLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _KnowledgeNodeTile extends StatelessWidget {
  const _KnowledgeNodeTile({
    required this.node,
    required this.onTap,
  });

  final Map<String, dynamic> node;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = _cleanText(node['name']);
    final description = _cleanText(node['description']);
    final examFreq = _readInt(node['exam_frequency']);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.article_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.58),
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (examFreq > 0) _ExamFrequencyPill(value: examFreq),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExamFrequencyPill extends StatelessWidget {
  const _ExamFrequencyPill({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '考频 $value',
        style: const TextStyle(
          color: Colors.orange,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _KnowledgeEmptyState extends StatelessWidget {
  const _KnowledgeEmptyState({
    required this.icon,
    required this.text,
    this.action,
  });

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 36,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.25),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5),
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 8),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class KnowledgeNodeDetailPage extends StatefulWidget {
  const KnowledgeNodeDetailPage({super.key, required this.nodeId});

  final String nodeId;

  @override
  State<KnowledgeNodeDetailPage> createState() =>
      _KnowledgeNodeDetailPageState();
}

class _KnowledgeNodeDetailPageState extends State<KnowledgeNodeDetailPage> {
  late Future<Map<String, dynamic>> _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = _loadDetail();
  }

  Future<Map<String, dynamic>> _loadDetail() async {
    final result = await MemCoachNativeBridge.callAgentTool(
      'knowledge_node_detail',
      {'node_id': widget.nodeId},
    );
    final error = result['error']?.toString();
    if (error != null && error.isNotEmpty && error != 'null') {
      throw Exception(error);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('知识点详情')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _detailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _KnowledgeDetailError(
              message:
                  snapshot.error.toString().replaceFirst('Exception: ', ''),
              onRetry: () => setState(() {
                _detailFuture = _loadDetail();
              }),
            );
          }
          final detail = snapshot.data ?? {};
          final name = _cleanText(detail['name']);
          final subject = _cleanText(detail['subject']);
          final chapter = _cleanText(detail['chapter']);
          final description = _cleanText(detail['description']);
          final content = _cleanText(detail['content']);
          final examFreq = _readInt(detail['exam_frequency']);

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (subject.isNotEmpty)
                    _KnowledgeInfoChip(
                      icon: Icons.school_outlined,
                      label: _subjectLabel(subject),
                    ),
                  if (chapter.isNotEmpty)
                    _KnowledgeInfoChip(
                      icon: Icons.folder_outlined,
                      label: chapter,
                    ),
                  if (examFreq > 0)
                    _KnowledgeInfoChip(
                      icon: Icons.local_fire_department_outlined,
                      label: '考频 $examFreq',
                    ),
                ],
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.55,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.68),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Divider(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.1),
              ),
              const SizedBox(height: 12),
              MarkdownMathView(
                data: content.isNotEmpty ? content : description,
                selectable: true,
                baseFontSize: 15,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _KnowledgeInfoChip extends StatelessWidget {
  const _KnowledgeInfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _KnowledgeDetailError extends StatelessWidget {
  const _KnowledgeDetailError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 42,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.58),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
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
            const Center(
                child: Padding(
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1D1D26) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.04),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
