import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/reading_analytics.dart';
import 'analysis_common_widgets.dart';

class OverviewModule extends StatelessWidget {
  const OverviewModule({super.key, required this.analytics});

  final ReadingAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: HeroKpi(
                label: '整体完成',
                value: '${(analytics.overallProgress * 100).round()}%',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: HeroKpi(label: '今日已读', value: '${analytics.todayRead} 张'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: HeroKpi(
                label: '收藏',
                value: '${analytics.totalFavorites} 张',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SummaryBand(
          items: [
            SummaryBandItem('书籍', '${analytics.totalBooks}'),
            SummaryBandItem('卡片', '${analytics.totalCards}'),
            SummaryBandItem('已读', '${analytics.totalRead}'),
            SummaryBandItem('未读', '${analytics.totalUnread}'),
            SummaryBandItem('收藏', '${analytics.totalFavorites}'),
          ],
        ),
      ],
    );
  }
}

class HeatmapModule extends StatefulWidget {
  const HeatmapModule({
    super.key,
    required this.analytics,
    required this.onOpenDay,
  });

  final ReadingAnalytics analytics;
  final ValueChanged<DayAnalysis> onOpenDay;

  @override
  State<HeatmapModule> createState() => _HeatmapModuleState();
}

class _HeatmapModuleState extends State<HeatmapModule> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _jumpToLatest();
  }

  @override
  void didUpdateWidget(covariant HeatmapModule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.analytics.daysByDate.length !=
        widget.analytics.daysByDate.length) {
      _jumpToLatest();
    }
  }

  void _jumpToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = DateUtils.dateOnly(DateTime.now());
    final end = today;
    final weekdayOffset = today.weekday - 1;
    final start = end.subtract(Duration(days: 370 + weekdayOffset));
    final startAligned = DateUtils.dateOnly(start);
    final weekCount = ((end.difference(startAligned).inDays + 1) / 7).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const SizedBox(width: 20),
                  const SizedBox(width: 8),
                  Row(
                    children: List<Widget>.generate(weekCount, (weekIndex) {
                      final columnStart = startAligned.add(
                        Duration(days: weekIndex * 7),
                      );
                      return Padding(
                        padding: EdgeInsets.only(
                          right: weekIndex == weekCount - 1 ? 0 : 3,
                        ),
                        child: SizedBox(
                          width: 12,
                          child: Text(
                            _monthLabelForWeek(columnStart, end),
                            textAlign: TextAlign.left,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 17),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        WeekdayLabel('一'),
                        SizedBox(height: 15),
                        WeekdayLabel('三'),
                        SizedBox(height: 15),
                        WeekdayLabel('五'),
                        SizedBox(height: 15),
                        WeekdayLabel('日'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    children: List<Widget>.generate(weekCount, (weekIndex) {
                      final columnStart = startAligned.add(
                        Duration(days: weekIndex * 7),
                      );
                      return Padding(
                        padding: EdgeInsets.only(
                          right: weekIndex == weekCount - 1 ? 0 : 3,
                        ),
                        child: Column(
                          children: List<Widget>.generate(7, (dayIndex) {
                            final day = columnStart.add(
                              Duration(days: dayIndex),
                            );
                            final analysis =
                                widget.analytics.daysByDate[day] ??
                                DayAnalysis.empty(day);
                            final count = analysis.readCount;
                            final isFuture = day.isAfter(end);
                            final isToday = day == today;
                            final color = isFuture
                                ? cs.surface.withValues(alpha: 0.10)
                                : _heatColorForCount(context, count: count);

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Tooltip(
                                message:
                                    '${formatDate(day)} · 已读 $count${analysis.favoriteCount > 0 ? ' · 收藏 ${analysis.favoriteCount}' : ''}',
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => widget.onOpenDay(analysis),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: color,
                                      borderRadius: BorderRadius.circular(3),
                                      border: Border.all(
                                        color: isToday
                                            ? cs.primary
                                            : cs.outlineVariant.withValues(
                                                alpha: count == 0 ? 0.22 : 0.18,
                                              ),
                                        width: isToday ? 1.2 : 0.6,
                                      ),
                                    ),
                                    child: const SizedBox(
                                      width: 12,
                                      height: 12,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              children: [
                Text(
                  '少',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(width: 6),
                ...List<Widget>.generate(
                  5,
                  (index) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _heatColorForCount(
                          context,
                          count: const [0, 1, 5, 10, 15][index],
                        ),
                        borderRadius: BorderRadius.circular(3),
                        border: index == 0
                            ? Border.all(
                                color: cs.outlineVariant.withValues(
                                  alpha: 0.22,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '多',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const Spacer(),
            Text(
              '活跃 ${widget.analytics.activeDays365} 天',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }

  Color _heatColorForCount(BuildContext context, {required int count}) {
    final cs = Theme.of(context).colorScheme;
    if (count <= 0) {
      return cs.surface.withValues(alpha: 0.14);
    }

    final t = (count.clamp(1, 15) / 15).toDouble();
    return Color.lerp(
      cs.primaryContainer.withValues(alpha: 0.58),
      cs.primary,
      math.pow(t, 0.72).toDouble(),
    )!.withValues(alpha: 0.88);
  }

  String _monthLabelForWeek(DateTime columnStart, DateTime end) {
    for (var offset = 0; offset < 7; offset += 1) {
      final day = columnStart.add(Duration(days: offset));
      if (day.isAfter(end)) break;
      if (day.day == 1) {
        return '${day.month}';
      }
    }
    return '';
  }
}

class StreaksModule extends StatelessWidget {
  const StreaksModule({super.key, required this.analytics});

  final ReadingAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            MetricTile(
              label: '近 365 天',
              value: '${analytics.activeDays365} 天',
              hint: '有已读记录的天数',
            ),
            MetricTile(
              label: '活跃日均',
              value: analytics.activeDays30 == 0
                  ? '0'
                  : analytics.avgReadsPerActiveDay30.toStringAsFixed(1),
              hint: '近 30 天每个活跃日',
            ),
          ],
        ),
        const SizedBox(height: 18),
        RangeStatRow(
          label: '近 7 天',
          value: '${analytics.readLast7} 张已读',
          detail: '${analytics.activeDays7} 个活跃日',
        ),
        const SizedBox(height: 10),
        RangeStatRow(
          label: '近 30 天',
          value: '${analytics.readLast30} 张已读',
          detail: '${analytics.activeDays30} 个活跃日',
        ),
        const SizedBox(height: 10),
        RangeStatRow(
          label: '近 30 天收藏',
          value: '${analytics.favoriteLast30} 张',
          detail: analytics.totalRead == 0
              ? '暂无已读转收藏'
              : '收藏转化 ${(analytics.favoriteToReadRatio * 100).toStringAsFixed(1)}%',
        ),
      ],
    );
  }
}

class ActivityModule extends StatelessWidget {
  const ActivityModule({super.key, required this.analytics});

  final ReadingAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final weekdayPeaks = analytics.busiestWeekdayLabel;
    final hourPeak = analytics.busiestHourBucketLabel;
    final hourBuckets = analytics.hourBuckets;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '高频星期：$weekdayPeaks',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Text(
          '高频时段：$hourPeak',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        BarSection(
          title: '周内分布',
          bars: List<BarDatum>.generate(
            7,
            (index) => BarDatum(
              label: analytics.weekdayShortLabels[index],
              value: analytics.weekdayCounts[index],
            ),
          ),
        ),
        const SizedBox(height: 16),
        BarSection(title: '时段分布', bars: hourBuckets),
      ],
    );
  }
}

class RankingsModule extends StatelessWidget {
  const RankingsModule({super.key, required this.analytics});

  final ReadingAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final mostRead = analytics.booksSortedByRead
        .take(4)
        .toList(growable: false);
    final highestCompletion = analytics.booksSortedByProgress
        .where((item) => item.readCount > 0)
        .take(4)
        .toList(growable: false);
    final mostFavorite = analytics.booksSortedByFavorite
        .where((item) => item.favoriteCount > 0)
        .take(4)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RankingGroup(title: '已读最多', items: mostRead),
        const SizedBox(height: 16),
        RankingGroup(title: '完成度最高', items: highestCompletion),
        const SizedBox(height: 16),
        RankingGroup(title: '收藏最多', items: mostFavorite),
      ],
    );
  }
}

class DepthModule extends StatelessWidget {
  const DepthModule({super.key, required this.analytics});

  final ReadingAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final almostDone = analytics.booksSortedByProgress
        .where((item) => item.progress >= 0.75 && item.progress < 1)
        .take(5)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            BucketChip(label: '未开始', count: analytics.depthBucketNotStarted),
            BucketChip(label: '刚开始', count: analytics.depthBucketEarly),
            BucketChip(label: '进行中', count: analytics.depthBucketMid),
            BucketChip(label: '接近完成', count: analytics.depthBucketLate),
            BucketChip(label: '已完成', count: analytics.depthBucketDone),
          ],
        ),
        const SizedBox(height: 18),
        RangeStatRow(
          label: '库存压力',
          value: '${analytics.totalUnread} 张未读',
          detail: '${analytics.depthBucketNotStarted} 本完全未开始',
        ),
        const SizedBox(height: 10),
        RangeStatRow(
          label: '平均每本',
          value: analytics.totalBooks == 0
              ? '0 张'
              : '${(analytics.totalCards / analytics.totalBooks).toStringAsFixed(1)} 张',
          detail: analytics.totalBooks == 0
              ? '暂无书籍'
              : '平均已读 ${(analytics.totalRead / analytics.totalBooks).toStringAsFixed(1)} 张',
        ),
        if (almostDone.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '快读完的书',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          ...almostDone.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: BookProgressRow(book: item),
            ),
          ),
        ],
      ],
    );
  }
}

class FavoritesModule extends StatelessWidget {
  const FavoritesModule({super.key, required this.analytics});

  final ReadingAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final topFavoriteBooks = analytics.booksSortedByFavorite
        .where((item) => item.favoriteCount > 0)
        .take(5)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            MetricTile(
              label: '收藏总量',
              value: '${analytics.totalFavorites}',
              hint: '累计被标记收藏',
            ),
            MetricTile(
              label: '收藏率',
              value: analytics.totalRead == 0
                  ? '0%'
                  : '${(analytics.favoriteToReadRatio * 100).toStringAsFixed(1)}%',
              hint: '收藏数 / 已读数',
            ),
          ],
        ),
        if (topFavoriteBooks.isNotEmpty) ...[
          const SizedBox(height: 18),
          RankingGroup(title: '最常收藏的书', items: topFavoriteBooks),
        ],
      ],
    );
  }
}
