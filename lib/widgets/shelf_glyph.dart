import 'package:flutter/material.dart';

class ShelfGlyph extends StatelessWidget {
  const ShelfGlyph({
    super.key,
    this.size = 22,
    this.color,
    this.strokeWidth = 1.8,
  });

  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _ShelfGlyphPainter(
          color: color ?? Theme.of(context).colorScheme.onSurface,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _ShelfGlyphPainter extends CustomPainter {
  const _ShelfGlyphPainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final barY = size.height * 0.76;
    canvas.drawLine(
      Offset(size.width * 0.12, barY),
      Offset(size.width * 0.88, barY),
      paint,
    );

    final books = [
      Rect.fromLTWH(
        size.width * 0.2,
        size.height * 0.24,
        size.width * 0.12,
        size.height * 0.42,
      ),
      Rect.fromLTWH(
        size.width * 0.38,
        size.height * 0.18,
        size.width * 0.14,
        size.height * 0.48,
      ),
      Rect.fromLTWH(
        size.width * 0.58,
        size.height * 0.28,
        size.width * 0.12,
        size.height * 0.38,
      ),
    ];

    for (final rect in books) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.03)),
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ShelfGlyphPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}
