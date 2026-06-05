import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../app_settings.dart';
import '../../db/isar_db.dart';
import '../../models/book.dart';
import '../../models/book_card.dart';
import '../../repositories/book_card_repository.dart';
import '../../services/book_remark_service.dart';
import '../../services/reader_session_service.dart';
import '../bookshelf/launch_page.dart';
import '../bookshelf/bookshelf_sheet.dart';
import '../context/context_controller.dart';
import '../context/context_settings.dart';
import '../context/context_sheet.dart';
import '../settings/reader_background_sheet.dart';
import '../settings/app_drawer.dart';
import 'favorite_cards_page.dart';
import 'read_cards_page.dart';
import 'reader_background_settings.dart';
import 'reader_controller.dart';
import 'widgets/book_card_tile.dart';
import 'widgets/reader_background_surface.dart';

class BookCardsPage extends StatefulWidget {
  BookCardsPage({super.key, required List<Book> books, this.onExitReader})
    : books = List<Book>.unmodifiable(books);

  final List<Book> books;
  final VoidCallback? onExitReader;

  List<int> get bookIds => books.map((book) => book.id).toList(growable: false);

  String get shelfTitle {
    if (books.isEmpty) return '阅读';
    if (books.length == 1) return books.first.title;
    return '混合阅读 · ${books.length} 本';
  }

  @override
  State<BookCardsPage> createState() => _BookCardsPageState();
}

class _BookCardsPageState extends State<BookCardsPage> {
  final _scrollController = ScrollController();

  ReaderController? _controller;
  late final List<Book> _books = List<Book>.from(widget.books);
  final _bookRemarks = <int, String>{};
  ContextSettings _contextSettings = contextSettingsSetting.value;

  @override
  void initState() {
    super.initState();
    _init();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final isar = await IsarDb.instance.isar;
    final repository = BookCardRepository(isar);
    final controller = ReaderController(
      repository: repository,
      bookIds: widget.bookIds,
      initialReadingOrder: readingOrderSetting.value,
      initialShowUnreadOnly: showUnreadOnlySetting.value,
    );
    final remarksFuture = BookRemarkService.instance.load();
    await controller.reloadCards();
    final remarks = await remarksFuture;

    if (!mounted) {
      controller.dispose();
      return;
    }

    setState(() {
      _controller = controller;
      _bookRemarks
        ..clear()
        ..addAll(remarks);
    });
    unawaited(_saveCurrentSession());
  }

  Future<void> _saveCurrentSession() async {
    try {
      await ReaderSessionService.instance.saveLastOpenedBookIds(widget.bookIds);
    } catch (_) {
      // Session restore is best-effort and should not block reading startup.
    }
  }

  void _maybeLoadMore() {
    final controller = _controller;
    if (controller == null) return;
    if (!_scrollController.hasClients) return;
    if (controller.isLoadingMore || !controller.hasMore) return;

    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      controller.loadMore();
    }
  }

  Future<void> _toggleFavorite(BookCard card) async {
    await _controller?.toggleFavorite(card);
  }

  Future<void> _toggleRead(BookCard card) async {
    await _controller?.toggleRead(card);
  }

  void _openReadList() {
    final repository = _controller?.repository;
    if (repository == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReadCardsPage(
          bookIds: const <int>[],
          shelfTitle: '全部书籍',
          repository: repository,
          bookTitlesById: _bookTitlesById(),
        ),
      ),
    );
  }

  void _openFavoriteList() {
    final repository = _controller?.repository;
    if (repository == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FavoriteCardsPage(
          bookIds: const <int>[],
          shelfTitle: '全部书籍',
          repository: repository,
          bookTitlesById: _bookTitlesById(),
        ),
      ),
    );
  }

  Future<void> _openBookshelf() async {
    final selected = await showBookshelfSheet(
      context,
      initialSelectedBookIds: _books.map((book) => book.id).toList(),
    );
    if (!mounted || selected == null) return;

    final remarks = await BookRemarkService.instance.load();
    if (!mounted) return;
    setState(() {
      _bookRemarks
        ..clear()
        ..addAll(remarks);
    });

    await ReaderSessionService.instance.saveLastOpenedBookIds(
      selected.map((book) => book.id).toList(),
    );

    if (selected.isEmpty) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LaunchPage()),
        (route) => false,
      );
      return;
    }

    if (!_sameBookSelection(selected)) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => BookCardsPage(books: selected)),
      );
      return;
    }

    setState(() {
      _books
        ..clear()
        ..addAll(selected);
    });
  }

  bool _sameBookSelection(List<Book> nextBooks) {
    final currentIds = _books.map((book) => book.id).toList();
    final nextIds = nextBooks.map((book) => book.id).toList();
    if (currentIds.length != nextIds.length) return false;
    for (var index = 0; index < currentIds.length; index += 1) {
      if (currentIds[index] != nextIds[index]) return false;
    }
    return true;
  }

  String _displayTitle(Book book) => _bookRemarks[book.id] ?? book.title;

  String _bookTitleForCard(BookCard card) {
    return _bookRemarks[card.bookId] ?? card.bookTitle;
  }

  Map<int, String> _bookTitlesById() {
    return {for (final book in _books) book.id: _displayTitle(book)};
  }

  Future<void> _showContext(BookCard card) async {
    final repository = _controller?.repository;
    if (repository == null) return;

    final contextController = ContextController(
      repository: repository,
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
        bookTitle: _bookTitleForCard(card),
      ),
    );

    if (mounted) {
      setState(() {
        _contextSettings = contextController.settings;
      });
      saveContextSettingsSetting(contextController.settings);
      final changedCards = await repository.loadCardsByIds(
        contextController.changedCardIds.toList(),
      );
      for (final changedCard in changedCards) {
        await _controller?.refreshCard(changedCard);
      }
    }
    contextController.dispose();
  }

  Future<void> _openReaderBackgroundSettings() async {
    await showReaderBackgroundSheet(
      context,
      initialSettings: readerBackgroundSetting.value,
      onChanged: saveReaderBackgroundSettings,
      onImportImage: importReaderBackgroundImage,
      onClearImage: clearReaderBackgroundImage,
    );
  }

  void _handleBack() {
    final onExitReader = widget.onExitReader;
    if (onExitReader != null) {
      onExitReader();
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const LaunchPage(
          resumeLastSession: false,
          initialState: LaunchState(statusMessage: '已退出阅读，可从书架重新进入。'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    if (controller == null) {
      return ValueListenableBuilder<ReaderBackgroundSettings>(
        valueListenable: readerBackgroundSetting,
        builder: (context, backgroundSettings, _) {
          return Scaffold(
            backgroundColor: backgroundSettings.palette.color,
            body: ReaderBackgroundSurface(
              settings: backgroundSettings,
              child: const Center(child: CircularProgressIndicator()),
            ),
          );
        },
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return ValueListenableBuilder<ReaderBackgroundSettings>(
            valueListenable: readerBackgroundSetting,
            builder: (context, backgroundSettings, _) {
              final body =
                  controller.isLoadingInitial && controller.cards.isEmpty
                  ? const Center(child: Text('加载中…'))
                  : !controller.isLoadingInitial && controller.cards.isEmpty
                  ? _EmptyCardsMessage(
                      showUnreadOnly: controller.showUnreadOnly,
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.only(
                        top: MediaQuery.paddingOf(context).top + 2,
                        bottom: 20,
                      ),
                      itemCount:
                          controller.cards.length +
                          (controller.hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= controller.cards.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        final card = controller.cards[index];
                        return BookCardTile(
                          card: card,
                          onToggleRead: () => _toggleRead(card),
                          onToggleFavorite: () => _toggleFavorite(card),
                          onShowContext: () => _showContext(card),
                          showBookTitle: _books.length > 1,
                          bookTitle: _bookTitleForCard(card),
                        );
                      },
                    );

              return Scaffold(
                backgroundColor: backgroundSettings.palette.color,
                drawerEdgeDragWidth: 120,
                drawerScrimColor: Colors.black.withValues(alpha: 0.18),
                drawer: AppDrawer(
                  onOpenBookshelf: _openBookshelf,
                  readingOrder: controller.readingOrder,
                  onReadingOrderChanged: (order) {
                    saveReadingOrderSetting(order);
                    controller.setReadingOrder(order);
                  },
                  themeMode: themeModeSetting.value,
                  onThemeModeChanged: saveThemeModeSetting,
                  showUnreadOnly: controller.showUnreadOnly,
                  onShowUnreadOnlyChanged: (value) {
                    saveShowUnreadOnlySetting(value);
                    controller.setShowUnreadOnly(value);
                  },
                  onOpenReadList: _openReadList,
                  onOpenFavoriteList: _openFavoriteList,
                  onOpenReaderBackgroundSettings: _openReaderBackgroundSettings,
                  contextBefore: _contextSettings.before,
                  contextAfter: _contextSettings.after,
                  onContextBeforeChanged: (value) {
                    final next = _contextSettings.copyWith(before: value);
                    saveContextSettingsSetting(next);
                    setState(() {
                      _contextSettings = next;
                    });
                  },
                  onContextAfterChanged: (value) {
                    final next = _contextSettings.copyWith(after: value);
                    saveContextSettingsSetting(next);
                    setState(() {
                      _contextSettings = next;
                    });
                  },
                ),
                body: Stack(
                  children: [
                    ReaderBackgroundSurface(
                      settings: backgroundSettings,
                      child: body,
                    ),
                    if (!Platform.isAndroid && !Platform.isIOS)
                      Positioned(
                        top: 0,
                        left: 0,
                        child: SafeArea(
                          child: Builder(
                            builder: (context) {
                              return IconButton(
                                icon: const Icon(Icons.menu_rounded),
                                tooltip: '打开菜单',
                                onPressed: () =>
                                    Scaffold.of(context).openDrawer(),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyCardsMessage extends StatelessWidget {
  const _EmptyCardsMessage({required this.showUnreadOnly});

  final bool showUnreadOnly;

  @override
  Widget build(BuildContext context) {
    final text = showUnreadOnly ? '当前书单没有未读卡片' : '当前书单没有可显示的卡片';
    return Center(
      child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
    );
  }
}
