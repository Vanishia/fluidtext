import 'package:flutter/material.dart';

import '../../app_settings.dart';
import '../../db/isar_db.dart';
import '../../models/book.dart';
import '../../repositories/book_card_repository.dart';
import '../../services/book_remark_service.dart';
import '../../services/reader_session_service.dart';
import '../../widgets/shelf_glyph.dart';
import '../reader/favorite_cards_page.dart';
import '../reader/read_cards_page.dart';
import '../reader/reader_page.dart';
import '../reader/reader_background_settings.dart';
import '../reader/widgets/reader_background_surface.dart';
import '../settings/app_drawer.dart';
import '../settings/reader_background_sheet.dart';
import 'bookshelf_sheet.dart';

class BookshelfPage extends StatefulWidget {
  const BookshelfPage({super.key});

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  BookCardRepository? _repository;
  final _selectedBooks = <Book>[];
  final _bookRemarks = <int, String>{};
  bool _isLoading = true;
  bool _didAutoOpen = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final isar = await IsarDb.instance.isar;
    final repository = BookCardRepository(isar);
    final savedBookIds = await ReaderSessionService.instance
        .loadLastOpenedBookIds();
    final savedBooks = await repository.loadBooksByIds(savedBookIds);
    final remarks = await BookRemarkService.instance.load();

    if (!mounted) return;
    setState(() {
      _repository = repository;
      _selectedBooks
        ..clear()
        ..addAll(savedBooks);
      _bookRemarks
        ..clear()
        ..addAll(remarks);
      _isLoading = false;
    });

    if (savedBooks.isNotEmpty && !_didAutoOpen) {
      _didAutoOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => BookCardsPage(books: savedBooks)),
        );
      });
    }
  }

  String _selectionTitle() {
    if (_selectedBooks.isEmpty) return '还没有上次阅读';
    if (_selectedBooks.length == 1) return _displayTitle(_selectedBooks.first);
    return '上次阅读 · ${_selectedBooks.length} 本';
  }

  String _selectionSummary() {
    if (_selectedBooks.isEmpty) {
      return '前往书架管理书籍，选好后会直接进入阅读。';
    }
    return _selectedBooks.map(_displayTitle).join('、');
  }

  String _displayTitle(Book book) => _bookRemarks[book.id] ?? book.title;

  Map<int, String> _selectedBookTitlesById() {
    return {for (final book in _selectedBooks) book.id: _displayTitle(book)};
  }

  Future<void> _applySelection(List<Book> selected) async {
    await ReaderSessionService.instance.saveLastOpenedBookIds(
      selected.map((book) => book.id).toList(),
    );
    if (!mounted) return;

    setState(() {
      _selectedBooks
        ..clear()
        ..addAll(selected);
    });
  }

  Future<void> _openBookshelf() async {
    final selected = await showBookshelfSheet(
      context,
      initialSelectedBookIds: _selectedBooks.map((book) => book.id).toList(),
    );
    if (selected == null || !mounted) return;

    final remarks = await BookRemarkService.instance.load();
    if (!mounted) return;
    setState(() {
      _bookRemarks
        ..clear()
        ..addAll(remarks);
    });

    await _applySelection(selected);
    if (!mounted || selected.isEmpty) return;

    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => BookCardsPage(books: selected)));
  }

  void _openReadList() {
    final repository = _repository;
    if (repository == null || _selectedBooks.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReadCardsPage(
          bookIds: _selectedBooks.map((book) => book.id).toList(),
          shelfTitle: _selectionTitle(),
          repository: repository,
          bookTitlesById: _selectedBookTitlesById(),
        ),
      ),
    );
  }

  void _openFavoriteList() {
    final repository = _repository;
    if (repository == null || _selectedBooks.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FavoriteCardsPage(
          bookIds: _selectedBooks.map((book) => book.id).toList(),
          shelfTitle: _selectionTitle(),
          repository: repository,
          bookTitlesById: _selectedBookTitlesById(),
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
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
            onOpenReadList: _selectedBooks.isEmpty ? null : _openReadList,
            onOpenFavoriteList: _selectedBooks.isEmpty
                ? null
                : _openFavoriteList,
            onOpenReaderBackgroundSettings: _openReaderBackgroundSettings,
          ),
          body: ReaderBackgroundSurface(
            settings: backgroundSettings,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ShelfGlyph(
                              size: 34,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              strokeWidth: 2.2,
                            ),
                            const SizedBox(height: 18),
                            Text(
                              _selectionTitle(),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _selectionSummary(),
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
                              label: Text(
                                _selectedBooks.isEmpty ? '前往书架管理书籍' : '打开当前书单',
                              ),
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
