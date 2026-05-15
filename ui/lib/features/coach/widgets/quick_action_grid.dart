import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/native/mem_coach_native_bridge.dart';
import '../../knowledge/presentation/knowledge_page.dart';
import '../presentation/practice_page.dart';
import 'chat_sheet.dart';

class QuickActionGrid extends StatefulWidget {
  const QuickActionGrid({super.key});

  @override
  State<QuickActionGrid> createState() => _QuickActionGridState();
}

class _QuickActionGridState extends State<QuickActionGrid> {
  bool _isUploading = false;

  @override
  Widget build(BuildContext context) {
    final items = [
      _QuickAction('上传真题', Icons.upload_file_rounded, const Color(0xFF5B5FEF)),
      _QuickAction('知识图谱', Icons.hub_rounded, const Color(0xFF20B486)),
      _QuickAction('模拟考试', Icons.science_rounded, const Color(0xFFFF9F1C)),
      _QuickAction('背诵模式', Icons.psychology_alt_rounded, const Color(0xFFEF476F)),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.25,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => _handleActionTap(context, index),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.black.withOpacity(0.04)),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: item.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: index == 0 && _isUploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(item.icon, color: item.color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleActionTap(BuildContext context, int index) async {
    switch (index) {
      case 0: // 上传真题
        await _uploadPdf(context);
        break;
      case 1: // 知识图谱 - 跳转到知识库页面的图谱标签
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const KnowledgePage(initialTab: 1),
          ),
        );
        break;
      case 2: // 模拟考试 - 跳转到模拟考试练习
        PracticePage.navigate(
          context,
          title: '模拟考试',
          subject: 'logic',
          count: 10,
        );
        break;
      case 3: // 背诵模式 - 跳转到背诵练习
        PracticePage.navigate(
          context,
          title: '背诵模式',
          subject: 'logic',
          count: 5,
        );
        break;
    }
  }

  Future<void> _uploadPdf(BuildContext context) async {
    if (_isUploading) return;

    // 1. 选择 PDF 文件
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法获取文件路径')),
        );
      }
      return;
    }

    // 2. 显示科目和年份选择对话框
    final uploadParams = await _showUploadParamsDialog(context);
    if (uploadParams == null) return;

    setState(() => _isUploading = true);

    try {
      // 3. 调用 Native Bridge 上传
      final uploadResult = await MemCoachNativeBridge.uploadPdf(
        file.path!,
        subject: uploadParams['subject'],
        year: uploadParams['year'],
      );

      if (mounted) {
        final fileName = uploadResult['file_name']?.toString() ?? file.name;
        final pageCount = uploadResult['page_count']?.toString() ?? '?';
        final documentId = uploadResult['document_id']?.toString() ?? uploadResult['id']?.toString() ?? '';
        final jobId = uploadResult['job_id']?.toString() ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('上传成功并启动后台解析：$fileName（$pageCount 页）'),
            backgroundColor: const Color(0xFF20B486),
          ),
        );

        final initialText = documentId.isNotEmpty
            ? '请基于 PDF「$fileName」（document_id: $documentId，$pageCount 页）回答：'
            : '请基于刚刚上传的 PDF「$fileName」（$pageCount 页）回答：';
        final initialStatus = jobId.isNotEmpty
            ? 'PDF 已上传，后台解析中（任务：$jobId）。你可以继续输入问题。'
            : 'PDF 已上传，后台解析中。你可以继续输入问题。';

        // 自动打开 ChatSheet 方便用户基于刚上传的 PDF 提问
        ChatSheet.show(
          context,
          initialText: initialText,
          initialStatus: initialStatus,
          initialPdfJobId: jobId.isNotEmpty ? jobId : null,
        );


      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('上传失败：$e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<Map<String, dynamic>?> _showUploadParamsDialog(BuildContext context) async {
    String? selectedSubject;
    int? selectedYear;
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
                decoration: const InputDecoration(
                  labelText: '科目',
                  border: OutlineInputBorder(),
                ),
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
                  hintText: '例如：2024',
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  selectedYear = int.tryParse(value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (selectedSubject == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请选择科目')),
                  );
                  return;
                }
                final year = int.tryParse(yearController.text);
                if (year == null || year <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请输入有效的年份')),
                  );
                  return;
                }
                Navigator.pop(context, {
                  'subject': selectedSubject,
                  'year': year,
                });
              },
              child: const Text('上传'),
            ),
          ],
        ),
      ),
    );
  }

  void _showFeatureNotAvailable(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature 功能即将上线')),
    );
  }
}

class _QuickAction {
  const _QuickAction(this.title, this.icon, this.color);

  final String title;
  final IconData icon;
  final Color color;
}