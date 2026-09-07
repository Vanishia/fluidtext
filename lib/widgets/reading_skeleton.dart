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

Color _barColor(BuildContext context) {
  return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08);
}

/// 收藏 / 已读列表页的骨架占位，按列表行结构铺文本条。
class CardListSkeleton extends StatelessWidget {
  const CardListSkeleton({super.key, this.itemCount = 6});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 20),
      children: [
        for (var index = 0; index < itemCount; index += 1)
          _SkeletonListRow(index: index),
      ],
    );
  }
}

class _SkeletonListRow extends StatelessWidget {
  const _SkeletonListRow({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final barColor = _barColor(context);
    // 各行宽度错开，更接近真实段落的参差不齐。
    final lastLineFactor = switch (index % 3) {
      0 => 0.62,
      1 => 0.45,
      _ => 0.78,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 13, 16, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Bar(height: 12, color: barColor),
          const SizedBox(height: 7),
          _Bar(height: 12, color: barColor),
          const SizedBox(height: 7),
          FractionallySizedBox(
            widthFactor: lastLineFactor,
            child: _Bar(height: 12, color: barColor),
          ),
          const SizedBox(height: 9),
          _Bar(width: 132, height: 9, color: barColor),
        ],
      ),
    );
  }
}

/// 阅读分析页的骨架占位，按模块卡片的版式铺面板。
class ReadingAnalysisSkeleton extends StatelessWidget {
  const ReadingAnalysisSkeleton({super.key, this.moduleCount = 3});

  final int moduleCount;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(10, 52, 10, bottomInset + 14),
      children: [
        for (var index = 0; index < moduleCount; index += 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: _SkeletonModule(index: index),
              ),
            ),
          ),
      ],
    );
  }
}

class _SkeletonModule extends StatelessWidget {
  const _SkeletonModule({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelColor = isDark
        ? Colors.black.withValues(alpha: 0.28)
        : Colors.white.withValues(alpha: 0.46);
    final barColor = _barColor(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 10),
              _Bar(width: 88, height: 13, color: barColor),
            ],
          ),
          const SizedBox(height: 16),
          _Bar(height: 12, color: barColor),
          const SizedBox(height: 8),
          FractionallySizedBox(
            widthFactor: index.isEven ? 0.72 : 0.55,
            child: _Bar(height: 12, color: barColor),
          ),
          const SizedBox(height: 14),
          _Bar(height: 44, color: barColor),
        ],
      ),
    );
  }
}
