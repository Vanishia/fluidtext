import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';

import 'db/isar_db.dart';
import 'models/book.dart';
import 'models/book_card.dart';
import 'services/book_import_service.dart';

void main() => runApp(const MyApp());

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
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _importService = const BookImportService();
  final _scrollController = ScrollController();

  Isar? _isar;
  int? _currentBookId;
  String? _currentBookTitle;

  bool _isImporting = false;
  String? _importStatus;

  final _cards = <BookCard>[];
  var _hasMore = true;
  var _isLoadingMore = false;
  var _offset = 0;
  static const _pageSize = 60;

  @override
  void initState() {
    super.initState();
    _init();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final isar = await IsarDb.instance.isar;
    final lastBook = await isar.books.where().sortByCreatedAtDesc().findFirst();

    if (!mounted) return;
    setState(() {
      _isar = isar;
      _currentBookId = lastBook?.id;
      _currentBookTitle = lastBook?.title;
    });

    await _reloadCards();
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
        _currentBookId = imported.bookId;
        _currentBookTitle = imported.bookTitle;
        _importStatus = '完成：写入 ${imported.insertedCards} 张卡片';
      });

      await _reloadCards();
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
    final bookId = _currentBookId;
    if (isar == null || bookId == null) {
      if (!mounted) return;
      setState(() {
        _cards.clear();
        _offset = 0;
        _hasMore = false;
      });
      return;
    }

    setState(() {
      _cards.clear();
      _offset = 0;
      _hasMore = true;
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
    final bookId = _currentBookId;
    if (isar == null || bookId == null) return;
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);
    try {
      final page = await isar.bookCards
          .filter()
          .bookIdEqualTo(bookId)
          .sortByCardIndex()
          .offset(_offset)
          .limit(_pageSize)
          .findAll();

      if (!mounted) return;
      setState(() {
        _cards.addAll(page);
        _offset += page.length;
        _hasMore = page.length == _pageSize;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookTitle = _currentBookTitle ?? '未导入书籍';

    return Scaffold(
      appBar: AppBar(
        title: Text(bookTitle),
        actions: [
          IconButton(
            onPressed: _isImporting ? null : _pickAndImportEpub,
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: '导入 EPUB',
          ),
        ],
      ),
      body: Stack(
        children: [
          _cards.isEmpty
              ? Center(
                  child: Text(
                    _currentBookId == null ? '请先导入一本 EPUB' : '加载中…',
                  ),
                )
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isImporting ? null : _pickAndImportEpub,
        icon: const Icon(Icons.add),
        label: const Text('导入 EPUB'),
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
