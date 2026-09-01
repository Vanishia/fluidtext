import 'dart:ui';

import 'package:flutter/material.dart';

class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    required this.color,
    required this.borderColor,
    this.borderRadius,
  });

  final Widget child;
  final Color color;
  final Color borderColor;

  /// 四角圆角，默认 20；传 null 时用默认值。
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(20);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: borderColor),
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
