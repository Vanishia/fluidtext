import 'dart:async';
import 'dart:io';

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
import '../search/search_page.dart';
import 'card_list_page.dart';
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
    // 单双列切换的过渡动画期间会同时挂两个滚动视图，跳过该窗口。
    if (_scrollController.positions.length != 1) return;
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
    // 单双列切换的过渡动画期间会同时挂两个滚动视图，跳过该窗口。
    if (_scrollController.positions.length != 1) return;
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
        builder: (_) => CardListPage(
          kind: CardListKind.read,
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
        builder: (_) => CardListPage(
          kind: CardListKind.favorite,
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

  void _openSearch() {
    final repository = _controller?.repository;
    if (repository == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SearchPage(repository: repository)),
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
    // 桌面端推移布局下侧边栏打开时，返回键先收起侧边栏；
    // 移动端 Drawer 的返回处理由框架负责。
    if (!Platform.isAndroid &&
        !Platform.isIOS &&
        _sidebarVisible &&
        !_sidebarPushMode) {
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
            backgroundColor: backgroundSettings.backgroundColor(
              Theme.of(context).brightness,
            ),
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

              // 移动端回退到原生悬浮毛玻璃 Drawer：自带的手势不会
              // 和列表滚动抢手势竞技场；桌面端用贴边常驻/推移侧边栏。
              final useNativeDrawer = Platform.isAndroid || Platform.isIOS;

              Widget menuPanel({required bool floating}) {
                return AppSidePanel(
                  onOpenBookshelf: _openBookshelf,
                  onOpenSearch: LibraryDataAccess.supportsFullTextSearch
                      ? _openSearch
                      : null,
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
                  onRequestClose: () => _setSidebarVisible(false),
                  floating: floating,
                );
              }

              Widget buildReaderArea({
                required bool sidebarVisible,
                required bool pushMode,
              }) {
                return Stack(
                  children: [
                    body,
                    // 菜单按钮：仅桌面端显示；移动端用 Drawer 侧滑手势，
                    // 不占用视觉空间。
                    if (!useNativeDrawer)
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
                            tooltip: sidebarVisible ? '收起菜单' : '打开菜单',
                            onPressed: () =>
                                _setSidebarVisible(!sidebarVisible),
                          ),
                        ),
                      ),
                    // 翻页按钮：滚动时显示，停止后收起。
                    ValueListenableBuilder<bool>(
                      valueListenable: showPageTurnButtonsSetting,
                      builder: (context, enabled, _) {
                        if (!enabled) {
                          return const SizedBox.shrink();
                        }
                        return Positioned(
                          right: 12,
                          top: 0,
                          bottom: 0,
                          child: Align(
                            alignment: const Alignment(0, 0.35),
                            child: PageTurnButtons(
                              visible: _pageTurnButtonsVisible,
                              onPageUp: () => _pageScroll(-1),
                              onPageDown: () => _pageScroll(1),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                );
              }

              Widget withPageShortcuts({required Widget child}) {
                return CallbackShortcuts(
                  bindings: <ShortcutActivator, VoidCallback>{
                    const SingleActivator(LogicalKeyboardKey.pageDown): () =>
                        _pageScroll(1),
                    const SingleActivator(LogicalKeyboardKey.pageUp): () =>
                        _pageScroll(-1),
                  },
                  child: Focus(autofocus: true, child: child),
                );
              }

              if (useNativeDrawer) {
                return Scaffold(
                  backgroundColor: backgroundSettings.backgroundColor(
                    Theme.of(context).brightness,
                  ),
                  drawerEdgeDragWidth: 120,
                  drawerScrimColor: Colors.black.withValues(alpha: 0.18),
                  drawer: menuPanel(floating: true),
                  body: withPageShortcuts(
                    child: ReaderBackgroundSurface(
                      settings: backgroundSettings,
                      child: buildReaderArea(
                        sidebarVisible: false,
                        pushMode: true,
                      ),
                    ),
                  ),
                );
              }

              return Scaffold(
                backgroundColor: backgroundSettings.backgroundColor(
                  Theme.of(context).brightness,
                ),
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

                    return withPageShortcuts(
                      // 壁纸铺满整个窗口（含侧边栏下方），侧边栏的
                      // BackdropFilter 才能模糊到真实壁纸而非纯色。
                      child: ReaderBackgroundSurface(
                        settings: backgroundSettings,
                        child: Row(
                          children: [
                            if (pushMode)
                              PushSidePanel(
                                visible: sidebarVisible,
                                child: menuPanel(floating: false),
                              ),
                            Expanded(
                              child: pushMode
                                  ? buildReaderArea(
                                      sidebarVisible: sidebarVisible,
                                      pushMode: pushMode,
                                    )
                                  : SlideSidePanel(
                                      visible: sidebarVisible,
                                      onVisibilityChanged: _setSidebarVisible,
                                      panel: menuPanel(floating: false),
                                      child: buildReaderArea(
                                        sidebarVisible: sidebarVisible,
                                        pushMode: pushMode,
                                      ),
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
