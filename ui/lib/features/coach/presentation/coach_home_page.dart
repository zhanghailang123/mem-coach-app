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

        return Scaffold(
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // 顶部标题栏
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                      child: _Header(data: data),
                    ),
                  ),
                  // 今日备考仪表盘
                  SliverToBoxAdapter(
                    child: _DashboardCard(data: data),
                  ),
                  // 今日智能任务清单
                  SliverToBoxAdapter(
                    child: _TodayTasks(data: data),
                  ),
                  // PDF 资料中心
                  SliverToBoxAdapter(
                    child: const _PdfMaterialCard(),
                  ),
                  // 底部备考金句
                  const SliverToBoxAdapter(
                    child: _DailyQuoteCard(),
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

/// 顶部标题及操作栏
class _Header extends StatelessWidget {
  const _Header({required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context) {
    final streakText = data.streak > 0 ? '连续学习 ${data.streak} 天' : '开始你的学习之旅';
    final examText =
        data.daysUntilExam > 0 ? '距考试 ${data.daysUntilExam} 天' : '';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MEM 搭子',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                [if (examText.isNotEmpty) examText, streakText].join(' · '),
                style: TextStyle(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  fontSize: 13,
                ),
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
                content: const Text(
                    '暂无新通知。\n\n通知功能将在后续版本中完善，包括：\n• 学习提醒\n• 复习提醒\n• 成就通知'),
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

/// 仪表盘看板卡片
class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context) {
    final double accuracy =
        data.todayTotal > 0 ? (data.todayCorrect / data.todayTotal) : 0.0;
    final String accuracyText =
        data.todayTotal > 0 ? '${(accuracy * 100).toInt()}%' : '0%';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        // 极简浅色科技渐变背景
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1D1D26), const Color(0xFF161620)]
              : [Colors.white, const Color(0xFFF9FAFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? const Color(0xFF2C2C35) : const Color(0xFFE2E6F5),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5B5FEF).withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // 左侧圆形环状进度条
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: data.todayTotal > 0
                      ? (data.todayCorrect / data.todayTotal).clamp(0.0, 1.0)
                      : 0.0,
                  strokeWidth: 7.5,
                  backgroundColor: const Color(0xFF5B5FEF).withOpacity(0.08),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFF5B5FEF)),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      accuracyText,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      '今日正确率',
                      style: TextStyle(
                        fontSize: 8,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.5),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          // 右侧核心统计网格
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(context, '${data.daysUntilExam}天', '考试倒计时'),
                _buildStatItem(context, '${data.streak}天', '连续学习'),
                _buildStatItem(context, '${data.todayTotal}题', '今日刷题'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, String val, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          val,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// 今日学习清单板块
class _TodayTasks extends StatelessWidget {
  const _TodayTasks({required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '今日智能推荐清单',
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w900,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          // 任务 1：真题演练
          _buildTaskCard(
            context,
            icon: Icons.edit_document,
            iconBg: const Color(0xFF5B5FEF).withOpacity(0.08),
            iconColor: const Color(0xFF5B5FEF),
            title: '逻辑真题演练',
            subtitle: data.todayTotal > 0
                ? '今日已练 ${data.todayTotal} 题 · 建议再完成 5 题'
                : '建议完成 5 题真题摸底',
            actionText: '去练习',
            onTap: () {
              PracticePage.navigate(
                context,
                title: '每日真题挑战',
                subject: 'logic',
                count: 5,
              );
            },
          ),
          const SizedBox(height: 12),
          // 任务 2：闪卡复习
          _buildTaskCard(
            context,
            icon: Icons.psychology_outlined,
            iconBg: const Color(0xFFEF476F).withOpacity(0.08),
            iconColor: const Color(0xFFEF476F),
            title: '记忆闪卡背诵',
            subtitle: data.dueReviewCount > 0
                ? '有 ${data.dueReviewCount} 个词汇已到期需复习'
                : '词汇背诵已全部完成',
            actionText: '去背诵',
            onTap: () {
              PracticePage.navigate(
                context,
                title: '背诵复习',
                subject: 'logic',
                count: 5,
              );
            },
          ),
          const SizedBox(height: 12),
          // 任务 3：写作辅导快捷指令
          _buildTaskCard(
            context,
            icon: Icons.auto_awesome_outlined,
            iconBg: const Color(0xFF20B486).withOpacity(0.08),
            iconColor: const Color(0xFF20B486),
            title: '管综写作辅导',
            subtitle: '快速梳理论证有效性分析框架',
            actionText: '唤导师',
            onTap: () {
              ChatSheet.show(
                context,
                initialText: '帮我梳理考研管综写作的论证有效性分析核心大纲与框架',
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(
    BuildContext context, {
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String actionText,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1D1D26) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? const Color(0xFF2C2C35) : const Color(0xFFE2E6F5),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.5),
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                actionText,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 备考资料中心卡片
class _PdfMaterialCard extends StatelessWidget {
  const _PdfMaterialCard();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF171720) : const Color(0xFFF6F8FF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? const Color(0xFF262630) : const Color(0xFFE2E6F5),
            width: 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1D1D26) : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      Theme.of(context).colorScheme.primary.withOpacity(0.15),
                  width: 1.0,
                ),
              ),
              child: Icon(
                Icons.picture_as_pdf_outlined,
                color: Theme.of(context).colorScheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '个性化资料库',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '导入 PDF 真题以进行全考点拆解',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
            const _MinimalUploadEntry(),
          ],
        ),
      ),
    );
  }
}

/// 极简上传 PDF 功能组件
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF5B5FEF),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF5B5FEF).withOpacity(0.2),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _isUploading
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.cloud_upload_outlined,
                    color: Colors.white, size: 14),
            const SizedBox(width: 6),
            Text(
              _isUploading ? '导入中' : '导入 PDF',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold),
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

  Future<Map<String, dynamic>?> _showUploadParamsDialog(
      BuildContext context) async {
    String? selectedSubject;
    final yearController =
        TextEditingController(text: DateTime.now().year.toString());

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('上传真题参数'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                    labelText: '科目', border: OutlineInputBorder()),
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
                decoration: const InputDecoration(
                    labelText: '年份',
                    border: OutlineInputBorder(),
                    hintText: '例如：2024'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(
              onPressed: () {
                if (selectedSubject == null) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('请选择科目')));
                  return;
                }
                final year = int.tryParse(yearController.text);
                if (year == null || year <= 0) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('请输入有效的年份')));
                  return;
                }
                Navigator.pop(
                    context, {'subject': selectedSubject, 'year': year});
              },
              child: const Text('上传'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 每日一言与备考金句
class _DailyQuoteCard extends StatelessWidget {
  const _DailyQuoteCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 100),
      child: Column(
        children: [
          Icon(
            Icons.format_quote_rounded,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
            size: 38,
          ),
          const SizedBox(height: 8),
          Text(
            '“ 每一个努力背诵逻辑公式的深夜，都在为你未来科学决策的每一个管理动作铺路。 ”',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontStyle: FontStyle.italic,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
              height: 1.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '—— MEM AI 智能导师',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
            ),
          ),
        ],
      ),
    );
  }
}
