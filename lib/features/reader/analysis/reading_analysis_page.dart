import 'package:flutter/material.dart';

import '../../../app_settings.dart';
import '../../../repositories/book_card_repository.dart';
import '../reader_background_settings.dart';
import '../widgets/reader_background_surface.dart';
import 'models/reading_analytics.dart';
import 'reading_analysis_controller.dart';
import 'reading_analysis_module.dart';
import 'theme/analysis_seed_color.dart';
import 'widgets/analysis_common_widgets.dart';
import 'widgets/analysis_modules.dart';
import 'widgets/day_analysis_sheet.dart';

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
  ReadingAnalytics? _analytics;
  String? _error;
  bool _isLoading = true;
  late List<ReadingAnalysisModuleType> _moduleOrder =
      List<ReadingAnalysisModuleType>.from(analysisModuleOrderSetting.value);
  late final ReadingAnalysisController _controller = ReadingAnalysisController(
    repository: widget.repository,
    bookIds: widget.bookIds,
  );

  Future<Color>? _seedColorFuture;
  String? _seedColorCacheKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceFullScan = false}) async {
    final cached = _controller.getCachedAnalytics(forceFullScan: forceFullScan);

    setState(() {
      _isLoading = cached == null;
      _error = null;
      if (cached != null) {
        _analytics = cached;
      }
    });

    try {
      final analytics = await _controller.load(forceFullScan: forceFullScan);
      if (!mounted) return;
      setState(() {
        _analytics = analytics;
        _moduleOrder = List<ReadingAnalysisModuleType>.from(
          normalizeReadingAnalysisModuleOrder(_moduleOrder),
        );
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
    _seedColorFuture = AnalysisSeedColorResolver.resolveSeedColor(settings);
  }

  void _openDayAnalysis(
    BuildContext context,
    ReadingAnalytics analytics,
    DayAnalysis day,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DayAnalysisSheet(analytics: analytics, day: day),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ReadingAnalytics analytics,
    ReaderBackgroundSettings backgroundSettings,
  ) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return ReorderableListView.builder(
      padding: EdgeInsets.fromLTRB(10, 52, 10, bottomInset + 14),
      buildDefaultDragHandles: false,
      autoScrollerVelocityScalar: 12.0,
      proxyDecorator: _buildReorderProxy,
      onReorder: _onReorder,
      itemCount: _moduleOrder.length,
      itemBuilder: (context, index) {
        final module = _moduleOrder[index];
        return Padding(
          key: ValueKey(module.name),
          padding: const EdgeInsets.only(bottom: 14),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: _buildModuleCard(
                context,
                analytics: analytics,
                backgroundSettings: backgroundSettings,
                module: module,
                index: index,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReorderProxy(
    Widget child,
    int index,
    Animation<double> animation,
  ) {
    final scale = Tween<double>(
      begin: 1,
      end: 1.015,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        return Transform.scale(
          scale: scale.value,
          child: Opacity(opacity: 0.98, child: child),
        );
      },
    );
  }

  Widget _buildModuleCard(
    BuildContext context, {
    required ReadingAnalytics analytics,
    required ReaderBackgroundSettings backgroundSettings,
    required ReadingAnalysisModuleType module,
    required int index,
  }) {
    final content = switch (module) {
      ReadingAnalysisModuleType.overview => OverviewModule(
        analytics: analytics,
      ),
      ReadingAnalysisModuleType.heatmap => HeatmapModule(
        analytics: analytics,
        onOpenDay: (day) => _openDayAnalysis(context, analytics, day),
      ),
      ReadingAnalysisModuleType.streaks => StreaksModule(analytics: analytics),
      ReadingAnalysisModuleType.activity => ActivityModule(
        analytics: analytics,
      ),
      ReadingAnalysisModuleType.rankings => RankingsModule(
        analytics: analytics,
      ),
      ReadingAnalysisModuleType.depth => DepthModule(analytics: analytics),
      ReadingAnalysisModuleType.favorites => FavoritesModule(
        analytics: analytics,
      ),
    };

    final title = moduleTitle(module);

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelColor = cs.surface.withValues(
      alpha: backgroundSettings.hasCustomImage
          ? 0.40
          : isDark
          ? 0.56
          : 0.46,
    );

    return DecoratedBox(
      decoration: analysisPanelDecoration(cs, color: panelColor, radius: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(moduleIcon(module), size: 16, color: cs.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 18,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.72),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
              FilledButton(
                onPressed: () => _load(forceFullScan: true),
                child: const Text('重试'),
              ),
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
                AnalysisSeedColorResolver.normalizeSeedColor(
                  backgroundSettings.palette.color,
                );
            final themed = AnalysisSeedColorResolver.buildPageTheme(
              Theme.of(context),
              seedColor,
            );
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
                        bottom: false,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: _buildStateBody(
                                context,
                                backgroundSettings,
                              ),
                            ),
                            const Positioned(
                              top: 6,
                              left: 10,
                              child: AnalysisBackButton(),
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
