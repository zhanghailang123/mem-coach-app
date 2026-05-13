import 'package:flutter/material.dart';

class KnowledgePage extends StatelessWidget {
  const KnowledgePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('知识库'),
        actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.upload_file_rounded))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          _SegmentTabs(),
          SizedBox(height: 16),
          _FileGroupCard(),
          SizedBox(height: 16),
          _KnowledgeTreeCard(),
          SizedBox(height: 16),
          _MemorizeEntryCard(),
        ],
      ),
    );
  }
}

class _SegmentTabs extends StatelessWidget {
  const _SegmentTabs();

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: 0, label: Text('真题')),
        ButtonSegment(value: 1, label: Text('图谱')),
        ButtonSegment(value: 2, label: Text('背诵')),
      ],
      selected: const {0},
      onSelectionChanged: (_) {},
    );
  }
}

class _FileGroupCard extends StatelessWidget {
  const _FileGroupCard();

  @override
  Widget build(BuildContext context) {
    final files = [
      ('2024 管综真题.pdf', '已解析 25/25 题'),
      ('2023 管综真题.pdf', '已解析 25/25 题'),
      ('2022 管综真题.pdf', '解析中 18/25 题'),
    ];
    return _KbCard(
      title: '真题文件',
      child: Column(
        children: files.map((f) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFEF476F)),
          title: Text(f.$1, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(f.$2),
          trailing: const Icon(Icons.chevron_right_rounded),
        )).toList(),
      ),
    );
  }
}

class _KnowledgeTreeCard extends StatelessWidget {
  const _KnowledgeTreeCard();

  @override
  Widget build(BuildContext context) {
    return _KbCard(
      title: '逻辑知识树',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _TreeNode('形式逻辑', level: 0, active: true),
          _TreeNode('条件推理', level: 1, active: true),
          _TreeNode('否定后件式', level: 2, active: true),
          _TreeNode('选言推理', level: 1),
          _TreeNode('论证逻辑', level: 0),
          _TreeNode('削弱与加强', level: 1),
        ],
      ),
    );
  }
}

class _TreeNode extends StatelessWidget {
  const _TreeNode(this.title, {required this.level, this.active = false});

  final String title;
  final int level;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: level * 20.0, bottom: 10),
      child: Row(
        children: [
          Icon(active ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
              size: 18, color: active ? Theme.of(context).colorScheme.primary : Colors.black38),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(fontWeight: active ? FontWeight.w900 : FontWeight.w600)),
        ],
      ),
    );
  }
}

class _MemorizeEntryCard extends StatelessWidget {
  const _MemorizeEntryCard();

  @override
  Widget build(BuildContext context) {
    return _KbCard(
      title: '背诵学习',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🔴 待背 5 条   🟡 复习 12 条', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: () {}, child: const Text('开始背诵'))),
        ],
      ),
    );
  }
}

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
