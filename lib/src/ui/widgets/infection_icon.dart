import 'dart:math' as math;

import 'package:flutter/material.dart';

class InfectionAppIcon extends StatelessWidget {
  const InfectionAppIcon({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _InfectionIconPainter(),
    );
  }
}

class _InfectionIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final bg = Paint()..color = const Color(0xFF101820);
    canvas.drawCircle(center, radius, bg);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08
      ..color = const Color(0xFF00E5B0);
    canvas.drawCircle(center, radius * 0.72, ring);

    final core = Paint()..color = const Color(0xFF00E5B0);
    canvas.drawCircle(center, radius * 0.18, core);

    final nodePaint = Paint()..color = const Color(0xFF7CFFCB);
    for (var i = 0; i < 6; i++) {
      final angle = (math.pi * 2 / 6) * i - math.pi / 2;
      final point = Offset(
        center.dx + math.cos(angle) * radius * 0.52,
        center.dy + math.sin(angle) * radius * 0.52,
      );
      canvas.drawCircle(point, radius * 0.08, nodePaint);
      canvas.drawLine(center, point, Paint()
        ..color = const Color(0xFF2FD9B8)
        ..strokeWidth = size.width * 0.03);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
