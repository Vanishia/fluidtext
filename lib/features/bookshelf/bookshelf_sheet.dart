import 'dart:developer' as developer;

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';

import '../../db/isar_db.dart';
import '../../models/book.dart';
import '../../repositories/book_card_repository.dart';
import '../../services/book_remark_service.dart';
import '../../services/book_import_service.dart';
import '../../services/data_backup_service.dart';
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
  final _backupService = const DataBackupService();
  final _books = <Book>[];
  final _remarks = <int, String>{};
  final _stats = <int, BookCardStats>{};
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
    final remarks = await BookRemarkService.instance.load();
    final stats = await repository.loadBookStats(
      books.map((book) => book.id).toList(),
    );
    await repository.logDatabaseSnapshot('bookshelf init');

    if (!mounted) return;
    setState(() {
      _isar = isar;
      _repository = repository;
      _books
        ..clear()
        ..addAll(books);
      _remarks
        ..clear()
        ..addAll(remarks);
      _stats
        ..clear()
        ..addAll(stats);
      _selectedIds.removeWhere((id) => !_books.any((book) => book.id == id));
      _isLoading = false;
    });
  }

  Future<void> _reloadBooks() async {
    final repository = _repository;
    if (repository == null) return;

    final books = await repository.loadBooks();
    final stats = await repository.loadBookStats(
      books.map((book) => book.id).toList(),
    );
    if (!mounted) return;
    setState(() {
      _books
        ..clear()
        ..addAll(books);
      _stats
        ..clear()
        ..addAll(stats);
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
        sourceFileName: file?.name,
      );

      await _reloadBooks();
      if (!mounted) return;

      setState(() {
        _selectedIds.add(imported.bookId);
        _status = imported.wasDuplicate
            ? '《${imported.bookTitle}》已存在，已选中原书'
            : '已导入《${imported.bookTitle}》';
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

  Future<void> _exportBackup() async {
    final isar = _isar;
    if (isar == null || _isBusy) return;

    setState(() {
      _isBusy = true;
      _status = '正在导出备份…';
    });

    try {
      final path = await _backupService.exportBackup(isar);
      if (!mounted) return;
      setState(() {
        _status = path == null ? '已取消导出备份' : '备份已导出：$path';
      });
    } catch (error, stackTrace) {
      developer.log(
        'Backup export failed in bookshelf sheet',
        name: 'BookshelfSheet',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() => _status = '备份导出失败：$error');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _deleteBook(Book book) async {
    final repository = _repository;
    if (repository == null || _isBusy) return;
    final title = _displayTitle(book);

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除书籍'),
        content: Text('将删除《$title》及其所有卡片，是否继续？'),
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
      await BookRemarkService.instance.removeRemark(book.id);
      await _reloadBooks();
      if (!mounted) return;
      setState(() {
        _selectedIds.remove(book.id);
        _remarks.remove(book.id);
        _status = '已删除《$title》';
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

  Future<void> _editRemark(Book book) async {
    if (_isBusy) return;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => _BookRemarkDialog(
        initialValue: _remarks[book.id] ?? book.title,
        originalTitle: book.title,
      ),
    );
    if (result == null) return;

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    setState(() {
      _isBusy = true;
      _status = '正在保存备注…';
    });

    try {
      await BookRemarkService.instance.saveRemark(book.id, result);
      final trimmed = result.trim();
      if (!mounted) return;
      setState(() {
        if (trimmed.isEmpty) {
          _remarks.remove(book.id);
          _status = '已清除《${book.title}》的备注';
        } else {
          _remarks[book.id] = trimmed;
          _status = '已备注为《$trimmed》';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '备注保存失败：$error');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  String _displayTitle(Book book) => _remarks[book.id] ?? book.title;

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
                              tooltip: '导出备份',
                              onPressed: _isBusy ? null : _exportBackup,
                              icon: const Icon(Icons.ios_share_rounded),
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
                                  final remark = _remarks[book.id];
                                  final displayTitle = _displayTitle(book);
                                  final stats =
                                      _stats[book.id] ?? BookCardStats.empty;

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
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    displayTitle,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodyLarge
                                                        ?.copyWith(
                                                          fontWeight: selected
                                                              ? FontWeight.w700
                                                              : FontWeight.w500,
                                                        ),
                                                  ),
                                                  if (remark != null) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      book.title,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            color: cs
                                                                .onSurfaceVariant,
                                                          ),
                                                    ),
                                                  ],
                                                  const SizedBox(height: 7),
                                                  _BookProgress(stats: stats),
                                                ],
                                              ),
                                            ),
                                            PopupMenuButton<String>(
                                              enabled: !_isBusy,
                                              tooltip: '更多',
                                              icon: const Icon(
                                                Icons.more_horiz_rounded,
                                                size: 22,
                                              ),
                                              onSelected: (value) {
                                                WidgetsBinding.instance
                                                    .addPostFrameCallback((_) {
                                                      if (!mounted) return;
                                                      switch (value) {
                                                        case 'remark':
                                                          _editRemark(book);
                                                          break;
                                                        case 'delete':
                                                          _deleteBook(book);
                                                          break;
                                                      }
                                                    });
                                              },
                                              itemBuilder: (context) => [
                                                const PopupMenuItem(
                                                  value: 'remark',
                                                  child: ListTile(
                                                    leading: Icon(
                                                      Icons.edit_note_rounded,
                                                    ),
                                                    title: Text('备注'),
                                                    contentPadding:
                                                        EdgeInsets.zero,
                                                  ),
                                                ),
                                                const PopupMenuItem(
                                                  value: 'delete',
                                                  child: ListTile(
                                                    leading: Icon(
                                                      Icons
                                                          .delete_outline_rounded,
                                                    ),
                                                    title: Text('删除'),
                                                    contentPadding:
                                                        EdgeInsets.zero,
                                                  ),
                                                ),
                                              ],
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

class _BookRemarkDialog extends StatefulWidget {
  const _BookRemarkDialog({
    required this.initialValue,
    required this.originalTitle,
  });

  final String initialValue;
  final String originalTitle;

  @override
  State<_BookRemarkDialog> createState() => _BookRemarkDialogState();
}

class _BookRemarkDialogState extends State<_BookRemarkDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('备注书名'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: '备注名',
          hintText: widget.originalTitle,
          helperText: '留空会清除备注，原书名不会被修改',
        ),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

class _BookProgress extends StatelessWidget {
  const _BookProgress({required this.stats});

  final BookCardStats stats;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final percent = (stats.readProgress * 100).round();
    final textStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: stats.readProgress,
            minHeight: 3,
            backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.7),
            color: cs.primary.withValues(alpha: 0.72),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '已读 ${stats.readCount}/${stats.totalCount} · $percent% · 收藏 ${stats.favoriteCount}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textStyle,
        ),
      ],
    );
  }
}
