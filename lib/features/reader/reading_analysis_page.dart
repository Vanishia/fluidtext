import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app_settings.dart';
import '../../models/book.dart';
import '../../models/book_card.dart';
import '../../repositories/book_card_repository.dart';
import '../../services/book_remark_service.dart';
import 'reader_background_settings.dart';
import 'reading_analysis_module.dart';
import 'widgets/reader_background_surface.dart';

class ReadingAnalysisPage extends StatefulWidget {
  const ReadingAnalysisPage({
    super.key,
    required this.repository,
    this.bookIds = const <int>[],
    this.shelfTitle = '全部书籍',
  });

  final BookCardRepository repository;
  final List<int> bookIds;
  final String shelfTitle;

  @override
  State<ReadingAnalysisPage> createState() => _ReadingAnalysisPageState();
}

class _ReadingAnalysisPageState extends State<ReadingAnalysisPage> {
  _ReadingAnalytics? _analytics;
  String? _error;
  bool _isLoading = true;
  late List<ReadingAnalysisModuleType> _moduleOrder =
      List<ReadingAnalysisModuleType>.from(analysisModuleOrderSetting.value);

  Future<Color>? _seedColorFuture;
  String? _seedColorCacheKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final books = widget.bookIds.isEmpty
          ? await widget.repository.loadBooks()
          : await widget.repository.loadBooksByIds(widget.bookIds);
      final bookIds = books.map((book) => book.id).toList(growable: false);
      final remarksFuture = BookRemarkService.instance.load();
      final statsFuture = widget.repository.loadBookStats(bookIds);
      final readCardsFuture = widget.repository.loadReadCards(bookIds);
      final favoriteCardsFuture = widget.repository.loadFavoriteCards(bookIds);

      final remarks = await remarksFuture;
      final stats = await statsFuture;
      final readCards = await readCardsFuture;
      final favoriteCards = await favoriteCardsFuture;
      final titlesById = {
        for (final book in books) book.id: remarks[book.id] ?? book.title,
      };

      if (!mounted) return;
      setState(() {
        _analytics = _ReadingAnalytics.from(
          books: books,
          bookTitlesById: titlesById,
          statsByBookId: stats,
          readCards: readCards,
          favoriteCards: favoriteCards,
        );
        _moduleOrder = normalizeReadingAnalysisModuleOrder(_moduleOrder);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _isLoading = false;
      });
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _moduleOrder.removeAt(oldIndex);
      _moduleOrder.insert(newIndex, item);
    });
    saveAnalysisModuleOrderSetting(_moduleOrder);
  }

  void _ensureSeedColorFuture(ReaderBackgroundSettings settings) {
    final key = [
      settings.source.name,
      settings.paletteKey,
      settings.texture.name,
      settings.imagePath ?? '',
    ].join('|');
    if (_seedColorCacheKey == key && _seedColorFuture != null) {
      return;
    }
    _seedColorCacheKey = key;
    _seedColorFuture = _resolveSeedColor(settings);
  }

  Future<Color> _resolveSeedColor(ReaderBackgroundSettings settings) async {
    if (!settings.hasCustomImage) {
      return _normalizeSeedColor(settings.palette.color);
    }

    final imagePath = settings.imagePath;
    if (imagePath == null || imagePath.isEmpty) {
      return _normalizeSeedColor(settings.palette.color);
    }

    final derived = await _extractSeedColorFromImage(imagePath);
    return _normalizeSeedColor(derived ?? settings.palette.color);
  }

  Future<Color?> _extractSeedColorFromImage(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 40,
        targetHeight: 40,
      );
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      codec.dispose();
      if (byteData == null) return null;
      return _dominantColorFromRgba(byteData);
    } catch (_) {
      return null;
    }
  }

  Color _dominantColorFromRgba(ByteData rgba) {
    final buckets = <int, _ColorBucket>{};
    for (var offset = 0; offset < rgba.lengthInBytes; offset += 4) {
      final red = rgba.getUint8(offset);
      final green = rgba.getUint8(offset + 1);
      final blue = rgba.getUint8(offset + 2);
      final alpha = rgba.getUint8(offset + 3);
      if (alpha < 180) continue;

      final color = Color.fromARGB(255, red, green, blue);
      final hsl = HSLColor.fromColor(color);
      if (hsl.lightness <= 0.06 || hsl.lightness >= 0.95) continue;

      final key = ((red ~/ 32) << 10) | ((green ~/ 32) << 5) | (blue ~/ 32);
      final weight =
          (0.35 + hsl.saturation) *
          (1 - (hsl.lightness - 0.52).abs()).clamp(0.15, 1.0);
      buckets
          .putIfAbsent(key, _ColorBucket.new)
          .add(red: red, green: green, blue: blue, weight: weight);
    }

    if (buckets.isEmpty) {
      return const Color(0xFF5F8AA6);
    }

    final bucket = buckets.values.reduce(
      (best, current) => current.weight > best.weight ? current : best,
    );
    return bucket.color;
  }

  Color _normalizeSeedColor(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withSaturation(hsl.saturation.clamp(0.28, 0.70))
        .withLightness(hsl.lightness.clamp(0.28, 0.64))
        .toColor();
  }

  ThemeData _pageTheme(ThemeData baseTheme, Color seedColor) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: baseTheme.brightness,
    );

    return baseTheme.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface.withValues(
          alpha: baseTheme.brightness == Brightness.dark ? 0.64 : 0.84,
        ),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.45),
      ),
      chipTheme: baseTheme.chipTheme.copyWith(
        backgroundColor: scheme.secondaryContainer.withValues(alpha: 0.72),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }

  void _openDayAnalysis(
    BuildContext context,
    _ReadingAnalytics analytics,
    _DayAnalysis day,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DayAnalysisSheet(analytics: analytics, day: day),
    );
  }

  Widget _buildBody(
    BuildContext context,
    _ReadingAnalytics analytics,
    ReaderBackgroundSettings backgroundSettings,
  ) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        buildDefaultDragHandles: false,
        onReorder: _onReorder,
        itemCount: _moduleOrder.length,
        itemBuilder: (context, index) {
          final module = _moduleOrder[index];
          return Padding(
            key: ValueKey(module.name),
            padding: const EdgeInsets.only(bottom: 14),
            child: _buildModuleCard(
              context,
              analytics: analytics,
              backgroundSettings: backgroundSettings,
              module: module,
              index: index,
            ),
          );
        },
      ),
    );
  }

  Widget _buildModuleCard(
    BuildContext context, {
    required _ReadingAnalytics analytics,
    required ReaderBackgroundSettings backgroundSettings,
    required ReadingAnalysisModuleType module,
    required int index,
  }) {
    final content = switch (module) {
      ReadingAnalysisModuleType.overview => _OverviewModule(
        analytics: analytics,
      ),
      ReadingAnalysisModuleType.heatmap => _HeatmapModule(
        analytics: analytics,
        onOpenDay: (day) => _openDayAnalysis(context, analytics, day),
      ),
      ReadingAnalysisModuleType.streaks => _StreaksModule(analytics: analytics),
      ReadingAnalysisModuleType.activity => _ActivityModule(
        analytics: analytics,
      ),
      ReadingAnalysisModuleType.rankings => _RankingsModule(
        analytics: analytics,
      ),
      ReadingAnalysisModuleType.depth => _DepthModule(analytics: analytics),
      ReadingAnalysisModuleType.favorites => _FavoritesModule(
        analytics: analytics,
      ),
    };

    final title = switch (module) {
      ReadingAnalysisModuleType.overview => '阅读总览',
      ReadingAnalysisModuleType.heatmap => '阅读热力图',
      ReadingAnalysisModuleType.streaks => '连续阅读',
      ReadingAnalysisModuleType.activity => '活跃分布',
      ReadingAnalysisModuleType.rankings => '书籍排行',
      ReadingAnalysisModuleType.depth => '阅读深度',
      ReadingAnalysisModuleType.favorites => '收藏洞察',
    };

    final subtitle = switch (module) {
      ReadingAnalysisModuleType.overview => '整体进度与近期开启情况',
      ReadingAnalysisModuleType.heatmap => '近 53 周已读热力，点按可看当日详情',
      ReadingAnalysisModuleType.streaks => '当前连读、最佳纪录与近 30 天效率',
      ReadingAnalysisModuleType.activity => '一周时段偏好与近两周趋势',
      ReadingAnalysisModuleType.rankings => '已读、完成度与收藏表现',
      ReadingAnalysisModuleType.depth => '库存状态与接近完成的书',
      ReadingAnalysisModuleType.favorites => '收藏量、最近收藏与偏好分布',
    };

    final cs = Theme.of(context).colorScheme;
    final panelColor = cs.surface.withValues(
      alpha: backgroundSettings.hasCustomImage ? 0.86 : 0.92,
    );

    return Card(
      color: panelColor,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                ReorderableDelayedDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            content,
          ],
        ),
      ),
    );
  }

  Widget _buildStateBody(
    BuildContext context,
    ReaderBackgroundSettings backgroundSettings,
  ) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insights_outlined, size: 36),
              const SizedBox(height: 12),
              Text('阅读分析加载失败', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    final analytics = _analytics;
    if (analytics == null) {
      return const SizedBox.shrink();
    }

    return _buildBody(context, analytics, backgroundSettings);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReaderBackgroundSettings>(
      valueListenable: readerBackgroundSetting,
      builder: (context, backgroundSettings, _) {
        _ensureSeedColorFuture(backgroundSettings);
        return FutureBuilder<Color>(
          future: _seedColorFuture,
          builder: (context, snapshot) {
            final seedColor =
                snapshot.data ??
                _normalizeSeedColor(backgroundSettings.palette.color);
            final themed = _pageTheme(Theme.of(context), seedColor);
            final cs = themed.colorScheme;

            return Theme(
              data: themed,
              child: Scaffold(
                backgroundColor: backgroundSettings.palette.color,
                body: ReaderBackgroundSurface(
                  settings: backgroundSettings,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              cs.primaryContainer.withValues(alpha: 0.20),
                              cs.surface.withValues(alpha: 0.16),
                              cs.tertiaryContainer.withValues(alpha: 0.18),
                            ],
                          ),
                        ),
                      ),
                      SafeArea(
                        child: Column(
                          children: [
                            _AnalysisHeader(
                              shelfTitle: widget.shelfTitle,
                              onRefresh: _isLoading ? null : _load,
                            ),
                            Expanded(
                              child: _buildStateBody(
                                context,
                                backgroundSettings,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _AnalysisHeader extends StatelessWidget {
  const _AnalysisHeader({required this.shelfTitle, this.onRefresh});

  final String shelfTitle;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      child: SizedBox(
        height: 46,
        child: Row(
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_back),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => Navigator.maybePop(context),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '阅读分析',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    shelfTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '刷新',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewModule extends StatelessWidget {
  const _OverviewModule({required this.analytics});

  final _ReadingAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricTile(
              label: '书籍',
              value: '${analytics.totalBooks}',
              hint: '已导入总数',
            ),
            _MetricTile(
              label: '卡片',
              value: '${analytics.totalCards}',
              hint: '全库阅读单元',
            ),
            _MetricTile(
              label: '已读',
              value: '${analytics.totalRead}',
              hint: '累计已读卡片',
            ),
            _MetricTile(
              label: '未读',
              value: '${analytics.totalUnread}',
              hint: '当前库存',
            ),
            _MetricTile(
              label: '收藏',
              value: '${analytics.totalFavorites}',
              hint: '累计收藏卡片',
            ),
            _MetricTile(
              label: '完成率',
              value: '${(analytics.overallProgress * 100).round()}%',
              hint: '全库整体进度',
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SummaryBand(
          items: [
            _SummaryBandItem('今日已读', '${analytics.todayRead}'),
            _SummaryBandItem('本周已读', '${analytics.thisWeekRead}'),
            _SummaryBandItem('本月已读', '${analytics.thisMonthRead}'),
            _SummaryBandItem('近 7 天', '${analytics.readLast7}'),
            _SummaryBandItem('近 30 天', '${analytics.readLast30}'),
            _SummaryBandItem('近 30 天收藏', '${analytics.favoriteLast30}'),
          ],
        ),
      ],
    );
  }
}

class _HeatmapModule extends StatelessWidget {
  const _HeatmapModule({required this.analytics, required this.onOpenDay});

  final _ReadingAnalytics analytics;
  final ValueChanged<_DayAnalysis> onOpenDay;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = DateUtils.dateOnly(DateTime.now());
    final end = today;
    final weekdayOffset = today.weekday - 1;
    final start = end.subtract(Duration(days: 370 + weekdayOffset));
    final startAligned = DateUtils.dateOnly(start);
    final maxCount = analytics.maxHeatmapCount;
    final weekCount = ((end.difference(startAligned).inDays + 1) / 7).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '活跃天数 ${analytics.activeDays365} · 最长连续 ${analytics.bestStreak} 天',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            Text(
              '点按查看当日',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: const [
                    _WeekdayLabel('一'),
                    SizedBox(height: 18),
                    _WeekdayLabel('三'),
                    SizedBox(height: 18),
                    _WeekdayLabel('五'),
                    SizedBox(height: 18),
                    _WeekdayLabel('日'),
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
                      right: weekIndex == weekCount - 1 ? 0 : 4,
                    ),
                    child: Column(
                      children: List<Widget>.generate(7, (dayIndex) {
                        final day = columnStart.add(Duration(days: dayIndex));
                        final analysis =
                            analytics.daysByDate[day] ??
                            _DayAnalysis.empty(day);
                        final count = analysis.readCount;
                        final isFuture = day.isAfter(end);
                        final isToday = day == today;
                        final color = isFuture
                            ? cs.surfaceContainerHighest.withValues(alpha: 0.28)
                            : _heatColorForCount(
                                context,
                                count: count,
                                maxCount: maxCount,
                              );

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Tooltip(
                            message:
                                '${_formatDate(day)} · 已读 $count${analysis.favoriteCount > 0 ? ' · 收藏 ${analysis.favoriteCount}' : ''}',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () => onOpenDay(analysis),
                              child: Ink(
                                width: 13,
                                height: 13,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isToday
                                        ? cs.primary
                                        : cs.outlineVariant.withValues(
                                            alpha: count == 0 ? 0.18 : 0.28,
                                          ),
                                    width: isToday ? 1.2 : 0.6,
                                  ),
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
        ),
        const SizedBox(height: 12),
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
                      count: index,
                      maxCount: 4,
                    ),
                    borderRadius: BorderRadius.circular(4),
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
      ],
    );
  }

  Color _heatColorForCount(
    BuildContext context, {
    required int count,
    required int maxCount,
  }) {
    final cs = Theme.of(context).colorScheme;
    if (count <= 0) {
      return cs.surfaceContainerHighest.withValues(alpha: 0.45);
    }

    final ratio = maxCount <= 1 ? 1.0 : count / maxCount;
    final t = ratio.clamp(0.0, 1.0);
    return Color.lerp(
      cs.secondaryContainer.withValues(alpha: 0.70),
      cs.primary,
      math.pow(t, 0.78).toDouble(),
    )!.withValues(alpha: 0.92);
  }
}

class _StreaksModule extends StatelessWidget {
  const _StreaksModule({required this.analytics});

  final _ReadingAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricTile(
              label: '当前连续',
              value: '${analytics.currentStreak} 天',
              hint: analytics.currentStreak > 0 ? '今天仍在延续' : '今天还没读',
            ),
            _MetricTile(
              label: '最佳纪录',
              value: '${analytics.bestStreak} 天',
              hint: '历史最长连续阅读',
            ),
            _MetricTile(
              label: '近 365 天',
              value: '${analytics.activeDays365} 天',
              hint: '有已读记录的天数',
            ),
            _MetricTile(
              label: '活跃日均',
              value: analytics.activeDays30 == 0
                  ? '0'
                  : analytics.avgReadsPerActiveDay30.toStringAsFixed(1),
              hint: '近 30 天每个活跃日',
            ),
          ],
        ),
        const SizedBox(height: 18),
        _RangeStatRow(
          label: '近 7 天',
          value: '${analytics.readLast7} 张已读',
          detail: '${analytics.activeDays7} 个活跃日',
        ),
        const SizedBox(height: 10),
        _RangeStatRow(
          label: '近 30 天',
          value: '${analytics.readLast30} 张已读',
          detail: '${analytics.activeDays30} 个活跃日',
        ),
        const SizedBox(height: 10),
        _RangeStatRow(
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

class _ActivityModule extends StatelessWidget {
  const _ActivityModule({required this.analytics});

  final _ReadingAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final weekdayPeaks = analytics.busiestWeekdayLabel;
    final hourPeak = analytics.busiestHourBucketLabel;
    final hourBuckets = analytics.hourBuckets;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text('高频星期 $weekdayPeaks')),
            Chip(label: Text('高频时段 $hourPeak')),
            Chip(
              label: Text(
                '近 14 天 ${analytics.trendLast14.fold<int>(0, (sum, item) => sum + item.count)} 张',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _BarSection(
          title: '周内分布',
          bars: List<_BarDatum>.generate(
            7,
            (index) => _BarDatum(
              label: analytics.weekdayShortLabels[index],
              value: analytics.weekdayCounts[index],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _BarSection(title: '时段分布', bars: hourBuckets),
        const SizedBox(height: 16),
        _BarSection(
          title: '近 14 天趋势',
          bars: analytics.trendLast14
              .map(
                (item) => _BarDatum(label: item.shortLabel, value: item.count),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _RankingsModule extends StatelessWidget {
  const _RankingsModule({required this.analytics});

  final _ReadingAnalytics analytics;

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
        _RankingGroup(
          title: '已读最多',
          items: mostRead,
          formatter: (item) => '${item.readCount}/${item.totalCount}',
        ),
        const SizedBox(height: 16),
        _RankingGroup(
          title: '完成度最高',
          items: highestCompletion,
          formatter: (item) => '${(item.progress * 100).round()}%',
        ),
        const SizedBox(height: 16),
        _RankingGroup(
          title: '收藏最多',
          items: mostFavorite,
          formatter: (item) => '${item.favoriteCount} 张',
        ),
      ],
    );
  }
}

class _DepthModule extends StatelessWidget {
  const _DepthModule({required this.analytics});

  final _ReadingAnalytics analytics;

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
            _BucketChip(label: '未开始', count: analytics.depthBucketNotStarted),
            _BucketChip(label: '刚开始', count: analytics.depthBucketEarly),
            _BucketChip(label: '进行中', count: analytics.depthBucketMid),
            _BucketChip(label: '接近完成', count: analytics.depthBucketLate),
            _BucketChip(label: '已完成', count: analytics.depthBucketDone),
          ],
        ),
        const SizedBox(height: 18),
        _RangeStatRow(
          label: '库存压力',
          value: '${analytics.totalUnread} 张未读',
          detail: '${analytics.depthBucketNotStarted} 本完全未开始',
        ),
        const SizedBox(height: 10),
        _RangeStatRow(
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
              child: _BookProgressRow(book: item),
            ),
          ),
        ],
      ],
    );
  }
}

class _FavoritesModule extends StatelessWidget {
  const _FavoritesModule({required this.analytics});

  final _ReadingAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final topFavoriteBooks = analytics.booksSortedByFavorite
        .where((item) => item.favoriteCount > 0)
        .take(5)
        .toList(growable: false);
    final recentFavorites = analytics.recentFavoriteEvents
        .take(5)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricTile(
              label: '收藏总量',
              value: '${analytics.totalFavorites}',
              hint: '累计被标记收藏',
            ),
            _MetricTile(
              label: '近 7 天',
              value: '${analytics.favoriteLast7}',
              hint: '新收藏卡片',
            ),
            _MetricTile(
              label: '近 30 天',
              value: '${analytics.favoriteLast30}',
              hint: '新收藏卡片',
            ),
            _MetricTile(
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
          _RankingGroup(
            title: '最常收藏的书',
            items: topFavoriteBooks,
            formatter: (item) => '${item.favoriteCount} 张',
          ),
        ],
        if (recentFavorites.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            '最近收藏',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          ...recentFavorites.map(
            (event) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TimelineEventTile(
                timeLabel: _formatTime(event.timestamp),
                title: analytics.bookTitle(event.card.bookId),
                preview: event.card.content,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DayAnalysisSheet extends StatelessWidget {
  const _DayAnalysisSheet({required this.analytics, required this.day});

  final _ReadingAnalytics analytics;
  final _DayAnalysis day;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bookBreakdown =
        day.bookIds
            .map((bookId) {
              return _DayBookBreakdown(
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
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                      _formatDate(day.date, withWeekday: true),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
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
                    _SummaryBand(
                      items: [
                        _SummaryBandItem('已读', '${day.readCount}'),
                        _SummaryBandItem('收藏', '${day.favoriteCount}'),
                        _SummaryBandItem('涉及书籍', '${day.bookIds.length}'),
                        _SummaryBandItem('活跃时段', day.peakHourLabel),
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
                          child: _DayBookBreakdownRow(item: item),
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
                          child: _TimelineEventTile(
                            timeLabel: _formatTime(event.timestamp),
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
                          child: _TimelineEventTile(
                            timeLabel: _formatTime(event.timestamp),
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

class _MetricTile extends StatelessWidget {
  const _MetricTile({
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
      width: 144,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.28)),
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
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
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

class _SummaryBand extends StatelessWidget {
  const _SummaryBand({required this.items});

  final List<_SummaryBandItem> items;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 12,
        children: items
            .map(
              (item) => SizedBox(
                width: 92,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.value,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w800,
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

class _SummaryBandItem {
  const _SummaryBandItem(this.label, this.value);

  final String label;
  final String value;
}

class _RangeStatRow extends StatelessWidget {
  const _RangeStatRow({
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
    return Row(
      children: [
        SizedBox(
          width: 86,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Text(
          detail,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _WeekdayLabel extends StatelessWidget {
  const _WeekdayLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _BarSection extends StatelessWidget {
  const _BarSection({required this.title, required this.bars});

  final String title;
  final List<_BarDatum> bars;

  @override
  Widget build(BuildContext context) {
    final maxValue = bars.fold<int>(
      0,
      (best, item) => math.max(best, item.value),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: bars
                .map(
                  (item) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _VerticalBar(
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
    );
  }
}

class _VerticalBar extends StatelessWidget {
  const _VerticalBar({
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
        const SizedBox(height: 6),
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              height: math.max(6, 72 * ratio),
              decoration: BoxDecoration(
                color: Color.lerp(
                  cs.secondaryContainer,
                  cs.primary,
                  ratio.clamp(0.0, 1.0),
                ),
                borderRadius: BorderRadius.circular(999),
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

class _RankingGroup extends StatelessWidget {
  const _RankingGroup({
    required this.title,
    required this.items,
    required this.formatter,
  });

  final String title;
  final List<_BookSummary> items;
  final String Function(_BookSummary item) formatter;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text('$title暂无数据', style: Theme.of(context).textTheme.bodyMedium);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _BookProgressRow(book: item, trailing: formatter(item)),
          ),
        ),
      ],
    );
  }
}

class _BookProgressRow extends StatelessWidget {
  const _BookProgressRow({required this.book, this.trailing});

  final _BookSummary book;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(18),
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
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                trailing ?? '${(book.progress * 100).round()}%',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w800,
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
              backgroundColor: cs.surfaceContainerHigh,
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

class _BucketChip extends StatelessWidget {
  const _BucketChip({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label $count'));
  }
}

class _TimelineEventTile extends StatelessWidget {
  const _TimelineEventTile({
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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.44),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                timeLabel,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
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
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
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

class _DayBookBreakdown {
  const _DayBookBreakdown({
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

class _DayBookBreakdownRow extends StatelessWidget {
  const _DayBookBreakdownRow({required this.item});

  final _DayBookBreakdown item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(16),
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
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
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
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BarDatum {
  const _BarDatum({required this.label, required this.value});

  final String label;
  final int value;
}

class _TrendPoint {
  const _TrendPoint({required this.date, required this.count});

  final DateTime date;
  final int count;

  String get shortLabel => '${date.month}/${date.day}';
}

class _TimedCardEvent {
  const _TimedCardEvent({required this.timestamp, required this.card});

  final DateTime timestamp;
  final BookCard card;
}

class _DayAnalysis {
  _DayAnalysis(this.date);

  final DateTime date;
  final List<_TimedCardEvent> readEvents = <_TimedCardEvent>[];
  final List<_TimedCardEvent> favoriteEvents = <_TimedCardEvent>[];
  final Map<int, int> readCountByBook = <int, int>{};
  final Map<int, int> favoriteCountByBook = <int, int>{};
  final List<int> hourlyReads = List<int>.filled(24, 0);

  int get readCount => readEvents.length;
  int get favoriteCount => favoriteEvents.length;

  Iterable<int> get bookIds sync* {
    final ids = <int>{...readCountByBook.keys, ...favoriteCountByBook.keys};
    final ordered = ids.toList(growable: false)..sort();
    yield* ordered;
  }

  String get peakHourLabel {
    var bestHour = 0;
    var bestValue = 0;
    for (var hour = 0; hour < hourlyReads.length; hour += 1) {
      if (hourlyReads[hour] > bestValue) {
        bestValue = hourlyReads[hour];
        bestHour = hour;
      }
    }
    return bestValue == 0 ? '无' : '${bestHour.toString().padLeft(2, '0')}:00';
  }

  static _DayAnalysis empty(DateTime date) => _DayAnalysis(date);
}

class _BookSummary {
  const _BookSummary({
    required this.bookId,
    required this.title,
    required this.totalCount,
    required this.readCount,
    required this.favoriteCount,
    this.lastReadAt,
    this.lastFavoritedAt,
  });

  final int bookId;
  final String title;
  final int totalCount;
  final int readCount;
  final int favoriteCount;
  final DateTime? lastReadAt;
  final DateTime? lastFavoritedAt;

  int get unreadCount => totalCount - readCount;
  double get progress => totalCount == 0 ? 0 : readCount / totalCount;
  double get favoriteRate => totalCount == 0 ? 0 : favoriteCount / totalCount;
}

class _ReadingAnalytics {
  _ReadingAnalytics({
    required this.books,
    required this.bookTitlesById,
    required this.bookSummaries,
    required this.daysByDate,
    required this.recentFavoriteEvents,
    required this.totalCards,
    required this.totalRead,
    required this.totalFavorites,
    required this.readLast7,
    required this.readLast30,
    required this.favoriteLast7,
    required this.favoriteLast30,
    required this.todayRead,
    required this.thisWeekRead,
    required this.thisMonthRead,
    required this.currentStreak,
    required this.bestStreak,
    required this.activeDays365,
    required this.activeDays30,
    required this.activeDays7,
    required this.avgReadsPerActiveDay30,
    required this.weekdayCounts,
    required this.hourCounts,
    required this.trendLast14,
  });

  final List<Book> books;
  final Map<int, String> bookTitlesById;
  final List<_BookSummary> bookSummaries;
  final Map<DateTime, _DayAnalysis> daysByDate;
  final List<_TimedCardEvent> recentFavoriteEvents;
  final int totalCards;
  final int totalRead;
  final int totalFavorites;
  final int readLast7;
  final int readLast30;
  final int favoriteLast7;
  final int favoriteLast30;
  final int todayRead;
  final int thisWeekRead;
  final int thisMonthRead;
  final int currentStreak;
  final int bestStreak;
  final int activeDays365;
  final int activeDays30;
  final int activeDays7;
  final double avgReadsPerActiveDay30;
  final List<int> weekdayCounts;
  final List<int> hourCounts;
  final List<_TrendPoint> trendLast14;

  factory _ReadingAnalytics.from({
    required List<Book> books,
    required Map<int, String> bookTitlesById,
    required Map<int, BookCardStats> statsByBookId,
    required List<BookCard> readCards,
    required List<BookCard> favoriteCards,
  }) {
    final totalCards = statsByBookId.values.fold<int>(
      0,
      (sum, item) => sum + item.totalCount,
    );
    final totalRead = statsByBookId.values.fold<int>(
      0,
      (sum, item) => sum + item.readCount,
    );
    final totalFavorites = statsByBookId.values.fold<int>(
      0,
      (sum, item) => sum + item.favoriteCount,
    );

    final lastReadByBook = <int, DateTime>{};
    final lastFavoriteByBook = <int, DateTime>{};
    final daysByDate = <DateTime, _DayAnalysis>{};
    final weekdayCounts = List<int>.filled(7, 0);
    final hourCounts = List<int>.filled(24, 0);
    final today = DateUtils.dateOnly(DateTime.now());
    final sevenDayStart = today.subtract(const Duration(days: 6));
    final thirtyDayStart = today.subtract(const Duration(days: 29));
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final monthStart = DateTime(today.year, today.month);

    var readLast7 = 0;
    var readLast30 = 0;
    var favoriteLast7 = 0;
    var favoriteLast30 = 0;
    var todayRead = 0;
    var thisWeekRead = 0;
    var thisMonthRead = 0;

    for (final card in readCards) {
      final readAt = card.readAt?.toLocal();
      if (readAt == null) continue;
      final day = DateUtils.dateOnly(readAt);
      final dayAnalysis = daysByDate.putIfAbsent(day, () => _DayAnalysis(day));
      final event = _TimedCardEvent(timestamp: readAt, card: card);
      dayAnalysis.readEvents.add(event);
      dayAnalysis.readCountByBook.update(
        card.bookId,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      dayAnalysis.hourlyReads[readAt.hour] += 1;
      weekdayCounts[readAt.weekday - 1] += 1;
      hourCounts[readAt.hour] += 1;
      if (!day.isBefore(sevenDayStart)) readLast7 += 1;
      if (!day.isBefore(thirtyDayStart)) readLast30 += 1;
      if (day == today) todayRead += 1;
      if (!day.isBefore(weekStart)) thisWeekRead += 1;
      if (!day.isBefore(monthStart)) thisMonthRead += 1;

      final current = lastReadByBook[card.bookId];
      if (current == null || readAt.isAfter(current)) {
        lastReadByBook[card.bookId] = readAt;
      }
    }

    final favoriteEvents = <_TimedCardEvent>[];
    for (final card in favoriteCards) {
      final favoritedAt = card.favoritedAt?.toLocal();
      if (favoritedAt == null) continue;
      final day = DateUtils.dateOnly(favoritedAt);
      final dayAnalysis = daysByDate.putIfAbsent(day, () => _DayAnalysis(day));
      final event = _TimedCardEvent(timestamp: favoritedAt, card: card);
      dayAnalysis.favoriteEvents.add(event);
      dayAnalysis.favoriteCountByBook.update(
        card.bookId,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      if (!day.isBefore(sevenDayStart)) favoriteLast7 += 1;
      if (!day.isBefore(thirtyDayStart)) favoriteLast30 += 1;
      favoriteEvents.add(event);

      final current = lastFavoriteByBook[card.bookId];
      if (current == null || favoritedAt.isAfter(current)) {
        lastFavoriteByBook[card.bookId] = favoritedAt;
      }
    }

    for (final day in daysByDate.values) {
      day.readEvents.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      day.favoriteEvents.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }
    favoriteEvents.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final activeReadDays =
        daysByDate.entries
            .where((entry) => entry.value.readCount > 0)
            .map((entry) => entry.key)
            .toList(growable: false)
          ..sort();

    final activeDays365 = activeReadDays
        .where(
          (day) => !day.isBefore(today.subtract(const Duration(days: 364))),
        )
        .length;
    final activeDays30 = activeReadDays
        .where((day) => !day.isBefore(thirtyDayStart))
        .length;
    final activeDays7 = activeReadDays
        .where((day) => !day.isBefore(sevenDayStart))
        .length;

    var currentStreak = 0;
    for (
      var cursor = today;
      ;
      cursor = cursor.subtract(const Duration(days: 1))
    ) {
      final day = daysByDate[cursor];
      if (day == null || day.readCount == 0) break;
      currentStreak += 1;
    }

    var bestStreak = 0;
    var streak = 0;
    DateTime? previousDay;
    for (final day in activeReadDays) {
      if (previousDay == null || day.difference(previousDay).inDays == 1) {
        streak += 1;
      } else {
        streak = 1;
      }
      if (streak > bestStreak) bestStreak = streak;
      previousDay = day;
    }

    final trendLast14 = List<_TrendPoint>.generate(14, (index) {
      final date = today.subtract(Duration(days: 13 - index));
      return _TrendPoint(date: date, count: daysByDate[date]?.readCount ?? 0);
    });

    final summaries = books
        .map((book) {
          final stats = statsByBookId[book.id] ?? BookCardStats.empty;
          return _BookSummary(
            bookId: book.id,
            title: bookTitlesById[book.id] ?? book.title,
            totalCount: stats.totalCount,
            readCount: stats.readCount,
            favoriteCount: stats.favoriteCount,
            lastReadAt: lastReadByBook[book.id],
            lastFavoritedAt: lastFavoriteByBook[book.id],
          );
        })
        .toList(growable: false);

    return _ReadingAnalytics(
      books: books,
      bookTitlesById: bookTitlesById,
      bookSummaries: summaries,
      daysByDate: daysByDate,
      recentFavoriteEvents: favoriteEvents,
      totalCards: totalCards,
      totalRead: totalRead,
      totalFavorites: totalFavorites,
      readLast7: readLast7,
      readLast30: readLast30,
      favoriteLast7: favoriteLast7,
      favoriteLast30: favoriteLast30,
      todayRead: todayRead,
      thisWeekRead: thisWeekRead,
      thisMonthRead: thisMonthRead,
      currentStreak: currentStreak,
      bestStreak: bestStreak,
      activeDays365: activeDays365,
      activeDays30: activeDays30,
      activeDays7: activeDays7,
      avgReadsPerActiveDay30: activeDays30 == 0 ? 0 : readLast30 / activeDays30,
      weekdayCounts: weekdayCounts,
      hourCounts: hourCounts,
      trendLast14: trendLast14,
    );
  }

  int get totalBooks => books.length;
  int get totalUnread => totalCards - totalRead;
  double get overallProgress => totalCards == 0 ? 0 : totalRead / totalCards;
  double get favoriteToReadRatio =>
      totalRead == 0 ? 0 : totalFavorites / totalRead;
  int get maxHeatmapCount => daysByDate.values.fold<int>(
    0,
    (best, item) => math.max(best, item.readCount),
  );

  List<_BookSummary> get booksSortedByRead {
    final copy = List<_BookSummary>.from(bookSummaries);
    copy.sort((a, b) {
      final readCompare = b.readCount.compareTo(a.readCount);
      if (readCompare != 0) return readCompare;
      final progressCompare = b.progress.compareTo(a.progress);
      if (progressCompare != 0) return progressCompare;
      return a.title.compareTo(b.title);
    });
    return copy;
  }

  List<_BookSummary> get booksSortedByProgress {
    final copy = List<_BookSummary>.from(bookSummaries);
    copy.sort((a, b) {
      final progressCompare = b.progress.compareTo(a.progress);
      if (progressCompare != 0) return progressCompare;
      final readCompare = b.readCount.compareTo(a.readCount);
      if (readCompare != 0) return readCompare;
      return a.title.compareTo(b.title);
    });
    return copy;
  }

  List<_BookSummary> get booksSortedByFavorite {
    final copy = List<_BookSummary>.from(bookSummaries);
    copy.sort((a, b) {
      final favoriteCompare = b.favoriteCount.compareTo(a.favoriteCount);
      if (favoriteCompare != 0) return favoriteCompare;
      final favoriteRateCompare = b.favoriteRate.compareTo(a.favoriteRate);
      if (favoriteRateCompare != 0) return favoriteRateCompare;
      return a.title.compareTo(b.title);
    });
    return copy;
  }

  int get depthBucketNotStarted =>
      bookSummaries.where((item) => item.readCount == 0).length;
  int get depthBucketEarly => bookSummaries
      .where((item) => item.progress > 0 && item.progress < 0.25)
      .length;
  int get depthBucketMid => bookSummaries
      .where((item) => item.progress >= 0.25 && item.progress < 0.75)
      .length;
  int get depthBucketLate => bookSummaries
      .where((item) => item.progress >= 0.75 && item.progress < 1)
      .length;
  int get depthBucketDone =>
      bookSummaries.where((item) => item.progress >= 1).length;

  List<String> get weekdayShortLabels => const [
    '一',
    '二',
    '三',
    '四',
    '五',
    '六',
    '日',
  ];

  String get busiestWeekdayLabel {
    var bestIndex = 0;
    var bestValue = 0;
    for (var index = 0; index < weekdayCounts.length; index += 1) {
      if (weekdayCounts[index] > bestValue) {
        bestValue = weekdayCounts[index];
        bestIndex = index;
      }
    }
    return bestValue == 0
        ? '无'
        : '${weekdayShortLabels[bestIndex]} (${weekdayCounts[bestIndex]})';
  }

  String get busiestHourBucketLabel {
    final buckets = hourBuckets;
    var best = const _BarDatum(label: '无', value: 0);
    for (final item in buckets) {
      if (item.value > best.value) {
        best = item;
      }
    }
    return best.value == 0 ? '无' : '${best.label} (${best.value})';
  }

  List<_BarDatum> get hourBuckets => <_BarDatum>[
    _bucketForHours('00-02', 0, 3),
    _bucketForHours('03-05', 3, 6),
    _bucketForHours('06-08', 6, 9),
    _bucketForHours('09-11', 9, 12),
    _bucketForHours('12-14', 12, 15),
    _bucketForHours('15-17', 15, 18),
    _bucketForHours('18-20', 18, 21),
    _bucketForHours('21-23', 21, 24),
  ];

  _BarDatum _bucketForHours(String label, int start, int end) {
    var sum = 0;
    for (var hour = start; hour < end; hour += 1) {
      sum += hourCounts[hour];
    }
    return _BarDatum(label: label, value: sum);
  }

  String bookTitle(int bookId) => bookTitlesById[bookId] ?? '未知书籍';
}

class _ColorBucket {
  double _red = 0;
  double _green = 0;
  double _blue = 0;
  double weight = 0;

  void add({
    required int red,
    required int green,
    required int blue,
    required double weight,
  }) {
    _red += red * weight;
    _green += green * weight;
    _blue += blue * weight;
    this.weight += weight;
  }

  Color get color {
    if (weight == 0) {
      return const Color(0xFF5F8AA6);
    }
    return Color.fromARGB(
      255,
      (_red / weight).round().clamp(0, 255),
      (_green / weight).round().clamp(0, 255),
      (_blue / weight).round().clamp(0, 255),
    );
  }
}

String _formatDate(DateTime date, {bool withWeekday = false}) {
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

String _formatTime(DateTime date) {
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
