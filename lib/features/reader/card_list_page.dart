import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_settings.dart';
import '../../features/context/context_controller.dart';
import '../../features/context/context_settings.dart';
import '../../features/context/context_sheet.dart';
import '../../models/book_card.dart';
import '../../repositories/library_repository.dart';
import '../../widgets/reading_skeleton.dart';
import 'reader_background_settings.dart';
import 'widgets/reader_background_surface.dart';

/// 收藏 / 已读列表共用的卡片类型。
enum CardListKind { read, favorite }

class CardListPage extends StatefulWidget {
  const CardListPage({
    super.key,
    required this.kind,
    required this.bookIds,
    required this.shelfTitle,
    required this.repository,
    this.bookTitlesById = const <int, String>{},
  });

  final CardListKind kind;
  final List<int> bookIds;
  final String shelfTitle;
  final LibraryRepository repository;
  final Map<int, String> bookTitlesById;

  @override
  State<CardListPage> createState() => _CardListPageState();
}

class _CardListPageState extends State<CardListPage> {
  static const int _pageSize = 50;

  final _cards = <BookCard>[];
  final _bookTitlesById = <int, String>{};
  final _scrollController = ScrollController();
  Map<int, String>? _remarks;
  ContextSettings _contextSettings = contextSettingsSetting.value;
  var _isLoading = true;
  var _isLoadingMore = false;
  var _totalCount = 0;

  // 筛选与排序状态；_timeFilter/_selectedBookIds 为默认值时表示不限制。
  _TimeFilter _timeFilter = _TimeFilter.all;
  DateTimeRange? _customRange;
  Set<int>? _selectedBookIds;
  CardListSort _sort = CardListSort.activityDesc;

  /// 筛选变更的世代号：丢弃上一代仍在途的分页结果，避免串数据。
  var _queryGeneration = 0;

  bool get _isFavorite => widget.kind == CardListKind.favorite;

  bool get _hasMore => _cards.length < _totalCount;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.positions.length != 1) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  /// 生效的书目范围：null 表示不限制；空列表表示「未选任何书」，
  /// 此时结果应为空（repository 的空头约定是「全部」，不能直接透传）。
  List<int>? get _effectiveBookIds {
    final selected = _selectedBookIds;
    if (selected == null) {
      return widget.bookIds.isEmpty ? null : widget.bookIds;
    }
    if (widget.bookIds.isEmpty) return selected.toList(growable: false);
    return widget.bookIds.where(selected.contains).toList(growable: false);
  }

  /// 动作时间范围：含起始日 00:00、不含结束日次日 00:00。
  (DateTime?, DateTime?) get _activityRange {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final tomorrow = todayStart.add(const Duration(days: 1));
    switch (_timeFilter) {
      case _TimeFilter.all:
        return (null, null);
      case _TimeFilter.today:
        return (todayStart, tomorrow);
      case _TimeFilter.last7Days:
        return (todayStart.subtract(const Duration(days: 6)), tomorrow);
      case _TimeFilter.last30Days:
        return (todayStart.subtract(const Duration(days: 29)), tomorrow);
      case _TimeFilter.custom:
        final range = _customRange;
        if (range == null) return (null, null);
        final start = DateTime(
          range.start.year,
          range.start.month,
          range.start.day,
        );
        final end = DateTime(
          range.end.year,
          range.end.month,
          range.end.day,
        ).add(const Duration(days: 1));
        return (start, end);
    }
  }

  Future<List<BookCard>> _loadCardsPage({int offset = 0}) {
    final bookIds = _effectiveBookIds;
    if (bookIds != null && bookIds.isEmpty) {
      return Future.value(const <BookCard>[]);
    }
    final (from, to) = _activityRange;
    final repository = widget.repository;
    return _isFavorite
        ? repository.loadFavoriteCards(
            bookIds ?? const <int>[],
            offset: offset,
            limit: _pageSize,
            from: from,
            to: to,
            sort: _sort,
          )
        : repository.loadReadCards(
            bookIds ?? const <int>[],
            offset: offset,
            limit: _pageSize,
            from: from,
            to: to,
            sort: _sort,
          );
  }

  Future<int> _loadTotalCount() {
    final bookIds = _effectiveBookIds;
    if (bookIds != null && bookIds.isEmpty) {
      return Future.value(0);
    }
    final (from, to) = _activityRange;
    final repository = widget.repository;
    return _isFavorite
        ? repository.countFavoriteCards(bookIds ?? const [], from: from, to: to)
        : repository.countReadCards(bookIds ?? const [], from: from, to: to);
  }

  Future<void> _load() async {
    final generation = _queryGeneration;
    final cardsFuture = _loadCardsPage();
    final totalCountFuture = _loadTotalCount();
    final remarksFuture = _loadRemarksOnce();
    final cards = await cardsFuture;
    final totalCount = await totalCountFuture;
    await remarksFuture;
    await _ensureBookTitles(cards.map((card) => card.bookId));
    if (!mounted || generation != _queryGeneration) return;
    setState(() {
      _cards
        ..clear()
        ..addAll(cards);
      _totalCount = totalCount;
      _isLoading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    final generation = _queryGeneration;
    setState(() => _isLoadingMore = true);
    final cards = await _loadCardsPage(offset: _cards.length);
    await _ensureBookTitles(cards.map((card) => card.bookId));
    if (!mounted || generation != _queryGeneration) return;
    setState(() {
      _cards.addAll(cards);
      _isLoadingMore = false;
    });
  }

  /// 筛选/排序变更后从头重新加载，并回到列表顶部。
  void _onFiltersChanged() {
    _queryGeneration++;
    setState(() {
      _cards.clear();
      _totalCount = 0;
      _isLoading = true;
      _isLoadingMore = false;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _load();
  }

  Future<Map<int, String>> _loadRemarksOnce() async {
    return _remarks ??= await widget.repository.loadRemarks();
  }

  /// 只拉取当前已加载卡片涉及、且尚未知名称的书籍，避免全量 loadBooks。
  Future<void> _ensureBookTitles(Iterable<int> bookIds) async {
    final missing = bookIds
        .toSet()
        .where(
          (id) =>
              !_bookTitlesById.containsKey(id) &&
              !widget.bookTitlesById.containsKey(id),
        )
        .toList(growable: false);
    if (missing.isEmpty) return;

    final books = await widget.repository.loadBooksByIds(missing);
    final remarks = await _loadRemarksOnce();
    _bookTitlesById.addAll({
      for (final book in books) book.id: remarks[book.id] ?? book.title,
    });
  }

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return '未知时间';
    final local = timestamp.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }

  String _timestampText(BookCard card) {
    final label = _isFavorite ? '收藏于' : '已读于';
    final timestamp = _isFavorite ? card.favoritedAt : card.readAt;
    return '$label ${_formatTimestamp(timestamp)}';
  }

  String _bookTitle(BookCard card) {
    return _bookTitlesById[card.bookId] ??
        widget.bookTitlesById[card.bookId] ??
        card.bookTitle;
  }

  Future<void> _copyCardContent(BuildContext context, BookCard card) async {
    await Clipboard.setData(ClipboardData(text: card.content));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Copied'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1200),
          margin: const EdgeInsets.fromLTRB(24, 0, 24, 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
  }

  Future<void> _showContext(BookCard card) async {
    final contextController = ContextController(
      repository: widget.repository,
      bookId: card.bookId,
      initialCard: card,
      initialSettings: _contextSettings,
    );
    await contextController.load();

    if (!mounted) {
      contextController.dispose();
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ContextSheet(
        controller: contextController,
        bookTitle: _bookTitle(card),
      ),
    );

    if (mounted) {
      saveContextSettingsSetting(contextController.settings);

      final changedCards = await widget.repository.loadCardsByIds(
        contextController.changedCardIds.toList(),
      );
      if (mounted) {
        setState(() {
          _contextSettings = contextController.settings;
          final changedMap = {for (final c in changedCards) c.id: c};
          for (var i = 0; i < _cards.length; i++) {
            final updated = changedMap[_cards[i].id];
            if (updated != null) {
              _cards[i] = updated;
            }
          }
          final lengthBeforeFilter = _cards.length;
          _cards.removeWhere((c) => _isFavorite ? !c.isFavorite : !c.isRead);
          // 取消收藏/已读的卡片被移除后，总数同步减少，保证 _hasMore 正确。
          _totalCount -= lengthBeforeFilter - _cards.length;
        });
      } else {
        contextController.dispose();
        return;
      }
    }
    contextController.dispose();
  }

  String get _timeFilterLabel {
    switch (_timeFilter) {
      case _TimeFilter.all:
        return '按时间';
      case _TimeFilter.today:
        return '今天';
      case _TimeFilter.last7Days:
        return '最近 7 天';
      case _TimeFilter.last30Days:
        return '最近 30 天';
      case _TimeFilter.custom:
        final range = _customRange;
        if (range == null) return '按时间';
        return '${range.start.month}/${range.start.day}'
            '–${range.end.month}/${range.end.day}';
    }
  }

  String get _sortLabel {
    switch (_sort) {
      case CardListSort.activityDesc:
        return '从新到旧';
      case CardListSort.activityAsc:
        return '从旧到新';
      case CardListSort.cardOrder:
        return '卡片顺序';
    }
  }

  /// 在筛选按钮下方弹出小菜单。
  Future<T?> _showChipMenu<T>(
    BuildContext chipContext,
    List<PopupMenuEntry<T>> items,
  ) {
    final box = chipContext.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    return showMenu<T>(context: context, position: position, items: items);
  }

  Future<void> _pickTimeFilter(BuildContext chipContext) async {
    PopupMenuEntry<_TimeFilter> item(_TimeFilter value, String label) =>
        CheckedPopupMenuItem(
          value: value,
          checked: _timeFilter == value,
          child: Text(label),
        );
    final selection = await _showChipMenu<_TimeFilter>(chipContext, [
      item(_TimeFilter.all, '全部时间'),
      item(_TimeFilter.today, '今天'),
      item(_TimeFilter.last7Days, '最近 7 天'),
      item(_TimeFilter.last30Days, '最近 30 天'),
      item(_TimeFilter.custom, '自定义范围…'),
    ]);
    if (selection == null || !mounted) return;
    if (selection == _TimeFilter.custom) {
      final now = DateTime.now();
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(now.year + 1, 12, 31),
        initialDateRange:
            _customRange ??
            DateTimeRange(
              start: now.subtract(const Duration(days: 6)),
              end: now,
            ),
      );
      if (range == null || !mounted) return;
      _customRange = range;
      _timeFilter = _TimeFilter.custom;
    } else {
      _timeFilter = selection;
    }
    _onFiltersChanged();
  }

  Future<void> _pickBooks() async {
    final scope = widget.bookIds;
    final books = scope.isEmpty
        ? await widget.repository.loadBooks()
        : await widget.repository.loadBooksByIds(scope);
    final remarks = await _loadRemarksOnce();
    if (!mounted) return;

    // 未筛选时视为全选。
    final initial = _selectedBookIds ?? books.map((book) => book.id).toSet();
    final result = await showDialog<Set<int>>(
      context: context,
      builder: (context) => _BookFilterDialog(
        bookTitles: {
          for (final book in books) book.id: remarks[book.id] ?? book.title,
        },
        initialSelection: initial,
      ),
    );
    if (result == null) return;
    // 全选等价于不限制，回到默认状态。
    _selectedBookIds = result.length == books.length ? null : result;
    _onFiltersChanged();
  }

  Future<void> _pickSort(BuildContext chipContext) async {
    PopupMenuEntry<CardListSort> item(CardListSort value, String label) =>
        CheckedPopupMenuItem(
          value: value,
          checked: _sort == value,
          child: Text(label),
        );
    final selection = await _showChipMenu<CardListSort>(chipContext, [
      item(CardListSort.activityDesc, '从新到旧'),
      item(CardListSort.activityAsc, '从旧到新'),
      item(CardListSort.cardOrder, '卡片顺序'),
    ]);
    if (selection == null || selection == _sort || !mounted) return;
    _sort = selection;
    _onFiltersChanged();
  }

  /// 筛选条：作为列表第一项，随内容一起滚走。
  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Row(
        children: [
          _FilterChip(
            label: _timeFilterLabel,
            active: _timeFilter != _TimeFilter.all,
            onTapWithContext: _pickTimeFilter,
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: _selectedBookIds == null
                ? '按书'
                : '${_selectedBookIds!.length} 本书',
            active: _selectedBookIds != null,
            onTapWithContext: (_) => _pickBooks(),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: _sortLabel,
            active: _sort != CardListSort.activityDesc,
            onTapWithContext: _pickSort,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const CardListSkeleton();
    }
    if (_cards.isEmpty) {
      final hasFilter =
          _timeFilter != _TimeFilter.all || _selectedBookIds != null;
      // 空态也保留筛选条，否则筛选到零结果后无法改回条件。
      return Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: Center(
              child: Text(
                hasFilter
                    ? '没有符合筛选条件的卡片'
                    : (_isFavorite ? '还没有收藏卡片' : '还没有已读卡片'),
              ),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: 1 + _cards.length + (_isLoadingMore ? 1 : 0),
      separatorBuilder: (context, index) => Divider(
        height: 1,
        indent: 12,
        endIndent: 12,
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: 0.28),
      ),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildFilterBar();
        }
        final cardIndex = index - 1;
        if (cardIndex >= _cards.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _CardListItem(
          card: _cards[cardIndex],
          timestampText: _timestampText(_cards[cardIndex]),
          onCopy: () => _copyCardContent(context, _cards[cardIndex]),
          onShowContext: () => _showContext(_cards[cardIndex]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReaderBackgroundSettings>(
      valueListenable: readerBackgroundSetting,
      builder: (context, backgroundSettings, _) {
        return Scaffold(
          backgroundColor: backgroundSettings.backgroundColor(
            Theme.of(context).brightness,
          ),
          body: ReaderBackgroundSurface(
            settings: backgroundSettings,
            child: SafeArea(
              child: Column(
                children: [
                  _ListPageHeader(
                    title:
                        '${widget.shelfTitle} · ${_isFavorite ? '收藏' : '已读'}',
                    count: _totalCount,
                  ),
                  // 遮罩只铺在卡片内容区，提升正文可读性；
                  // 顶栏与系统导航栏区域保持透明。
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const _SubtleReadabilityOverlay(),
                        _buildBody(),
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
  }
}

class _CardListItem extends StatelessWidget {
  const _CardListItem({
    required this.card,
    required this.timestampText,
    required this.onCopy,
    required this.onShowContext,
  });

  final BookCard card;
  final String timestampText;
  final VoidCallback onCopy;
  final VoidCallback onShowContext;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onLongPress: onCopy,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedBuilder(
                animation: Listenable.merge([
                  readerFontScaleSetting,
                  readerLineHeightSetting,
                ]),
                builder: (context, _) {
                  return Text(
                    card.content,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 15 * readerFontScaleSetting.value,
                      height: readerLineHeightSetting.value,
                    ),
                  );
                },
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      '#${card.cardIndex} · $timestampText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    icon: const Icon(Icons.unfold_more),
                    tooltip: '展开上下文',
                    onPressed: onShowContext,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubtleReadabilityOverlay extends StatelessWidget {
  const _SubtleReadabilityOverlay();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.18),
    );
  }
}

class _ListPageHeader extends StatelessWidget {
  const _ListPageHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_back),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 14, left: 8),
            child: Text(
              '$count 张',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// 按时间筛选的预设选项；custom 配合自定义日期范围使用。
enum _TimeFilter { all, today, last7Days, last30Days, custom }

/// 筛选条上的扁平下拉小按钮：选中态用主题色强调。
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTapWithContext,
  });

  final String label;
  final bool active;

  /// 回调携带按钮自身的 BuildContext，用于定位弹出菜单。
  final void Function(BuildContext chipContext) onTapWithContext;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Builder(
      builder: (chipContext) {
        return Material(
          color: active
              ? cs.primaryContainer.withValues(alpha: 0.75)
              : cs.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onTapWithContext(chipContext),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: Theme.of(chipContext).textTheme.labelMedium
                        ?.copyWith(
                          color: active
                              ? cs.onPrimaryContainer
                              : cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: active
                        ? cs.onPrimaryContainer
                        : cs.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 按书筛选对话框：书名复选列表 + 全选，确定后返回选中的书籍 id 集合。
class _BookFilterDialog extends StatefulWidget {
  const _BookFilterDialog({
    required this.bookTitles,
    required this.initialSelection,
  });

  /// id → 显示名（备注优先）。
  final Map<int, String> bookTitles;
  final Set<int> initialSelection;

  @override
  State<_BookFilterDialog> createState() => _BookFilterDialogState();
}

class _BookFilterDialogState extends State<_BookFilterDialog> {
  late final Set<int> _selection = {...widget.initialSelection};

  @override
  Widget build(BuildContext context) {
    final entries = widget.bookTitles.entries.toList(growable: false);
    final allSelected = _selection.length == entries.length;

    return AlertDialog(
      title: const Text('按书筛选'),
      contentPadding: const EdgeInsets.only(top: 8),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('全选'),
              value: allSelected,
              onChanged: (checked) {
                setState(() {
                  _selection
                    ..clear()
                    ..addAll(checked ?? false ? widget.bookTitles.keys : []);
                });
              },
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final entry in entries)
                    CheckboxListTile(
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        entry.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      value: _selection.contains(entry.key),
                      onChanged: (checked) {
                        setState(() {
                          checked ?? false
                              ? _selection.add(entry.key)
                              : _selection.remove(entry.key);
                        });
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selection),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
