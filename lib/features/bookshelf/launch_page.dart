import 'package:flutter/material.dart';

import '../../app_settings.dart';
import '../../db/isar_db.dart';
import '../../models/book.dart';
import '../../repositories/book_card_repository.dart';
import '../../services/reader_session_service.dart';
import '../reader/reader_page.dart';
import '../reader/reader_background_settings.dart';
import '../reader/widgets/reader_background_surface.dart';
import '../settings/app_drawer.dart';
import '../settings/reader_background_sheet.dart';
import 'bookshelf_sheet.dart';

class LaunchState {
  const LaunchState({this.restoredBooks, this.statusMessage});

  final List<Book>? restoredBooks;
  final String? statusMessage;
}

Future<LaunchState> loadLaunchState() async {
  final savedBookIds = await ReaderSessionService.instance
      .loadLastOpenedBookIds();
  if (savedBookIds.isEmpty) {
    return const LaunchState();
  }

  final isar = await IsarDb.instance.isar;
  final repository = BookCardRepository(isar);
  final savedBooks = await repository.loadBooksByIds(savedBookIds);
  if (savedBooks.isEmpty) {
    return const LaunchState(statusMessage: '未找到上次阅读的书籍，请重新选择。');
  }

  return LaunchState(restoredBooks: List<Book>.unmodifiable(savedBooks));
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

  @override
  void initState() {
    super.initState();
    _restoredBooks = widget.initialState.restoredBooks;
    _statusMessage = widget.initialState.statusMessage;
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
          backgroundColor: backgroundSettings.palette.color,
          drawerEdgeDragWidth: 120,
          drawerScrimColor: Colors.black.withValues(alpha: 0.18),
          appBar: AppBar(title: const Text('FluidText')),
          drawer: AppDrawer(
            onOpenBookshelf: _openBookshelf,
            readingOrder: readingOrderSetting.value,
            onReadingOrderChanged: (order) {
              saveReadingOrderSetting(order);
              setState(() {});
            },
            themeMode: themeModeSetting.value,
            onThemeModeChanged: saveThemeModeSetting,
            onOpenReaderBackgroundSettings: _openReaderBackgroundSettings,
          ),
          body: ReaderBackgroundSurface(
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
                              style: Theme.of(context).textTheme.headlineSmall
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
          ),
        );
      },
    );
  }
}
