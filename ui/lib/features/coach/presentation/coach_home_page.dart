import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/native/mem_coach_native_bridge.dart';
import '../../settings/presentation/settings_page.dart';
import '../widgets/chat_sheet.dart';
import 'practice_page.dart';

/// 首页数据模型
class HomeData {
  const HomeData({
    this.streak = 0,
    this.daysUntilExam = 0,
    this.todayTotal = 0,
    this.todayCorrect = 0,
    this.todayAccuracy = -1.0,
    this.overallAccuracy = -1.0,
    this.dueReviewCount = 0,
    this.masteredCount = 0,
    this.totalKnowledgeCount = 0,
    this.weakPoints = const [],
    this.briefing = '',
  });

  final int streak;
  final int daysUntilExam;
  final int todayTotal;
  final int todayCorrect;
  final double todayAccuracy;
  final double overallAccuracy;
  final int dueReviewCount;
  final int masteredCount;
  final int totalKnowledgeCount;
  final List<Map<String, dynamic>> weakPoints;
  final String briefing;

  factory HomeData.fromMap(Map<String, dynamic> map) {
    return HomeData(
      streak: (map['streak'] as num?)?.toInt() ?? 0,
      daysUntilExam: (map['days_until_exam'] as num?)?.toInt() ?? 0,
      todayTotal: (map['today_total'] as num?)?.toInt() ?? 0,
      todayCorrect: (map['today_correct'] as num?)?.toInt() ?? 0,
      todayAccuracy: (map['today_accuracy'] as num?)?.toDouble() ?? -1.0,
      overallAccuracy: (map['overall_accuracy'] as num?)?.toDouble() ?? -1.0,
      dueReviewCount: (map['due_review_count'] as num?)?.toInt() ?? 0,
      masteredCount: (map['mastered_count'] as num?)?.toInt() ?? 0,
      totalKnowledgeCount: (map['total_knowledge_count'] as num?)?.toInt() ?? 0,
      weakPoints: (map['weak_points'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      briefing: map['briefing'] as String? ?? '',
    );
  }

  bool get hasData => todayTotal > 0 || streak > 0 || masteredCount > 0;
}

class CoachHomePage extends StatefulWidget {
  const CoachHomePage({super.key});

  @override
  State<CoachHomePage> createState() => _CoachHomePageState();
}

class _CoachHomePageState extends State<CoachHomePage> {
  Future<HomeData>? _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  Future<HomeData> _loadData() async {
    try {
      final map = await MemCoachNativeBridge.getHomeData();
      return HomeData.fromMap(map);
    } catch (e) {
      debugPrint('加载首页数据失败: $e');
      return const HomeData();
    }
  }

  Future<void> _onRefresh() async {
    setState(() {
      _dataFuture = _loadData();
    });
    await _dataFuture;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HomeData>(
      future: _dataFuture,
      builder: (context, snapshot) {
        final data = snapshot.data ?? const HomeData();
        final isLoading = snapshot.connectionState == ConnectionState.waiting;

        return Scaffold(
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                      child: _Header(data: data),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: _ChatHeroCard(data: data, isLoading: isLoading),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                      child: _CoreStudyDoubleCard(data: data),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 28, 20, 100),
                      child: _MinimalUploadEntry(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context) {
    final streakText = data.streak > 0 ? '连续学习 ${data.streak} 天' : '开始你的学习之旅';
    final examText = data.daysUntilExam > 0 ? '距考试 ${data.daysUntilExam} 天' : '';

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF5B5FEF), Color(0xFF20B486)],
            ),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 21),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('MEM Coach', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 1),
              Text(
                [if (examText.isNotEmpty) examText, streakText].join(' · '),
                style: const TextStyle(color: Colors.black54, fontSize: 12.5),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('通知中心'),
                content: const Text('暂无新通知。\n\n通知功能将在后续版本中完善，包括：\n• 学习提醒\n• 复习提醒\n• 成就通知'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('知道了'),
                  ),
                ],
              ),
            );
          },
          icon: const Icon(Icons.notifications_none_rounded),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const SettingsPage(),
              ),
            );
          },
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    );
  }
}

class _ChatHeroCard extends StatelessWidget {
  const _ChatHeroCard({required this.data, required this.isLoading});

  final HomeData data;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final briefingText = isLoading
        ? '正在分析你的学习数据...'
        : data.briefing.isNotEmpty
            ? data.briefing
            : '告诉我你的目标，我会把真题、知识点和复习节奏串起来。';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFF),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFFE9ECFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.auto_awesome_rounded, color: Theme.of(context).colorScheme.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_getGreeting(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black54)),
                    const SizedBox(height: 1),
                    Text(
                      briefingText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.black38, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: () => ChatSheet.show(context),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 26, 16, 26),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.12)),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                    blurRadius: 36,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.06),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.chat_bubble_outline_rounded, color: Theme.of(context).colorScheme.primary, size: 22),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('从一次对话开始', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87, letterSpacing: -0.5)),
                        SizedBox(height: 4),
                        Text('问我：今天该怎么学？', style: TextStyle(color: Colors.black38, fontSize: 13.5)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF5B5FEF), Color(0xFF20B486)],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Color(0x405B5FEF), blurRadius: 10, offset: Offset(0, 4)),
                      ],
                    ),
                    child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 22),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('你可以这样问', style: TextStyle(fontSize: 11, color: Colors.black26, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: const [
              _PromptChip(label: '我今天只有 20 分钟', prompt: '帮我安排今天 20 分钟 MEM 学习计划'),
              _PromptChip(label: '帮我复盘错题', prompt: '根据我的错题和学习记录，帮我复盘当前最需要补的知识点'),
              _PromptChip(label: '出 3 道逻辑题', prompt: '给我 3 道逻辑题练习，并在我答完后讲解思路'),
            ],
          ),
        ],
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) return '夜深了，先轻量复盘。';
    if (hour < 12) return '上午好，开启一次高效学习。';
    if (hour < 14) return '中午好，适合做 3 道微练习。';
    if (hour < 18) return '下午好，把薄弱点补一补。';
    if (hour < 22) return '晚上好，复习正当时。';
    return '夜深了，先轻量复盘。';
  }
}

class _PromptChip extends StatelessWidget {
  const _PromptChip({required this.label, required this.prompt});

  final String label;
  final String prompt;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      avatar: const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFF5B5FEF)),
      onPressed: () => ChatSheet.show(context, initialText: prompt),
      backgroundColor: Colors.white.withOpacity(0.94),
      side: BorderSide(color: Colors.white.withOpacity(0.45)),
      labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.black87),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    );
  }
}

class _CoreStudyDoubleCard extends StatelessWidget {
  const _CoreStudyDoubleCard({required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 真题挑战
        Expanded(
          child: GestureDetector(
            onTap: () {
              PracticePage.navigate(
                context,
                title: '每日真题挑战',
                subject: 'logic',
                count: 5,
              );
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF5B5FEF), Color(0xFF8C90FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF5B5FEF).withOpacity(0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.edit_document, color: Colors.white, size: 20),
                      ),
                      const Icon(Icons.arrow_forward_rounded, color: Colors.white70, size: 18),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '真题演练',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data.todayTotal > 0 ? '今日已练 ${data.todayTotal} 题' : '开启今日刷题挑战',
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        // 记忆卡牌
        Expanded(
          child: GestureDetector(
            onTap: () {
              PracticePage.navigate(
                context,
                title: '背诵复习',
                subject: 'logic',
                count: 5,
              );
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFEF476F), Color(0xFFFF7597)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFEF476F).withOpacity(0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.psychology, color: Colors.white, size: 20),
                      ),
                      const Icon(Icons.arrow_forward_rounded, color: Colors.white70, size: 18),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '记忆闪卡',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data.dueReviewCount > 0 ? '${data.dueReviewCount} 个知识点到期' : '今日已背诵完成',
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 极简上传真题入口
class _MinimalUploadEntry extends StatefulWidget {
  const _MinimalUploadEntry();

  @override
  State<_MinimalUploadEntry> createState() => _MinimalUploadEntryState();
}

class _MinimalUploadEntryState extends State<_MinimalUploadEntry> {
  bool _isUploading = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _isUploading ? null : () => _uploadPdf(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.03),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _isUploading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.upload_file_rounded, color: Colors.black38, size: 18),
            const SizedBox(width: 8),
            Text(
              _isUploading ? '上传中...' : '上传真题 PDF',
              style: const TextStyle(color: Colors.black38, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadPdf(BuildContext context) async {
    if (_isUploading) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;

    // 显示科目年份选择
    final params = await _showUploadParamsDialog(context);
    if (params == null) return;

    setState(() => _isUploading = true);
    try {
      final uploadResult = await MemCoachNativeBridge.uploadPdf(
        file.path!,
        subject: params['subject'],
        year: params['year'],
      );
      if (mounted) {
        final fileName = uploadResult['file_name']?.toString() ?? file.name;
        final jobId = uploadResult['job_id']?.toString() ?? '';
        final pageCount = uploadResult['page_count']?.toString() ?? '?';
        final documentId = uploadResult['document_id']?.toString() ?? '';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('上传成功：$fileName（$pageCount 页）'),
            backgroundColor: const Color(0xFF20B486),
          ),
        );

        final initialText = documentId.isNotEmpty
            ? '请基于 PDF「$fileName」（document_id: $documentId，$pageCount 页）回答：'
            : '请基于刚刚上传的 PDF「$fileName」（$pageCount 页）回答：';

        ChatSheet.show(
          context,
          initialText: initialText,
          initialStatus: 'PDF 已上传，后台解析中。',
          initialPdfJobId: jobId.isNotEmpty ? jobId : null,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传失败：$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<Map<String, dynamic>?> _showUploadParamsDialog(BuildContext context) async {
    String? selectedSubject;
    final yearController = TextEditingController(text: DateTime.now().year.toString());

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('上传真题参数'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: '科目', border: OutlineInputBorder()),
                value: selectedSubject,
                items: const [
                  DropdownMenuItem(value: 'logic', child: Text('逻辑')),
                  DropdownMenuItem(value: 'writing', child: Text('写作')),
                  DropdownMenuItem(value: 'math', child: Text('数学')),
                  DropdownMenuItem(value: 'english', child: Text('英语')),
                ],
                onChanged: (value) => setState(() => selectedSubject = value),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: yearController,
                decoration: const InputDecoration(labelText: '年份', border: OutlineInputBorder(), hintText: '例如：2024'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                if (selectedSubject == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请选择科目')));
                  return;
                }
                final year = int.tryParse(yearController.text);
                if (year == null || year <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入有效的年份')));
                  return;
                }
                Navigator.pop(context, {'subject': selectedSubject, 'year': year});
              },
              child: const Text('上传'),
            ),
          ],
        ),
      ),
    );
  }
}
