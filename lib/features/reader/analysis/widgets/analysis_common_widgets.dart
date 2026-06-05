import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/reading_analytics.dart';
import '../reading_analysis_module.dart';

class AnalysisBackButton extends StatelessWidget {
  const AnalysisBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    final iconColor = Theme.of(context).colorScheme.onSurface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => Navigator.maybePop(context),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(Icons.arrow_back, size: 22, color: iconColor),
        ),
      ),
    );
  }
}

class HeroKpi extends StatelessWidget {
  const HeroKpi({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: softPanelDecoration(
        cs,
        alpha: 0.10,
        borderAlpha: 0.08,
        radius: 6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.hint,
  });

  final String label;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 150,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: softPanelDecoration(
        cs,
        alpha: 0.08,
        borderAlpha: 0.08,
        radius: 6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class SummaryBand extends StatelessWidget {
  const SummaryBand({super.key, required this.items});

  final List<SummaryBandItem> items;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: softPanelDecoration(
        cs,
        alpha: 0.08,
        borderAlpha: 0.08,
        radius: 6,
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: items
            .map(
              (item) => SizedBox(
                width: 94,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.value,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class SummaryBandItem {
  const SummaryBandItem(this.label, this.value);

  final String label;
  final String value;
}

class RangeStatRow extends StatelessWidget {
  const RangeStatRow({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: softPanelDecoration(
        cs,
        alpha: 0.08,
        borderAlpha: 0.08,
        radius: 6,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            detail,
            textAlign: TextAlign.right,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class WeekdayLabel extends StatelessWidget {
  const WeekdayLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class BarSection extends StatelessWidget {
  const BarSection({super.key, required this.title, required this.bars});

  final String title;
  final List<BarDatum> bars;

  @override
  Widget build(BuildContext context) {
    final maxValue = bars.fold<int>(
      0,
      (best, item) => math.max(best, item.value),
    );
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: softPanelDecoration(
        cs,
        alpha: 0.07,
        borderAlpha: 0.08,
        radius: 6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 126,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: bars
                  .map(
                    (item) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: VerticalBar(
                          value: item.value,
                          maxValue: maxValue,
                          label: item.label,
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }
}

class VerticalBar extends StatelessWidget {
  const VerticalBar({
    super.key,
    required this.value,
    required this.maxValue,
    required this.label,
  });

  final int value;
  final int maxValue;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ratio = maxValue == 0 ? 0.0 : value / maxValue;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          '$value',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: 18,
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.bottomCenter,
              padding: const EdgeInsets.all(2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                height: math.max(6, 74 * ratio),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class RankingGroup extends StatelessWidget {
  const RankingGroup({
    super.key,
    required this.title,
    required this.items,
    required this.formatter,
  });

  final String title;
  final List<BookSummary> items;
  final String Function(BookSummary item) formatter;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text('$title暂无数据', style: Theme.of(context).textTheme.bodyMedium);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: softPanelDecoration(
        Theme.of(context).colorScheme,
        alpha: 0.07,
        borderAlpha: 0.08,
        radius: 6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: BookProgressRow(book: item, trailing: formatter(item)),
            ),
          ),
        ],
      ),
    );
  }
}

class BookProgressRow extends StatelessWidget {
  const BookProgressRow({super.key, required this.book, this.trailing});

  final BookSummary book;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: softPanelDecoration(
        cs,
        alpha: 0.08,
        borderAlpha: 0.08,
        radius: 6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                trailing ?? '${(book.progress * 100).round()}%',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: book.progress,
              minHeight: 6,
              backgroundColor: cs.surfaceContainerHigh.withValues(alpha: 0.75),
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '已读 ${book.readCount}/${book.totalCount} · 收藏 ${book.favoriteCount}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class BucketChip extends StatelessWidget {
  const BucketChip({super.key, required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label：$count 本',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class TimelineEventTile extends StatelessWidget {
  const TimelineEventTile({
    super.key,
    required this.timeLabel,
    required this.title,
    required this.preview,
  });

  final String timeLabel;
  final String title;
  final String preview;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: softPanelDecoration(
        cs,
        alpha: 0.08,
        borderAlpha: 0.08,
        radius: 6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  timeLabel,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            preview,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }
}

class DayBookBreakdown {
  const DayBookBreakdown({
    required this.bookId,
    required this.title,
    required this.readCount,
    required this.favoriteCount,
  });

  final int bookId;
  final String title;
  final int readCount;
  final int favoriteCount;
}

class DayBookBreakdownRow extends StatelessWidget {
  const DayBookBreakdownRow({super.key, required this.item});

  final DayBookBreakdown item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: softPanelDecoration(
        cs,
        alpha: 0.08,
        borderAlpha: 0.08,
        radius: 6,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '已读 ${item.readCount}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (item.favoriteCount > 0) ...[
            const SizedBox(width: 10),
            Text(
              '收藏 ${item.favoriteCount}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String moduleTitle(ReadingAnalysisModuleType module) {
  return switch (module) {
    ReadingAnalysisModuleType.overview => '阅读总览',
    ReadingAnalysisModuleType.heatmap => '阅读热力图',
    ReadingAnalysisModuleType.streaks => '连续阅读',
    ReadingAnalysisModuleType.activity => '活跃分布',
    ReadingAnalysisModuleType.rankings => '书籍排行',
    ReadingAnalysisModuleType.depth => '阅读深度',
    ReadingAnalysisModuleType.favorites => '收藏洞察',
  };
}

IconData moduleIcon(ReadingAnalysisModuleType module) {
  return switch (module) {
    ReadingAnalysisModuleType.overview => Icons.dashboard_rounded,
    ReadingAnalysisModuleType.heatmap => Icons.calendar_month_rounded,
    ReadingAnalysisModuleType.streaks => Icons.local_fire_department_rounded,
    ReadingAnalysisModuleType.activity => Icons.timeline_rounded,
    ReadingAnalysisModuleType.rankings => Icons.leaderboard_rounded,
    ReadingAnalysisModuleType.depth => Icons.stacked_bar_chart_rounded,
    ReadingAnalysisModuleType.favorites => Icons.favorite_rounded,
  };
}

BoxDecoration softPanelDecoration(
  ColorScheme cs, {
  double alpha = 0.08,
  double borderAlpha = 0.08,
  double radius = 6,
}) {
  return BoxDecoration(
    color: cs.surface.withValues(alpha: alpha),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: cs.outlineVariant.withValues(alpha: borderAlpha)),
  );
}

BoxDecoration analysisPanelDecoration(
  ColorScheme cs, {
  required Color color,
  double radius = 8,
}) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.12)),
  );
}

String formatDate(DateTime date, {bool withWeekday = false}) {
  final weekday = switch (date.weekday) {
    DateTime.monday => '周一',
    DateTime.tuesday => '周二',
    DateTime.wednesday => '周三',
    DateTime.thursday => '周四',
    DateTime.friday => '周五',
    DateTime.saturday => '周六',
    DateTime.sunday => '周日',
    _ => '',
  };
  final text =
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  return withWeekday ? '$text · $weekday' : text;
}

String formatTime(DateTime date) {
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
