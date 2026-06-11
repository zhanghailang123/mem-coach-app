import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/native/mem_coach_native_bridge.dart';
import '../../../core/widgets/markdown_math.dart';

/// 单词本主页面
class VocabularyPage extends StatefulWidget {
  const VocabularyPage({super.key});

  @override
  State<VocabularyPage> createState() => _VocabularyPageState();
}

class _VocabularyPageState extends State<VocabularyPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _refreshKey = 0; // 页面刷新控制键

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // 刷新所有单词列表和统计看板
  void _triggerRefresh() {
    setState(() {
      _refreshKey++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFF),
      appBar: AppBar(
        title: const Text(
          '专业生词本',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
      ),
      body: Column(
        children: [
          // 顶部背诵数据统计看板
          _buildStatsDashboard(),
          const SizedBox(height: 12),
          // Tab 切换栏
          TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFF5B5FEF),
            indicatorSize: TabBarIndicatorSize.label,
            labelColor: const Color(0xFF5B5FEF),
            unselectedLabelColor: Colors.black45,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13.5),
            tabs: const [
              Tab(text: '待复习'),
              Tab(text: '学习中'),
              Tab(text: '已掌握'),
            ],
          ),
          const SizedBox(height: 8),
          // Tab 内容展示区
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildWordList('review'),
                _buildWordList('learning'),
                _buildWordList('mastered'),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF5B5FEF),
        elevation: 4,
        onPressed: () => _showAddWordDialog(context),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
      ),
    );
  }

  // 构建统计数据仪表盘
  Widget _buildStatsDashboard() {
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey('stats_$_refreshKey'),
      future: MemCoachNativeBridge.callAgentTool('vocabulary_stats', {}),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: SizedBox(height: 80, child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)))),
          );
        }

        final data = snapshot.data;
        final total = data?['total'] ?? 0;
        final review = data?['review'] ?? 0;
        final learning = data?['learning'] ?? 0;
        final mastered = data?['mastered'] ?? 0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF5B5FEF), Color(0xFF8C90FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF5B5FEF).withOpacity(0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '词汇学习进度',
                      style: TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '共收录 $total 词',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildDashboardStatItem('待复习', review, const Color(0xFFFFD166)),
                    _buildDashboardStatItem('学习中', learning, const Color(0xFF4EA8DE)),
                    _buildDashboardStatItem('已掌握', mastered, const Color(0xFF06D6A0)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDashboardStatItem(String label, int value, Color dotColor) {
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '$value',
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }

  // 构建指定状态的单词列表
  Widget _buildWordList(String type) {
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey('${type}_$_refreshKey'),
      future: MemCoachNativeBridge.callAgentTool('vocabulary_list', {'status': type, 'limit': 100}),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!['error'] != null) {
          return const Center(child: Text('加载失败，下拉重试', style: TextStyle(color: Colors.black38)));
        }

        final words = (snapshot.data?['words'] as List?) ?? [];

        if (words.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox_rounded, size: 48, color: Colors.black12),
                const SizedBox(height: 12),
                Text(
                  type == 'review' ? '太棒了，当前没有待复习单词！' : '暂无单词记录',
                  style: const TextStyle(color: Colors.black38, fontSize: 13),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
          itemCount: words.length,
          itemBuilder: (context, index) {
            final word = words[index];
            return _wordCard(word);
          },
        );
      },
    );
  }

  // 单词列表卡片设计
  Widget _wordCard(Map<String, dynamic> word) {
    final status = word['status'] ?? 'new';
    Color statusColor = const Color(0xFFFFD166);
    String statusText = '新词';
    if (status == 'learning') {
      statusColor = const Color(0xFF4EA8DE);
      statusText = '学习中';
    } else if (status == 'mastered') {
      statusColor = const Color(0xFF06D6A0);
      statusText = '已掌握';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E6F5), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _navigateToDetail(word['id']),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          word['word'] ?? '',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.black87),
                        ),
                        if (word['phonetic'] != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              word['phonetic'],
                              style: const TextStyle(fontSize: 12, color: Colors.black38, fontStyle: FontStyle.italic),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: statusColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _extractDefinition(word['definitions']),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Colors.black54, height: 1.45),
              ),
              if (word['tags'] != null && _parseTags(word['tags']).isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _parseTags(word['tags'])
                      .map((tag) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF5B5FEF).withOpacity(0.06),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF5B5FEF)),
                            ),
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
          final pos = defs[0]['pos']?.toString() ?? '';
          final translation = defs[0]['translation']?.toString() ?? '';
          return pos.isNotEmpty ? '$pos $translation' : translation;
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

  // 导航到详情页，如果标记认识/不认识后返回，则触发重新加载
  void _navigateToDetail(String wordId) async {
    final needRefresh = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => VocabularyDetailPage(wordId: wordId),
      ),
    );
    if (needRefresh == true) {
      _triggerRefresh();
    }
  }

  // 手动添加单词输入弹窗
  Future<void> _showAddWordDialog(BuildContext context) async {
    final wordController = TextEditingController();
    final phoneticController = TextEditingController();
    final translationController = TextEditingController();
    final tagsController = TextEditingController();
    final explanationController = TextEditingController();

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF5B5FEF).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.note_add_rounded, color: Color(0xFF5B5FEF), size: 20),
              ),
              const SizedBox(width: 10),
              const Text('录入新单词', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: wordController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '单词 *',
                    hintText: '输入英文单词',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneticController,
                  decoration: const InputDecoration(
                    labelText: '音标',
                    hintText: '例如 /\'bentʃmɑːk/',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: translationController,
                  decoration: const InputDecoration(
                    labelText: '中文释义 *',
                    hintText: '例如 n. 基准; 标杆',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tagsController,
                  decoration: const InputDecoration(
                    labelText: '标签',
                    hintText: '多个用逗号隔开，如 MEM, 核心词',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: explanationController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '备考解析与例句（支持 Markdown）',
                    hintText: '可在此添加例句、搭配等...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF5B5FEF)),
              onPressed: () async {
                final word = wordController.text.trim();
                final translation = translationController.text.trim();
                if (word.isEmpty || translation.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请填写单词和释义')),
                  );
                  return;
                }

                // 分离词性与核心释义
                String pos = '';
                String trans = translation;
                final posRegex = RegExp(r'^([a-zA-Z]+\.)\s*(.*)$');
                if (posRegex.hasMatch(translation)) {
                  final match = posRegex.firstMatch(translation);
                  pos = match?.group(1) ?? '';
                  trans = match?.group(2) ?? '';
                }
                final definitionsJson = jsonEncode([
                  {'pos': pos, 'translation': trans}
                ]);

                // 解析标签列表
                final rawTags = tagsController.text.split(RegExp(r'[,，]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                final tagsJson = jsonEncode(rawTags);

                // 准备详细解析正文
                String exp = explanationController.text.trim();
                if (exp.isEmpty) {
                  exp = '### $word\n\n- **核心释义**: $translation\n';
                }

                final result = await MemCoachNativeBridge.callAgentTool('vocabulary_add', {
                  'word': word,
                  'phonetic': phoneticController.text.trim().isEmpty ? null : phoneticController.text.trim(),
                  'definitions': definitionsJson,
                  'explanation': exp,
                  'tags': tagsJson,
                });

                if (context.mounted) {
                  if (result['success'] == true) {
                    final alreadyExists = result['already_exists'] == true;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(alreadyExists ? '单词「$word」已存在于词库' : '添加单词「$word」成功'),
                        backgroundColor: alreadyExists ? Colors.orange : const Color(0xFF20B486),
                      ),
                    );
                    Navigator.pop(context);
                    _triggerRefresh();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('录入失败: ${result['error'] ?? "未知错误"}'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }
}

/// 单词详情页（StatefulWidget 便于处理局部状态更新）
class VocabularyDetailPage extends StatefulWidget {
  final String wordId;
  const VocabularyDetailPage({super.key, required this.wordId});

  @override
  State<VocabularyDetailPage> createState() => _VocabularyDetailPageState();
}

class _VocabularyDetailPageState extends State<VocabularyDetailPage> {
  Future<Map<String, dynamic>>? _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = _loadDetail();
  }

  Future<Map<String, dynamic>> _loadDetail() async {
    return await MemCoachNativeBridge.callAgentTool('vocabulary_detail', {'word_id': widget.wordId});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFF),
      appBar: AppBar(
        title: const Text('单词详情', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _detailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!['error'] != null) {
            return const Center(child: Text('加载失败，或该单词不存在'));
          }

          final word = snapshot.data!;
          final status = word['status'] ?? 'new';
          Color statusColor = const Color(0xFFFFD166);
          String statusText = '新词';
          if (status == 'learning') {
            statusColor = const Color(0xFF4EA8DE);
            statusText = '学习中';
          } else if (status == 'mastered') {
            statusColor = const Color(0xFF06D6A0);
            statusText = '已掌握';
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 顶部卡片
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE2E6F5), width: 1.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  word['word'] ?? '',
                                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.black87, letterSpacing: -0.5),
                                ),
                                if (word['phonetic'] != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    word['phonetic'],
                                    style: TextStyle(fontSize: 16, color: Colors.black38, fontStyle: FontStyle.italic),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              statusText,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        '详细释义与备考解析',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      const Divider(color: Color(0xFFE2E6F5), height: 1),
                      const SizedBox(height: 14),
                      // 使用 MarkdownMathView 渲染详细解析，支持公式和格式
                      MarkdownMathView(
                        data: word['explanation'] ?? '',
                        baseFontSize: 14.5,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                // 记忆反馈功能按钮
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF20B486),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => _submitFeedback(context, true),
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                        label: const Text('认识，加入下阶段', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFEF476F),
                          side: const BorderSide(color: Color(0xFFEF476F)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => _submitFeedback(context, false),
                        icon: const Icon(Icons.help_outline_rounded, size: 20),
                        label: const Text('模糊/不认识', style: TextStyle(fontWeight: FontWeight.bold)),
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

  Future<void> _submitFeedback(BuildContext context, bool isCorrect) async {
    await MemCoachNativeBridge.callAgentTool('vocabulary_review', {
      'word_id': widget.wordId,
      'is_correct': isCorrect,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isCorrect ? '已标记为认识' : '已加入复习计划'),
          backgroundColor: isCorrect ? const Color(0xFF20B486) : const Color(0xFFEF476F),
        ),
      );
      Navigator.pop(context, true); // 返回 true 通知列表刷新
    }
  }
}
