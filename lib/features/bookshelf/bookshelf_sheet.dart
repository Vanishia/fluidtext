import 'dart:developer' as developer;

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';

import '../../db/isar_db.dart';
import '../../models/book.dart';
import '../../repositories/book_card_repository.dart';
import '../../services/book_import_service.dart';
import '../../widgets/blocking_loader.dart';
import '../../widgets/glass.dart';

Future<List<Book>?> showBookshelfSheet(
  BuildContext context, {
  List<int> initialSelectedBookIds = const <int>[],
}) {
  return showModalBottomSheet<List<Book>>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        BookshelfSheet(initialSelectedBookIds: initialSelectedBookIds),
  );
}

class BookshelfSheet extends StatefulWidget {
  const BookshelfSheet({
    super.key,
    this.initialSelectedBookIds = const <int>[],
  });

  final List<int> initialSelectedBookIds;

  @override
  State<BookshelfSheet> createState() => _BookshelfSheetState();
}

class _BookshelfSheetState extends State<BookshelfSheet> {
  final _importService = const BookImportService();
  final _books = <Book>[];
  late final Set<int> _selectedIds = widget.initialSelectedBookIds.toSet();

  BookCardRepository? _repository;
  Isar? _isar;
  bool _isLoading = true;
  bool _isBusy = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final isar = await IsarDb.instance.isar;
    final repository = BookCardRepository(isar);
    final books = await repository.loadBooks();

    if (!mounted) return;
    setState(() {
      _isar = isar;
      _repository = repository;
      _books
        ..clear()
        ..addAll(books);
      _selectedIds.removeWhere((id) => !_books.any((book) => book.id == id));
      _isLoading = false;
    });
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
      _selectedIds.removeWhere((id) => !_books.any((book) => book.id == id));
    });
  }

  Future<void> _pickAndImportEpub() async {
    final isar = _isar;
    if (isar == null || _isBusy) return;

    setState(() {
      _isBusy = true;
      _status = '正在导入…';
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
        setState(() => _status = '未选择文件');
        return;
      }

      setState(() => _status = '解析与切分中…');

      final imported = await _importService.importEpubBytes(
        isar: isar,
        bytes: bytes,
      );

      await _reloadBooks();
      if (!mounted) return;

      setState(() {
        _selectedIds.add(imported.bookId);
        _status = '已导入《${imported.bookTitle}》';
      });
    } catch (error, stackTrace) {
      developer.log(
        'EPUB import failed in bookshelf sheet',
        name: 'BookshelfSheet',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() => _status = '导入失败：$error');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _deleteBook(Book book) async {
    final repository = _repository;
    if (repository == null || _isBusy) return;

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
      _isBusy = true;
      _status = '正在删除…';
    });

    try {
      await repository.deleteBook(book.id);
      await _reloadBooks();
      if (!mounted) return;
      setState(() {
        _selectedIds.remove(book.id);
        _status = '已删除《${book.title}》';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '删除失败：$error');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  List<Book> _selectedBooks() {
    return _books.where((book) => _selectedIds.contains(book.id)).toList();
  }

  void _toggleSelected(Book book) {
    setState(() {
      if (_selectedIds.contains(book.id)) {
        _selectedIds.remove(book.id);
      } else {
        _selectedIds.add(book.id);
      }
    });
  }

  void _close() {
    Navigator.of(context).pop(List<Book>.unmodifiable(_selectedBooks()));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope<List<Book>>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _close();
        }
      },
      child: FractionallySizedBox(
        heightFactor: 0.88,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Stack(
              children: [
                Glass(
                  color: cs.surface.withValues(alpha: isDark ? 0.46 : 0.84),
                  borderColor: cs.outlineVariant.withValues(
                    alpha: isDark ? 0.2 : 0.32,
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 10, 10),
                        child: Row(
                          children: [
                            Text(
                              '书架',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: '导入 EPUB',
                              onPressed: _isBusy ? null : _pickAndImportEpub,
                              icon: const Icon(Icons.add_rounded),
                            ),
                            IconButton(
                              tooltip: '关闭',
                              onPressed: _close,
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                      if (_status != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _status!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ),
                        ),
                      const Divider(height: 1),
                      Expanded(
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : _books.isEmpty
                            ? Center(
                                child: Text(
                                  '还没有书',
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  8,
                                  10,
                                  84,
                                ),
                                itemCount: _books.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 6),
                                itemBuilder: (context, index) {
                                  final book = _books[index];
                                  final selected = _selectedIds.contains(
                                    book.id,
                                  );

                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(18),
                                      onTap: _isBusy
                                          ? null
                                          : () => _toggleSelected(book),
                                      child: Ink(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? cs.secondaryContainer
                                                    .withValues(alpha: 0.7)
                                              : cs.surfaceContainerHigh
                                                    .withValues(alpha: 0.52),
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Checkbox(
                                              value: selected,
                                              onChanged: _isBusy
                                                  ? null
                                                  : (_) =>
                                                        _toggleSelected(book),
                                            ),
                                            Expanded(
                                              child: Text(
                                                book.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge
                                                    ?.copyWith(
                                                      fontWeight: selected
                                                          ? FontWeight.w700
                                                          : FontWeight.w500,
                                                    ),
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: '删除',
                                              onPressed: _isBusy
                                                  ? null
                                                  : () => _deleteBook(book),
                                              icon: const Icon(
                                                Icons.delete_outline_rounded,
                                                size: 20,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 20,
                  bottom: 20,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: _close,
                      child: Ink(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: cs.surface.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: cs.outlineVariant.withValues(alpha: 0.42),
                          ),
                        ),
                        child: Icon(
                          Icons.done_rounded,
                          size: 20,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_isBusy) const BlockingLoader(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
