import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';

import '../../app_settings.dart';
import '../../db/isar_db.dart';
import '../../features/context/context_settings.dart';
import '../../features/reader/reader_page.dart';
import '../../features/reader/reading_order.dart';
import '../../features/settings/app_drawer.dart';
import '../../models/book.dart';
import '../../repositories/book_card_repository.dart';
import '../../services/book_import_service.dart';
import '../../widgets/blocking_loader.dart';

class BookshelfPage extends StatefulWidget {
  const BookshelfPage({super.key});

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  final _importService = const BookImportService();

  Isar? _isar;
  BookCardRepository? _repository;

  bool _isImporting = false;
  String? _importStatus;
  var _readingOrder = ReadingOrder.sequential;
  var _contextSettings = const ContextSettings();

  final _books = <Book>[];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final isar = await IsarDb.instance.isar;

    if (!mounted) return;
    setState(() {
      _isar = isar;
      _repository = BookCardRepository(isar);
    });

    await _reloadBooks();
  }

  Future<void> _pickAndImportEpub() async {
    final isar = _isar;
    if (isar == null || _isImporting) return;

    setState(() {
      _isImporting = true;
      _importStatus = '正在导入…';
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['epub'],
        withData: true,
      );
      final file = result?.files.firstOrNull;
      final bytes = file?.bytes;
      if (bytes == null) {
        if (!mounted) return;
        setState(() => _importStatus = '未选择文件');
        return;
      }

      setState(() => _importStatus = '解析与切分中…');

      final imported = await _importService.importEpubBytes(
        isar: isar,
        bytes: bytes,
      );

      if (!mounted) return;
      setState(() {
        _importStatus = '完成：写入 ${imported.insertedCards} 张卡片';
      });

      await _reloadBooks();
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BookCardsPage(
            bookId: imported.bookId,
            bookTitle: imported.bookTitle,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _importStatus = '导入失败：$error');
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _reloadBooks() async {
    final repository = _repository;
    if (repository == null) return;

    final books = await repository.loadBooks();

    if (!mounted) return;
    setState(() {
      _books
        ..clear()
        ..addAll(books);
    });
  }

  Future<void> _deleteBook(Book book) async {
    final repository = _repository;
    if (repository == null || _isImporting) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除书籍'),
        content: Text('将删除《${book.title}》及其所有卡片，是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _isImporting = true;
      _importStatus = '正在删除…';
    });

    try {
      await repository.deleteBook(book.id);
      await _reloadBooks();
      if (!mounted) return;
      setState(() => _importStatus = '已删除：《${book.title}》');
    } catch (error) {
      if (!mounted) return;
      setState(() => _importStatus = '删除失败：$error');
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      drawerEdgeDragWidth: 120,
      drawerScrimColor: Colors.black.withValues(alpha: 0.18),
      appBar: AppBar(title: const Text('书架')),
      drawer: AppDrawer(
        isImporting: _isImporting,
        onImport: _pickAndImportEpub,
        onOpenBookshelf: () {},
        readingOrder: _readingOrder,
        onReadingOrderChanged: (order) => setState(() => _readingOrder = order),
        themeMode: themeModeSetting.value,
        onThemeModeChanged: (mode) => themeModeSetting.value = mode,
        contextBefore: _contextSettings.before,
        contextAfter: _contextSettings.after,
        onContextBeforeChanged: (value) {
          setState(() {
            _contextSettings = _contextSettings.copyWith(before: value);
          });
        },
        onContextAfterChanged: (value) {
          setState(() {
            _contextSettings = _contextSettings.copyWith(after: value);
          });
        },
      ),
      body: Stack(
        children: [
          _books.isEmpty
              ? const Center(child: Text('还没有书籍，去侧边栏导入一本 EPUB'))
              : ListView.separated(
                  padding: EdgeInsets.only(
                    bottom: bottomInset + (_importStatus == null ? 20 : 88),
                  ),
                  itemCount: _books.length,
                  separatorBuilder: (_, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final book = _books[index];
                    return ListTile(
                      title: Text(book.title),
                      subtitle: Text('ID: ${book.id}'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          switch (value) {
                            case 'open':
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => BookCardsPage(
                                    bookId: book.id,
                                    bookTitle: book.title,
                                  ),
                                ),
                              );
                              break;
                            case 'delete':
                              _deleteBook(book);
                              break;
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'open',
                            child: Text('打开'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('删除'),
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => BookCardsPage(
                              bookId: book.id,
                              bookTitle: book.title,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
          if (_isImporting) const BlockingLoader(),
        ],
      ),
      bottomNavigationBar: _importStatus == null
          ? null
          : SafeArea(
              maintainBottomViewPadding: true,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _importStatus!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
    );
  }
}
