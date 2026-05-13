import 'package:flutter/material.dart';

class InsightPage extends StatelessWidget {
  const InsightPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的学情')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          _ScoreCard(),
          SizedBox(height: 16),
          _SubjectRadarMock(),
          SizedBox(height: 16),
          _WeakPointList(),
          SizedBox(height: 16),
          _HeatmapCard(),
        ],
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard();

  @override
  Widget build(BuildContext context) {
    return _InsightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('目标进度', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: const [
              Text('156', style: TextStyle(fontSize: 42, fontWeight: FontWeight.w900)),
              SizedBox(width: 8),
              Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('/ 目标 180 分', style: TextStyle(color: Colors.black54)),
              ),
              Spacer(),
              Text('+12', style: TextStyle(color: Color(0xFF20B486), fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: const LinearProgressIndicator(value: 0.87, minHeight: 10),
          ),
        ],
      ),
    );
  }
}

class _SubjectRadarMock extends StatelessWidget {
  const _SubjectRadarMock();

  @override
  Widget build(BuildContext context) {
    return _InsightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('科目能力雷达', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: Center(
              child: CustomPaint(
                size: const Size(180, 160),
                painter: _RadarPainter(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = Colors.grey.shade300;
    for (final r in [40.0, 65.0, 85.0]) {
      canvas.drawCircle(center, r, paint);
    }
    final area = Paint()..style = PaintingStyle.fill..color = const Color(0xFF5B5FEF).withOpacity(0.18);
    final line = Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = const Color(0xFF5B5FEF);
    final path = Path()
      ..moveTo(center.dx, center.dy - 70)
      ..lineTo(center.dx + 68, center.dy - 6)
      ..lineTo(center.dx + 30, center.dy + 64)
      ..lineTo(center.dx - 58, center.dy + 30)
      ..lineTo(center.dx - 46, center.dy - 38)
      ..close();
    canvas.drawPath(path, area);
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WeakPointList extends StatelessWidget {
  const _WeakPointList();

  @override
  Widget build(BuildContext context) {
    final items = [
      ('条件推理', 0.40),
      ('论证削弱', 0.55),
      ('真假话推理', 0.62),
    ];
    return _InsightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('薄弱点 TOP 3', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          ...items.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(child: Text(e.$1, style: const TextStyle(fontWeight: FontWeight.w700))),
                SizedBox(width: 120, child: LinearProgressIndicator(value: e.$2)),
                const SizedBox(width: 10),
                Text('${(e.$2 * 100).toInt()}%'),
              ],
            ),
          )),
          const SizedBox(height: 8),
          FilledButton(onPressed: () {}, child: const Text('让 AI 帮我逐个突破')),
        ],
      ),
    );
  }
}

class _HeatmapCard extends StatelessWidget {
  const _HeatmapCard();

  @override
  Widget build(BuildContext context) {
    return _InsightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text('本周学习热力图', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          SizedBox(height: 14),
          Text('一  二  三  四  五  六  日', style: TextStyle(color: Colors.black54)),
          SizedBox(height: 8),
          Text('🟩 🟩 🟨 🟩 🟩 🟩 ⬜', style: TextStyle(fontSize: 24)),
          SizedBox(height: 8),
          Text('累计 8.5h · 日均 1.4h', style: TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.child});

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
      child: child,
    );
  }
}
