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

  Future<List<BookCard>> _loadCardsPage({int offset = 0}) {
    final repository = widget.repository;
    return _isFavorite
        ? repository.loadFavoriteCards(
            widget.bookIds,
            offset: offset,
            limit: _pageSize,
          )
        : repository.loadReadCards(
            widget.bookIds,
            offset: offset,
            limit: _pageSize,
          );
  }

  Future<int> _loadTotalCount() {
    final repository = widget.repository;
    return _isFavorite
        ? repository.countFavoriteCards(widget.bookIds)
        : repository.countReadCards(widget.bookIds);
  }

  Future<void> _load() async {
    final cardsFuture = _loadCardsPage();
    final totalCountFuture = _loadTotalCount();
    final remarksFuture = _loadRemarksOnce();
    final cards = await cardsFuture;
    final totalCount = await totalCountFuture;
    await remarksFuture;
    await _ensureBookTitles(cards.map((card) => card.bookId));
    if (!mounted) return;
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
    setState(() => _isLoadingMore = true);
    final cards = await _loadCardsPage(offset: _cards.length);
    await _ensureBookTitles(cards.map((card) => card.bookId));
    if (!mounted) return;
    setState(() {
      _cards.addAll(cards);
      _isLoadingMore = false;
    });
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

  Widget _buildBody() {
    if (_isLoading) {
      return const CardListSkeleton();
    }
    if (_cards.isEmpty) {
      return Center(child: Text(_isFavorite ? '还没有收藏卡片' : '还没有已读卡片'));
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: _cards.length + (_isLoadingMore ? 1 : 0),
      separatorBuilder: (context, index) => Divider(
        height: 1,
        indent: 12,
        endIndent: 12,
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: 0.28),
      ),
      itemBuilder: (context, index) {
        if (index >= _cards.length) {
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
          card: _cards[index],
          timestampText: _timestampText(_cards[index]),
          onCopy: () => _copyCardContent(context, _cards[index]),
          onShowContext: () => _showContext(_cards[index]),
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
