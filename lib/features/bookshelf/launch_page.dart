import 'dart:io';

import 'package:flutter/material.dart';

import '../../app_settings.dart';
import '../../models/book.dart';
import '../../repositories/library_data_access.dart';
import '../../repositories/library_repository.dart';
import '../../services/app_logger.dart';
import '../../services/reader_session_service.dart';
import '../../widgets/side_panel.dart';
import '../reader/reader_page.dart';
import '../reader/reader_background_settings.dart';
import '../reader/widgets/reader_background_surface.dart';
import '../settings/app_drawer.dart';
import '../settings/reader_background_sheet.dart';
import 'bookshelf_sheet.dart';

class LaunchState {
  const LaunchState({
    this.restoredBooks,
    this.statusMessage,
    this.prunedBookTitles = const <String>[],
  });

  final List<Book>? restoredBooks;
  final String? statusMessage;

  /// Titles of half-imported books that were cleaned up at launch; when
  /// non-empty the page prompts the user to re-import them.
  final List<String> prunedBookTitles;
}

Future<LaunchState> loadLaunchState() async {
  final repository = (await LibraryDataAccess.instance).repository;
  final prunedBookTitles = await _pruneIncompleteImports(repository);

  final savedBookIds = await ReaderSessionService.instance
      .loadLastOpenedBookIds();
  if (savedBookIds.isEmpty) {
    return LaunchState(prunedBookTitles: prunedBookTitles);
  }

  final savedBooks = await repository.loadBooksByIds(savedBookIds);
  if (savedBooks.isEmpty) {
    return LaunchState(
      statusMessage: '未找到上次阅读的书籍，请重新选择。',
      prunedBookTitles: prunedBookTitles,
    );
  }

  return LaunchState(
    restoredBooks: List<Book>.unmodifiable(savedBooks),
    prunedBookTitles: prunedBookTitles,
  );
}

/// Removes books left half-imported by a killed process; best effort — a
/// failure here must not block startup.
Future<List<String>> _pruneIncompleteImports(
  LibraryRepository repository,
) async {
  try {
    final pruned = await repository.pruneIncompleteBooks();
    return [for (final book in pruned) book.title];
  } catch (error, stackTrace) {
    AppLogger.instance.warning(
      'LaunchPage',
      'Failed to prune incomplete imported books',
      error: error,
      stackTrace: stackTrace,
    );
    return const <String>[];
  }
}

class LaunchPage extends StatefulWidget {
  const LaunchPage({
    super.key,
    this.resumeLastSession = true,
    this.initialState = const LaunchState(),
  });

  final bool resumeLastSession;
  final LaunchState initialState;

  @override
  State<LaunchPage> createState() => _LaunchPageState();
}

class _LaunchPageState extends State<LaunchPage> {
  bool _isLoading = false;
  List<Book>? _restoredBooks;
  String? _statusMessage;

  /// 用户手动开合过侧边栏后生效；为 null 时按屏幕宽高比自动决定。
  bool? _sidebarVisibleOverride;

  void _setSidebarVisible(bool visible) {
    setState(() {
      _sidebarVisibleOverride = visible;
    });
  }

  @override
  void initState() {
    super.initState();
    _restoredBooks = widget.initialState.restoredBooks;
    _statusMessage = widget.initialState.statusMessage;
    if (widget.initialState.prunedBookTitles.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showPrunedBooksDialog(widget.initialState.prunedBookTitles);
        }
      });
    }
    if (widget.resumeLastSession && _restoredBooks == null) {
      _isLoading = true;
      _restoreSession();
    }
  }

  Future<void> _restoreSession() async {
    final state = await loadLaunchState();

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _restoredBooks = state.restoredBooks;
      _statusMessage = state.statusMessage;
    });
    if (state.prunedBookTitles.isNotEmpty) {
      _showPrunedBooksDialog(state.prunedBookTitles);
    }
  }

  void _showPrunedBooksDialog(List<String> titles) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('已清理未完成导入的书籍'),
        content: Text(
          '上次导入中途被中断，以下书籍不完整，已自动清理，请重新导入：\n'
          '${titles.map((title) => '《$title》').join('、')}',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  Future<void> _openBookshelf() async {
    final selected = await showBookshelfSheet(
      context,
      initialSelectedBookIds:
          _restoredBooks?.map((book) => book.id).toList(growable: false) ??
          const <int>[],
    );
    if (selected == null || !mounted) return;

    await ReaderSessionService.instance.saveLastOpenedBookIds(
      selected.map((book) => book.id).toList(),
    );
    if (!mounted) return;

    if (selected.isEmpty) {
      setState(() {
        _restoredBooks = null;
        _statusMessage = '还没有上次阅读，先去书架选择一本书。';
      });
      return;
    }

    setState(() {
      _restoredBooks = List<Book>.unmodifiable(selected);
      _statusMessage = null;
    });
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

  void _exitReader() {
    setState(() {
      _restoredBooks = null;
      _statusMessage = '已退出阅读，可从书架重新进入。';
    });
  }

  @override
  Widget build(BuildContext context) {
    final restoredBooks = _restoredBooks;
    if (restoredBooks != null) {
      return BookCardsPage(books: restoredBooks, onExitReader: _exitReader);
    }

    return ValueListenableBuilder<ReaderBackgroundSettings>(
      valueListenable: readerBackgroundSetting,
      builder: (context, backgroundSettings, _) {
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

              final panel = AppSidePanel(
                onOpenBookshelf: _openBookshelf,
                readingOrder: readingOrderSetting.value,
                onReadingOrderChanged: (order) {
                  saveReadingOrderSetting(order);
                  setState(() {});
                },
                themeMode: themeModeSetting.value,
                onThemeModeChanged: saveThemeModeSetting,
                onOpenReaderBackgroundSettings: _openReaderBackgroundSettings,
                onRequestClose: () => _setSidebarVisible(false),
              );

              final content = ReaderBackgroundSurface(
                settings: backgroundSettings,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '从这里开始阅读',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _statusMessage ?? '前往书架选择书籍，选好后会直接进入阅读。',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                                const SizedBox(height: 22),
                                FilledButton.tonalIcon(
                                  onPressed: _openBookshelf,
                                  icon: const Icon(Icons.arrow_forward_rounded),
                                  label: const Text('前往书架'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
              );

              final readerArea = Stack(
                children: [
                  content,
                  // 菜单按钮：仅桌面端显示；移动端用侧滑手势。
                  if (!Platform.isAndroid && !Platform.isIOS)
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
                          onPressed: () => _setSidebarVisible(!sidebarVisible),
                        ),
                      ),
                    ),
                ],
              );

              return Row(
                children: [
                  if (pushMode)
                    PushSidePanel(visible: sidebarVisible, child: panel),
                  Expanded(
                    child: pushMode
                        ? readerArea
                        : SlideSidePanel(
                            visible: sidebarVisible,
                            onVisibilityChanged: _setSidebarVisible,
                            panel: panel,
                            child: readerArea,
                          ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
