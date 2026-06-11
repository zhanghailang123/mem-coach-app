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
        ? '正在智能分析你的学习进度...'
        : data.briefing.isNotEmpty
            ? data.briefing
            : '告诉我你的目标，我会把真题、知识点和复习节奏串起来。';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        // 深邃科技蓝渐变背景
        gradient: const LinearGradient(
          colors: [
            Color(0xFF131525),
            Color(0xFF1C1F3F),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: const Color(0xFF5B5FEF).withOpacity(0.35),
          width: 2,
        ),
        // AI 专属极光发光外投影
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5B5FEF).withOpacity(0.4),
            blurRadius: 36,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: const Color(0xFF20B486).withOpacity(0.15),
            blurRadius: 36,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI 导师身份及问候
          Row(
            children: [
              // 巨型发光 AI 徽章
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF5B5FEF), Color(0xFF20B486)],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF5B5FEF).withOpacity(0.6),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'MEM AI 智能导师',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(width: 10),
                        // 呼吸式在线标签
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF20B486).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF20B486).withOpacity(0.4), width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF20B486),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                '在线',
                                style: TextStyle(
                                  color: Color(0xFF20B486),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      briefingText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // 巨型拟真对话条入口
          GestureDetector(
            onTap: () => ChatSheet.show(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFF5B5FEF).withOpacity(0.1),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF5B5FEF).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF5B5FEF), size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '即刻发起对话',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          '“今天我该复习什么？”',
                          style: TextStyle(color: Colors.black45, fontSize: 13.5),
                        ),
                      ],
                    ),
                  ),
                  // 发光启动按钮
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF5B5FEF), Color(0xFF20B486)],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x505B5FEF),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 22),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 引导 Prompt 提示词
          const Text(
            '你可以这样问我',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white38,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: const [
              _PromptChip(label: '⏱️ 我今天只有 20 分钟', prompt: '帮我安排今天 20 分钟 MEM 学习计划'),
              _PromptChip(label: '📝 帮我复盘错题', prompt: '根据我的错题和学习记录，帮我复盘当前最需要补的知识点'),
              _PromptChip(label: '💡 出 3 道逻辑题', prompt: '给我 3 道逻辑题练习，并在我答完后讲解思路'),
            ],
          ),
        ],
      ),
    );
  }

  // 获取时间问候语
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
      onPressed: () => ChatSheet.show(context, initialText: prompt),
      backgroundColor: Colors.white.withOpacity(0.08),
      side: BorderSide(color: Colors.white.withOpacity(0.15), width: 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 12.5,
        color: Colors.white.withOpacity(0.9),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
