import 'package:flutter/material.dart';

/// AI 专属极简双星簇 Sparkle Logo
class AiSparkleLogo extends StatelessWidget {
  const AiSparkleLogo({
    super.key,
    this.size = 24,
    this.color = Colors.white,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _AiSparklePainter(color: color),
    );
  }
}

class _AiSparklePainter extends CustomPainter {
  _AiSparklePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // 绘制主星（居中偏左下方，留出右上角空间）
    final path1 = Path();
    final mainSize = w * 0.72;
    final cx1 = w * 0.44;
    final cy1 = h * 0.56;

    path1.moveTo(cx1, cy1 - mainSize / 2);
    path1.quadraticBezierTo(cx1, cy1, cx1 + mainSize / 2, cy1);
    path1.quadraticBezierTo(cx1, cy1, cx1, cy1 + mainSize / 2);
    path1.quadraticBezierTo(cx1, cy1, cx1 - mainSize / 2, cy1);
    path1.quadraticBezierTo(cx1, cy1, cx1, cy1 - mainSize / 2);
    path1.close();
    canvas.drawPath(path1, paint);

    // 绘制伴随小星（右上角）
    final path2 = Path();
    final subSize = w * 0.32;
    final cx2 = w * 0.80;
    final cy2 = h * 0.24;

    path2.moveTo(cx2, cy2 - subSize / 2);
    path2.quadraticBezierTo(cx2, cy2, cx2 + subSize / 2, cy2);
    path2.quadraticBezierTo(cx2, cy2, cx2, cy2 + subSize / 2);
    path2.quadraticBezierTo(cx2, cy2, cx2 - subSize / 2, cy2);
    path2.quadraticBezierTo(cx2, cy2, cx2, cy2 - subSize / 2);
    path2.close();
    canvas.drawPath(path2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
