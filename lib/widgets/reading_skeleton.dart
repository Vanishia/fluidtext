import 'package:flutter/material.dart';

/// 冷启动与会话恢复期间的阅读卡片骨架占位，
/// 避免白屏或单纯转圈的阻塞感。
class ReadingCardSkeleton extends StatelessWidget {
  const ReadingCardSkeleton({super.key, this.cardCount = 3});

  final int cardCount;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + 10,
        bottom: MediaQuery.paddingOf(context).bottom + 20,
      ),
      children: [
        for (var index = 0; index < cardCount; index += 1)
          const _SkeletonCard(),
      ],
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark
        ? Colors.black.withValues(alpha: 0.32)
        : Colors.white.withValues(alpha: 0.52);
    final barColor = cs.onSurface.withValues(alpha: 0.08);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Bar(width: 44, height: 10, color: barColor),
            const SizedBox(height: 12),
            _Bar(height: 12, color: barColor),
            const SizedBox(height: 8),
            _Bar(height: 12, color: barColor),
            const SizedBox(height: 8),
            FractionallySizedBox(
              widthFactor: 0.62,
              child: _Bar(height: 12, color: barColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({this.width, required this.height, required this.color});

  final double? width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
