import 'package:flutter/material.dart';

import '../models/reading_analytics.dart';
import 'analysis_common_widgets.dart';

class DayAnalysisSheet extends StatelessWidget {
  const DayAnalysisSheet({
    super.key,
    required this.analytics,
    required this.day,
  });

  final ReadingAnalytics analytics;
  final DayAnalysis day;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bookBreakdown =
        day.bookIds
            .map((bookId) {
              return DayBookBreakdown(
                bookId: bookId,
                title: analytics.bookTitle(bookId),
                readCount: day.readCountByBook[bookId] ?? 0,
                favoriteCount: day.favoriteCountByBook[bookId] ?? 0,
              );
            })
            .toList(growable: false)
          ..sort((a, b) {
            final countCompare = b.readCount.compareTo(a.readCount);
            if (countCompare != 0) return countCompare;
            return b.favoriteCount.compareTo(a.favoriteCount);
          });

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.42,
      maxChildSize: 0.94,
      builder: (context, controller) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatDate(day.date, withWeekday: true),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '当日阅读分析',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SummaryBand(
                      items: [
                        SummaryBandItem('已读', '${day.readCount}'),
                        SummaryBandItem('收藏', '${day.favoriteCount}'),
                        SummaryBandItem('涉及书籍', '${day.bookIds.length}'),
                        SummaryBandItem('活跃时段', day.peakHourLabel),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                  children: [
                    if (bookBreakdown.isNotEmpty) ...[
                      Text(
                        '书籍分布',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...bookBreakdown.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: DayBookBreakdownRow(item: item),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (day.readEvents.isNotEmpty) ...[
                      Text(
                        '阅读时间线',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...day.readEvents.map(
                        (event) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: TimelineEventTile(
                            timeLabel: formatTime(event.timestamp),
                            title: analytics.bookTitle(event.card.bookId),
                            preview: event.card.content,
                          ),
                        ),
                      ),
                    ] else ...[
                      Text(
                        '这一天没有已读记录。',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                    if (day.favoriteEvents.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        '当日收藏',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...day.favoriteEvents.map(
                        (event) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: TimelineEventTile(
                            timeLabel: formatTime(event.timestamp),
                            title: analytics.bookTitle(event.card.bookId),
                            preview: event.card.content,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
