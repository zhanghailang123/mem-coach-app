import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/native/mem_coach_native_bridge.dart';
import '../../../core/widgets/markdown_math.dart';

/// 知识库页面 - 扁平化展示各科知识图谱与知识点列表
class KnowledgePage extends StatefulWidget {
  const KnowledgePage({super.key});

  @override
  State<KnowledgePage> createState() => _KnowledgePageState();
}

class _KnowledgePageState extends State<KnowledgePage> {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('知识库'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // 顶部固定控制区域
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
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
              ],
            ),
          ),
          const Divider(height: 1),
          // 知识点列表展现区
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : _error != null
                    ? _KnowledgeEmptyState(
                        icon: Icons.error_outline_rounded,
                        text: '加载失败：$_error',
                        action: IconButton(
                          onPressed: _loadNodes,
                          icon: const Icon(Icons.refresh_rounded),
                          tooltip: '重试',
                        ),
                      )
                    : _nodes.isEmpty
                        ? const _KnowledgeEmptyState(
                            icon: Icons.search_off_rounded,
                            text: '没有匹配的知识点',
                          )
                        : _buildNodeList(),
          ),
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
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _KnowledgeChapterLabel(label: chapter),
          ),
        );
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
      children.add(const Divider(height: 1, indent: 16, endIndent: 16));
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: children,
    );
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
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 13,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 40,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.25),
            ),
            const SizedBox(height: 10),
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
