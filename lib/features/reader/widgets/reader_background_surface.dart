import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../reader_background_settings.dart';

class ReaderBackgroundSurface extends StatelessWidget {
  const ReaderBackgroundSurface({
    super.key,
    required this.settings,
    required this.child,
  });

  final ReaderBackgroundSettings settings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: settings.palette.color,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (settings.hasCustomImage)
            Positioned.fill(
              child: Image.file(
                File(settings.imagePath!),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          if (settings.hasCustomImage)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: settings.palette.color.withValues(alpha: 0.14),
                ),
              ),
            ),
          Positioned.fill(
            child: CustomPaint(
              painter: _ReaderTexturePainter(
                backgroundColor: settings.palette.color,
                texture: settings.texture,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _ReaderTexturePainter extends CustomPainter {
  const _ReaderTexturePainter({
    required this.backgroundColor,
    required this.texture,
  });

  final Color backgroundColor;
  final ReaderTexturePreset texture;

  @override
  void paint(Canvas canvas, Size size) {
    if (texture == ReaderTexturePreset.none) return;

    final isDark = backgroundColor.computeLuminance() < 0.4;
    final overlayColor = isDark ? Colors.white : Colors.black;

    switch (texture) {
      case ReaderTexturePreset.none:
        break;
      case ReaderTexturePreset.fiber:
        _paintFiber(canvas, size, overlayColor);
      case ReaderTexturePreset.dots:
        _paintDots(canvas, size, overlayColor);
      case ReaderTexturePreset.diagonal:
        _paintDiagonal(canvas, size, overlayColor);
    }
  }

  void _paintFiber(Canvas canvas, Size size, Color overlayColor) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = overlayColor.withValues(alpha: 0.055);

    const step = 18.0;
    for (var y = 0.0; y < size.height + step; y += step) {
      for (var x = 0.0; x < size.width + step; x += step) {
        final hash = ((x / step).round() * 37) + ((y / step).round() * 17);
        final dx = x + ((hash % 7) - 3) * 0.9;
        final dy = y + ((hash % 11) - 5) * 0.6;
        final radius = 0.5 + (hash % 5) * 0.18;
        canvas.drawCircle(Offset(dx, dy), radius, paint);
      }
    }
  }

  void _paintDots(Canvas canvas, Size size, Color overlayColor) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = overlayColor.withValues(alpha: 0.08);

    const step = 22.0;
    for (var row = 0, y = 16.0; y < size.height + step; row += 1, y += step) {
      final shift = row.isEven ? 0.0 : step / 2;
      for (var x = 16.0 + shift; x < size.width + step; x += step) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }

  void _paintDiagonal(Canvas canvas, Size size, Color overlayColor) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = overlayColor.withValues(alpha: 0.07);

    const step = 24.0;
    final extent = math.max(size.width, size.height);
    for (var offset = -extent; offset < extent * 1.6; offset += step) {
      canvas.drawLine(
        Offset(0, offset),
        Offset(size.width, offset + size.width * 0.28),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ReaderTexturePainter oldDelegate) {
    return oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.texture != texture;
  }
}
