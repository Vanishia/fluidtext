import 'dart:math';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';

import 'db/isar_db.dart';
import 'models/book.dart';
import 'models/book_card.dart';
import 'services/book_import_service.dart';

void main() => runApp(const MyApp());

enum ReadingOrder { sequential, random }

final readingOrderSetting = ValueNotifier(ReadingOrder.sequential);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FluidText',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const BookshelfPage(),
    );
  }
}

class BookshelfPage extends StatefulWidget {
  const BookshelfPage({super.key});

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  final _importService = const BookImportService();

  Isar? _isar;

  bool _isImporting = false;
  String? _importStatus;

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
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BookCardsPage(
              bookId: imported.bookId,
              bookTitle: imported.bookTitle,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _importStatus = '导入失败：$e');
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _reloadBooks() async {
    final isar = _isar;
    if (isar == null) return;

    final books = await isar.books.where().sortByCreatedAtDesc().findAll();

    if (!mounted) return;
    setState(() {
      _books
        ..clear()
        ..addAll(books);
    });
  }

  Future<void> _deleteBook(Book book) async {
    final isar = _isar;
    if (isar == null || _isImporting) return;

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
      await isar.writeTxn(() async {
        final cardIds = await isar.bookCards
            .filter()
            .bookIdEqualTo(book.id)
            .idProperty()
            .findAll();
        if (cardIds.isNotEmpty) {
          await isar.bookCards.deleteAll(cardIds);
        }
        await isar.books.delete(book.id);
      });

      await _reloadBooks();
      if (!mounted) return;
      setState(() => _importStatus = '已删除：《${book.title}》');
    } catch (e) {
      if (!mounted) return;
      setState(() => _importStatus = '删除失败：$e');
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('书架')),
      drawer: _AppDrawer(
        isImporting: _isImporting,
        onImport: _pickAndImportEpub,
        readingOrder: readingOrderSetting.value,
        onReadingOrderChanged: (order) => readingOrderSetting.value = order,
      ),
      body: Stack(
        children: [
          _books.isEmpty
              ? const Center(child: Text('还没有书籍，去侧边栏导入一本 EPUB'))
              : ListView.separated(
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
          if (_isImporting) const _BlockingLoader(),
        ],
      ),
      bottomNavigationBar: _importStatus == null
          ? null
          : SafeArea(
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

class BookCardsPage extends StatefulWidget {
  const BookCardsPage({
    super.key,
    required this.bookId,
    required this.bookTitle,
  });

  final int bookId;
  final String bookTitle;

  @override
  State<BookCardsPage> createState() => _BookCardsPageState();
}

class _BookCardsPageState extends State<BookCardsPage> {
  final _importService = const BookImportService();
  final _scrollController = ScrollController();
  final _random = Random();

  Isar? _isar;

  bool _isImporting = false;
  String? _importStatus;
  ReadingOrder _readingOrder = readingOrderSetting.value;

  final _cards = <BookCard>[];
  var _hasMore = true;
  var _isLoadingMore = false;
  var _offset = 0;
  final _orderedCardIds = <int>[];
  final _shuffledCardIds = <int>[];
  var _randomOffset = 0;
  static const _pageSize = 60;

  @override
  void initState() {
    super.initState();
    _init();
    _scrollController.addListener(_maybeLoadMore);
    readingOrderSetting.addListener(_onReadingOrderChanged);
  }

  @override
  void dispose() {
    readingOrderSetting.removeListener(_onReadingOrderChanged);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final isar = await IsarDb.instance.isar;
    if (!mounted) return;
    setState(() => _isar = isar);
    await _reloadCards();
  }

  void _onReadingOrderChanged() {
    final next = readingOrderSetting.value;
    if (next == _readingOrder) return;
    if (!mounted) return;
    setState(() => _readingOrder = next);
    _reloadCards();
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
      setState(() => _importStatus = '完成：写入 ${imported.insertedCards} 张卡片');

      if (imported.bookId == widget.bookId) {
        await _reloadCards();
      } else {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => BookCardsPage(
              bookId: imported.bookId,
              bookTitle: imported.bookTitle,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _importStatus = '导入失败：$e');
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _reloadCards() async {
    final isar = _isar;
    if (isar == null) return;

    final ids = await isar.bookCards
        .filter()
        .bookIdEqualTo(widget.bookId)
        .sortByCardIndex()
        .idProperty()
        .findAll();

    setState(() {
      _cards.clear();
      _offset = 0;
      _orderedCardIds
        ..clear()
        ..addAll(ids);
      _shuffledCardIds
        ..clear()
        ..addAll(ids);
      _randomOffset = 0;
      if (_readingOrder == ReadingOrder.random) {
        _shuffledCardIds.shuffle(_random);
      }
      _hasMore = ids.isNotEmpty;
    });

    await _loadMore();
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients) return;
    if (_isLoadingMore || !_hasMore) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    final isar = _isar;
    if (isar == null) return;
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);
    try {
      final pageIds = _nextPageIds();
      if (pageIds.isEmpty) {
        if (!mounted) return;
        setState(() => _hasMore = false);
        return;
      }

      final fetched = await isar.bookCards
          .filter()
          .anyOf(pageIds, (query, id) => query.idEqualTo(id))
          .findAll();
      final mapById = {for (final card in fetched) card.id: card};
      final page = pageIds.map((id) => mapById[id]).whereType<BookCard>().toList();

      if (!mounted) return;
      setState(() {
        _cards.addAll(page);
        _hasMore = _hasMoreAfterCurrentPage();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  List<int> _nextPageIds() {
    if (_readingOrder == ReadingOrder.sequential) {
      final start = _offset;
      if (start >= _orderedCardIds.length) return const [];
      final end = min(start + _pageSize, _orderedCardIds.length);
      _offset = end;
      return _orderedCardIds.sublist(start, end);
    }

    final start = _randomOffset;
    if (start >= _shuffledCardIds.length) return const [];
    final end = min(start + _pageSize, _shuffledCardIds.length);
    _randomOffset = end;
    return _shuffledCardIds.sublist(start, end);
  }

  bool _hasMoreAfterCurrentPage() {
    if (_readingOrder == ReadingOrder.sequential) {
      return _offset < _orderedCardIds.length;
    }
    return _randomOffset < _shuffledCardIds.length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bookTitle),
      ),
      drawer: _AppDrawer(
        isImporting: _isImporting,
        onImport: _pickAndImportEpub,
        readingOrder: _readingOrder,
        onReadingOrderChanged: (order) => readingOrderSetting.value = order,
      ),
      body: Stack(
        children: [
          _cards.isEmpty
              ? const Center(child: Text('加载中…'))
              : ListView.builder(
                  controller: _scrollController,
                  itemCount: _cards.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _cards.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final card = _cards[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '#${card.cardIndex}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              card.content,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          if (_isImporting) const _BlockingLoader(),
        ],
      ),
      bottomNavigationBar: _importStatus == null
          ? null
          : SafeArea(
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

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({
    required this.isImporting,
    required this.onImport,
    required this.readingOrder,
    required this.onReadingOrderChanged,
  });

  final bool isImporting;
  final VoidCallback onImport;
  final ReadingOrder readingOrder;
  final ValueChanged<ReadingOrder> onReadingOrderChanged;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            const ListTile(
              title: Text('FluidText'),
              subtitle: Text('书架 / 导入'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.library_books_outlined),
              title: const Text('书架'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const BookshelfPage()),
                  (_) => false,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('导入 EPUB'),
              enabled: !isImporting,
              onTap: () {
                Navigator.of(context).pop();
                onImport();
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.format_list_numbered),
              title: const Text('顺序阅读'),
              trailing: readingOrder == ReadingOrder.sequential
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                onReadingOrderChanged(ReadingOrder.sequential);
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.shuffle),
              title: const Text('乱序阅读'),
              trailing: readingOrder == ReadingOrder.random
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                onReadingOrderChanged(ReadingOrder.random);
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockingLoader extends StatelessWidget {
  const _BlockingLoader();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('处理中…'),
            ],
          ),
        ),
      ),
    );
  }
}
