import 'package:flutter/material.dart';
import '../../../core/native/mem_coach_native_bridge.dart';
import 'dart:convert';

/// 单词本页面
class VocabularyPage extends StatefulWidget {
  const VocabularyPage({super.key});

  @override
  State<VocabularyPage> createState() => _VocabularyPageState();
}

class _VocabularyPageState extends State<VocabularyPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('单词本'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '待复习'),
            Tab(text: '学习中'),
            Tab(text: '已掌握'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildWordList('review'),
          _buildWordList('learning'),
          _buildWordList('mastered'),
        ],
      ),
    );
  }

  Widget _buildWordList(String type) {
    return FutureBuilder<Map<String, dynamic>>(
      future: MemCoachNativeBridge.callAgentTool('vocabulary_list', {'status': type, 'limit': 100}),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData) {
          return const Center(child: Text('暂无单词'));
        }

        final words = (snapshot.data?['words'] as List?) ?? [];

        if (words.isEmpty) {
          return const Center(child: Text('暂无单词'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: words.length,
          itemBuilder: (context, index) {
            final word = words[index];
            return _wordCard(word);
          },
        );
      },
    );
  }

  Widget _wordCard(Map<String, dynamic> word) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _navigateToDetail(word['id']),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      word['word'] ?? '',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (word['phonetic'] != null)
                    Text(
                      word['phonetic'],
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _extractDefinition(word['definitions']),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
              if (word['tags'] != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _parseTags(word['tags'])
                      .map((tag) => Chip(
                            label: Text(tag, style: const TextStyle(fontSize: 12)),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _extractDefinition(dynamic definitions) {
    try {
      if (definitions is String) {
        final List<dynamic> defs = jsonDecode(definitions);
        if (defs.isNotEmpty && defs[0] is Map) {
          return defs[0]['translation'] ?? '';
        }
      }
      return '';
    } catch (e) {
      return '';
    }
  }

  List<String> _parseTags(dynamic tags) {
    try {
      if (tags is String) {
        final List<dynamic> tagList = jsonDecode(tags);
        return tagList.map((e) => e.toString()).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  void _navigateToDetail(String wordId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VocabularyDetailPage(wordId: wordId),
      ),
    );
  }
}

/// 单词详情页
class VocabularyDetailPage extends StatelessWidget {
  final String wordId;

  const VocabularyDetailPage({super.key, required this.wordId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('单词详情')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: MemCoachNativeBridge.callAgentTool('vocabulary_detail', {'word_id': wordId}),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final word = snapshot.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 单词和音标
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        word['word'] ?? '',
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.volume_up),
                      onPressed: () {
                        // TODO: 发音
                      },
                    ),
                  ],
                ),
                if (word['phonetic'] != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    word['phonetic'],
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                ],

                const SizedBox(height: 24),

                // 释义
                const Text(
                  '释义',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  word['explanation'] ?? '',
                  style: const TextStyle(fontSize: 16, height: 1.6),
                ),

                const SizedBox(height: 24),

                // 复习按钮
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _markAsKnown(context, wordId),
                        child: const Text('认识'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _markAsUnknown(context, wordId),
                        child: const Text('不认识'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _markAsKnown(BuildContext context, String wordId) async {
    await MemCoachNativeBridge.callAgentTool('vocabulary_review', {
      'word_id': wordId,
      'is_correct': true,
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已标记为认识')),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _markAsUnknown(BuildContext context, String wordId) async {
    await MemCoachNativeBridge.callAgentTool('vocabulary_review', {
      'word_id': wordId,
      'is_correct': false,
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已加入复习计划')),
      );
      Navigator.pop(context);
    }
  }
}
