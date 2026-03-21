import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';

import '../../app_settings.dart';
import '../../db/isar_db.dart';
import '../../models/book_card.dart';
import '../../repositories/book_card_repository.dart';
import '../../services/book_import_service.dart';
import '../../widgets/blocking_loader.dart';
import '../context/context_controller.dart';
import '../context/context_settings.dart';
import '../context/context_sheet.dart';
import '../settings/app_drawer.dart';
import 'reader_controller.dart';
import 'widgets/book_card_tile.dart';

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

  Isar? _isar;
  BookCardRepository? _repository;
  ReaderController? _controller;

  bool _isImporting = false;
  String? _importStatus;
  ContextSettings _contextSettings = const ContextSettings();

  @override
  void initState() {
    super.initState();
    _init();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final isar = await IsarDb.instance.isar;
    final repository = BookCardRepository(isar);
    final controller = ReaderController(
      repository: repository,
      bookId: widget.bookId,
    );
    await controller.reloadCards();

    if (!mounted) {
      controller.dispose();
      return;
    }

    setState(() {
      _isar = isar;
      _repository = repository;
      _controller = controller;
    });
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
        await _controller?.reloadCards();
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
    } catch (error) {
      if (!mounted) return;
      setState(() => _importStatus = '导入失败：$error');
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _toggleFavorite(BookCard card) async {
    final repository = _repository;
    if (repository == null) return;

    await repository.toggleFavorite(card);

    await _controller?.refreshCard(card);
  }

  Future<void> _showContext(BookCard card) async {
    final repository = _repository;
    if (repository == null) return;

    final contextController = ContextController(
      repository: repository,
      bookId: widget.bookId,
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
        bookTitle: widget.bookTitle,
      ),
    );

    if (mounted) {
      setState(() {
        _contextSettings = contextController.settings;
      });
    }
    contextController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    if (controller == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          drawerEdgeDragWidth: 120,
          drawerScrimColor: Colors.black.withValues(alpha: 0.18),
          appBar: AppBar(
            title: Text(widget.bookTitle),
          ),
          drawer: AppDrawer(
            isImporting: _isImporting,
            onImport: _pickAndImportEpub,
            onOpenBookshelf: () => Navigator.of(context).popUntil((route) => route.isFirst),
            readingOrder: controller.readingOrder,
            onReadingOrderChanged: controller.setReadingOrder,
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
              controller.isLoadingInitial && controller.cards.isEmpty
                  ? const Center(child: Text('加载中…'))
                  : ListView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.only(
                        bottom: bottomInset + (_importStatus == null ? 20 : 88),
                      ),
                      itemCount: controller.cards.length + (controller.hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= controller.cards.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        final card = controller.cards[index];
                        return BookCardTile(
                          card: card,
                          onToggleFavorite: () => _toggleFavorite(card),
                          onShowContext: () => _showContext(card),
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
      },
    );
  }
}
