import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/native/mem_coach_native_bridge.dart';
import '../../../core/widgets/markdown_math.dart';

/// 单词本主页面（单页搜索 + 状态过滤设计）
class VocabularyPage extends StatefulWidget {
  const VocabularyPage({super.key});

  @override
  State<VocabularyPage> createState() => _VocabularyPageState();
}

class _VocabularyPageState extends State<VocabularyPage> {
  int _refreshKey = 0; // 刷新控制键
  String _searchQuery = ''; // 搜索词
  String _selectedStatus = 'all'; // 当前选中的过滤状态: all, review, learning, mastered
  final TextEditingController _searchController = TextEditingController();

  // 触发页面整体数据重新加载
  void _triggerRefresh() {
    setState(() {
      _refreshKey++;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFFF9FAFF),
      appBar: AppBar(
        title: const Text(
          '专业生词本',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
        actions: [
          IconButton(
            icon: const Icon(Icons.note_add_outlined, color: Color(0xFF5B5FEF), size: 24),
            onPressed: () => _showAddWordDialog(context),
            tooltip: '录入新单词',
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          // 顶部学习统计仪表盘
          _buildStatsDashboard(),
          // 搜索框及过滤标签区
          _buildSearchAndFilters(),
          // 单词列表区
          Expanded(
            child: _buildWordList(),
          ),
        ],
      ),
    );
  }

  // 构建统计数据看板
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

  // 构建搜索输入栏与过滤 Chip 行
  Widget _buildSearchAndFilters() {
    final filterStatuses = [
      {'id': 'all', 'label': '全部'},
      {'id': 'review', 'label': '待复习'},
      {'id': 'learning', 'label': '学习中'},
      {'id': 'mastered', 'label': '已掌握'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 搜索输入栏
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E6F5), width: 1.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.015),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val.trim();
                });
              },
              decoration: InputDecoration(
                hintText: '搜索词汇...',
                hintStyle: const TextStyle(color: Colors.black26, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.black38, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                        child: const Icon(Icons.clear_rounded, color: Colors.black38, size: 18),
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
        // 过滤 Chip 滚动行 (仅在未搜索或作为筛选辅助时呈现)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Row(
            children: filterStatuses.map((item) {
              final isSelected = _selectedStatus == item['id'];
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedStatus = item['id']!;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF5B5FEF) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? Colors.transparent : const Color(0xFFE2E6F5),
                        width: 1.0,
                      ),
                      boxShadow: [
                        if (isSelected)
                          BoxShadow(
                            color: const Color(0xFF5B5FEF).withOpacity(0.18),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                      ],
                    ),
                    child: Text(
                      item['label']!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? Colors.white : Colors.black54,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // 构建过滤后的词汇列表
  Widget _buildWordList() {
    final isSearching = _searchQuery.isNotEmpty;

    // 动态决定调用哪一个 Native Tool
    final Future<Map<String, dynamic>> fetchFuture = isSearching
        ? MemCoachNativeBridge.callAgentTool('vocabulary_search', {
            'query': _searchQuery,
            'limit': 80,
          })
        : MemCoachNativeBridge.callAgentTool('vocabulary_list', {
            'status': _selectedStatus,
            'limit': 100,
          });

    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey('list_${isSearching ? "search_" + _searchQuery : _selectedStatus}_$_refreshKey'),
      future: fetchFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!['error'] != null) {
          return const Center(child: Text('加载失败，请下拉或重试', style: TextStyle(color: Colors.black38)));
        }

        var words = (snapshot.data?['words'] as List?) ?? [];

        // 如果在搜索模式下，且选定了过滤状态，在本地进行二次筛选
        if (isSearching && _selectedStatus != 'all') {
          words = words.where((item) {
            final itemStatus = item['status'] ?? 'new';
            // 如果是“待复习”，因为搜索数据未返回到期状态，默认展示所有匹配且状态为非已掌握或正在学习的词
            if (_selectedStatus == 'review') {
              return itemStatus == 'new' || itemStatus == 'learning';
            }
            return itemStatus == _selectedStatus;
          }).toList();
        }

        if (words.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox_rounded, size: 44, color: Colors.black12),
                const SizedBox(height: 12),
                Text(
                  isSearching ? '没有找到匹配的单词' : (_selectedStatus == 'review' ? '太棒了，当前没有待复习单词！' : '暂无相关单词记录'),
                  style: const TextStyle(color: Colors.black38, fontSize: 13),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
          itemCount: words.length,
          itemBuilder: (context, index) {
            final word = words[index];
            return _wordCard(word);
          },
        );
      },
    );
  }

  // 单词卡片组件
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
            color: Colors.black.withOpacity(0.015),
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

  // 导航到详情页，如果状态改变返回，则刷新数据
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

  // 手动录入新单词的对话框（简化输入并走 AI 解析）
  Future<void> _showAddWordDialog(BuildContext context) async {
    final wordController = TextEditingController();
    bool isLoading = false;

    return showDialog(
      context: context,
      barrierDismissible: false, // AI 生成期间禁止点击外部关闭
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return PopScope(
              canPop: !isLoading, // AI 生成期间禁止返回键关闭
              child: AlertDialog(
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
                content: isLoading
                    ? Container(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF5B5FEF)),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'AI 导师正在进行深度学术解析...',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: wordController,
                            autofocus: true,
                            decoration: const InputDecoration(
                              labelText: '单词/短语 *',
                              hintText: '输入英文单词或短语，AI 将自动分析',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.all(Radius.circular(12)),
                              ),
                              isDense: true,
                            ),
                          ),
                        ],
                      ),
                actions: isLoading
                    ? null
                    : [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF5B5FEF),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () async {
                            final word = wordController.text.trim();
                            if (word.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('请输入单词')),
                              );
                              return;
                            }

                            setState(() {
                              isLoading = true;
                            });

                            try {
                              final result = await MemCoachNativeBridge.callAgentTool('vocabulary_add', {
                                'word': word,
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
                                  setState(() {
                                    isLoading = false;
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('录入失败: ${result['error'] ?? "未知错误"}'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            } catch (e) {
                              if (context.mounted) {
                                setState(() {
                                  isLoading = false;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('录入出错: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          child: const Text('AI 生成解析'),
                        ),
                      ],
              ),
            );
          },
        );
      },
    );
  }
}

/// 单词详情页
class VocabularyDetailPage extends StatefulWidget {
  final String wordId;
  const VocabularyDetailPage({super.key, required this.wordId});

  @override
  State<VocabularyDetailPage> createState() => _VocabularyDetailPageState();
}

class _VocabularyDetailPageState extends State<VocabularyDetailPage> {
  Future<Map<String, dynamic>>? _detailFuture;
  bool _transitionEnded = false; // 是否完成转场动画

  @override
  void initState() {
    super.initState();
    _detailFuture = _loadDetail();

    // 延迟加载与渲染，避免复杂的 MarkdownMathView 造成转场掉帧
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.animation != null) {
        void listener(AnimationStatus status) {
          if (status == AnimationStatus.completed) {
            route.animation!.removeStatusListener(listener);
            if (mounted) {
              setState(() {
                _transitionEnded = true;
              });
            }
          }
        }

        if (route.animation!.isCompleted) {
          setState(() {
            _transitionEnded = true;
          });
        } else {
          route.animation!.addStatusListener(listener);
        }
      } else {
        setState(() {
          _transitionEnded = true;
        });
      }
    });
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
          if (snapshot.connectionState == ConnectionState.waiting || !_transitionEnded) {
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
                // 详情卡片
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
