import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_settings.dart';
import '../../models/book.dart';
import '../../models/book_card.dart';
import '../../repositories/library_data_access.dart';
import '../../services/reader_session_service.dart';
import '../../widgets/side_panel.dart';
import '../bookshelf/launch_page.dart';
import '../bookshelf/bookshelf_sheet.dart';
import '../context/context_controller.dart';
import '../context/context_settings.dart';
import '../context/context_sheet.dart';
import '../settings/reader_background_sheet.dart';
import '../settings/app_drawer.dart';
import 'favorite_cards_page.dart';
import 'read_cards_page.dart';
import 'reading_analysis_page.dart';
import 'reader_background_settings.dart';
import 'reader_controller.dart';
import 'widgets/book_card_tile.dart';
import 'widgets/card_flow.dart';
import 'widgets/page_turn_buttons.dart';
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

  /// 用户手动开合过侧边栏后生效；为 null 时按屏幕宽高比自动决定。
  bool? _sidebarVisibleOverride;

  /// build 时记录的实际状态，供返回键/按钮逻辑使用。
  bool _sidebarVisible = false;
  bool _sidebarPushMode = true;

  /// 翻页按钮：滚动时显示，停止滚动 1.5 秒后收起。
  bool _pageTurnButtonsVisible = false;
  Timer? _pageTurnHideTimer;

  void _setSidebarVisible(bool visible) {
    setState(() {
      _sidebarVisibleOverride = visible;
    });
  }

  /// 按 90% 视口高度翻页（PageUp/PageDown 与翻页按钮共用）。
  void _pageScroll(double direction) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target =
        (position.pixels + position.viewportDimension * 0.9 * direction).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _handleScrollActivity() {
    if (!showPageTurnButtonsSetting.value) return;
    if (!_pageTurnButtonsVisible) {
      setState(() {
        _pageTurnButtonsVisible = true;
      });
    }
    _pageTurnHideTimer?.cancel();
    _pageTurnHideTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() {
        _pageTurnButtonsVisible = false;
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _init();
    _scrollController.addListener(_maybeLoadMore);
    _scrollController.addListener(_handleScrollActivity);
  }

  @override
  void dispose() {
    _pageTurnHideTimer?.cancel();
    _scrollController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final dataAccess = await LibraryDataAccess.instance;
    final repository = dataAccess.repository;
    final controller = ReaderController(
      repository: repository,
      bookIds: widget.bookIds,
      initialReadingOrder: readingOrderSetting.value,
      initialShowUnreadOnly: showUnreadOnlySetting.value,
    );
    final remarksFuture = dataAccess.loadRemarks();
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

  void _openReadingAnalysis() {
    final repository = _controller?.repository;
    if (repository == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ReadingAnalysisPage(repository: repository, shelfTitle: '全部书籍'),
      ),
    );
  }

  Future<void> _openBookshelf() async {
    final selected = await showBookshelfSheet(
      context,
      initialSelectedBookIds: _books.map((book) => book.id).toList(),
    );
    if (!mounted || selected == null) return;

    final remarks = await (await LibraryDataAccess.instance).loadRemarks();
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
      initialFontSettings: appFontSetting.value,
      onImportFont: importAppFont,
      onUseSystemFont: useSystemFont,
    );
  }

  void _handleBack() {
    // 覆盖布局下侧边栏打开时，返回键先收起侧边栏。
    if (_sidebarVisible && !_sidebarPushMode) {
      _setSidebarVisible(false);
      return;
    }

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
                  : BookCardFlow(
                      scrollController: _scrollController,
                      cards: controller.cards,
                      hasMore: controller.hasMore,
                      cardBuilder: (card) {
                        return BookCardTile(
                          card: card,
                          repository: controller.repository,
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
                body: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final aspectRatio = constraints.maxHeight > 0
                        ? width / constraints.maxHeight
                        : 1.0;
                    final pushMode = width >= kSidePanelPushBreakpoint;
                    final sidebarVisible =
                        _sidebarVisibleOverride ??
                        aspectRatio >= kSidePanelDefaultOpenAspectRatio;
                    _sidebarPushMode = pushMode;
                    _sidebarVisible = sidebarVisible;

                    final panel = GestureDetector(
                      onHorizontalDragEnd: (details) {
                        // 面板内向左快速滑动收起（覆盖布局）。
                        if (!pushMode &&
                            (details.primaryVelocity ?? 0) < -240) {
                          _setSidebarVisible(false);
                        }
                      },
                      child: AppSidePanel(
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
                        onOpenReadingAnalysis: _openReadingAnalysis,
                        onOpenReadList: _openReadList,
                        onOpenFavoriteList: _openFavoriteList,
                        onOpenReaderBackgroundSettings:
                            _openReaderBackgroundSettings,
                        contextBefore: _contextSettings.before,
                        contextAfter: _contextSettings.after,
                        onContextBeforeChanged: (value) {
                          final next = _contextSettings.copyWith(
                            before: value,
                          );
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
                        onRequestClose: () => _setSidebarVisible(false),
                        showCloseButton: !pushMode,
                      ),
                    );

                    return CallbackShortcuts(
                      bindings: <ShortcutActivator, VoidCallback>{
                        const SingleActivator(LogicalKeyboardKey.pageDown): () =>
                            _pageScroll(1),
                        const SingleActivator(LogicalKeyboardKey.pageUp): () =>
                            _pageScroll(-1),
                      },
                      child: Focus(
                        autofocus: true,
                        child: Row(
                          children: [
                            if (pushMode)
                              PushSidePanel(
                                visible: sidebarVisible,
                                child: panel,
                              ),
                            Expanded(
                              child: Stack(
                                children: [
                                  ReaderBackgroundSurface(
                                    settings: backgroundSettings,
                                    child: body,
                                  ),
                                  // 菜单按钮：所有平台可见，点击开合侧边栏。
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    child: SafeArea(
                                      child: IconButton(
                                        icon: Icon(
                                          sidebarVisible && pushMode
                                              ? Icons.menu_open_rounded
                                              : Icons.menu_rounded,
                                        ),
                                        tooltip: sidebarVisible
                                            ? '收起菜单'
                                            : '打开菜单',
                                        onPressed: () => _setSidebarVisible(
                                          !sidebarVisible,
                                        ),
                                      ),
                                    ),
                                  ),
                                  // 翻页按钮：滚动时显示，停止后收起。
                                  ValueListenableBuilder<bool>(
                                    valueListenable:
                                        showPageTurnButtonsSetting,
                                    builder: (context, enabled, _) {
                                      if (!enabled) {
                                        return const SizedBox.shrink();
                                      }
                                      return Positioned(
                                        right: 12,
                                        top: 0,
                                        bottom: 0,
                                        child: Center(
                                          child: PageTurnButtons(
                                            visible: _pageTurnButtonsVisible,
                                            onPageUp: () => _pageScroll(-1),
                                            onPageDown: () => _pageScroll(1),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  // 左边缘向右滑动打开侧边栏（覆盖布局）。
                                  if (!pushMode && !sidebarVisible)
                                    Positioned(
                                      left: 0,
                                      top: 0,
                                      bottom: 0,
                                      width: 24,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.translucent,
                                        onHorizontalDragEnd: (details) {
                                          if ((details.primaryVelocity ?? 0) >
                                              240) {
                                            _setSidebarVisible(true);
                                          }
                                        },
                                        child: const SizedBox.expand(),
                                      ),
                                    ),
                                  if (!pushMode)
                                    Positioned.fill(
                                      child: OverlaySidePanel(
                                        visible: sidebarVisible,
                                        onClose: () =>
                                            _setSidebarVisible(false),
                                        child: panel,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
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
