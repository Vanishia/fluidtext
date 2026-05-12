import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_settings.dart';
import '../../features/context/context_controller.dart';
import '../../features/context/context_settings.dart';
import '../../features/context/context_sheet.dart';
import '../../models/book_card.dart';
import '../../repositories/book_card_repository.dart';
import '../../services/book_remark_service.dart';
import 'reader_background_settings.dart';
import 'widgets/reader_background_surface.dart';

class ReadCardsPage extends StatefulWidget {
  const ReadCardsPage({
    super.key,
    required this.bookIds,
    required this.shelfTitle,
    required this.repository,
    this.bookTitlesById = const <int, String>{},
  });

  final List<int> bookIds;
  final String shelfTitle;
  final BookCardRepository repository;
  final Map<int, String> bookTitlesById;

  @override
  State<ReadCardsPage> createState() => _ReadCardsPageState();
}

class _ReadCardsPageState extends State<ReadCardsPage> {
  final _cards = <BookCard>[];
  final _bookTitlesById = <int, String>{};
  ContextSettings _contextSettings = contextSettingsSetting.value;
  var _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cards = await widget.repository.loadReadCards(widget.bookIds);
    final bookTitlesById = await _loadBookTitlesById();
    if (!mounted) return;
    setState(() {
      _cards
        ..clear()
        ..addAll(cards);
      _bookTitlesById
        ..clear()
        ..addAll(bookTitlesById);
      _isLoading = false;
    });
  }

  Future<Map<int, String>> _loadBookTitlesById() async {
    final books = await widget.repository.loadBooks();
    final remarks = await BookRemarkService.instance.load();
    return {for (final book in books) book.id: remarks[book.id] ?? book.title};
  }

  String _formatReadAt(DateTime? readAt) {
    if (readAt == null) return '未知时间';
    final local = readAt.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }

  String _bookTitle(BookCard card) {
    return _bookTitlesById[card.bookId] ??
        widget.bookTitlesById[card.bookId] ??
        card.bookTitle;
  }

  Future<void> _copyCardContent(BuildContext context, BookCard card) async {
    await Clipboard.setData(ClipboardData(text: card.content));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Copied'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1200),
          margin: const EdgeInsets.fromLTRB(24, 0, 24, 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
  }

  Future<void> _showContext(BookCard card) async {
    final contextController = ContextController(
      repository: widget.repository,
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
        bookTitle: _bookTitle(card),
      ),
    );

    if (mounted) {
      saveContextSettingsSetting(contextController.settings);

      final changedCards = await widget.repository.loadCardsByIds(
        contextController.changedCardIds.toList(),
      );
      if (mounted) {
        setState(() {
          _contextSettings = contextController.settings;
          final changedMap = {for (final c in changedCards) c.id: c};
          for (var i = 0; i < _cards.length; i++) {
            final updated = changedMap[_cards[i].id];
            if (updated != null) {
              _cards[i] = updated;
            }
          }
          _cards.removeWhere((c) => !c.isRead);
        });
      } else {
        contextController.dispose();
        return;
      }
    }
    contextController.dispose();
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_cards.isEmpty) {
      return const Center(child: Text('还没有已读卡片'));
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: _cards.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        indent: 12,
        endIndent: 12,
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: 0.28),
      ),
      itemBuilder: (context, index) {
        return _ReadCardItem(
          card: _cards[index],
          readAtText: _formatReadAt(_cards[index].readAt),
          onCopy: () => _copyCardContent(context, _cards[index]),
          onShowContext: () => _showContext(_cards[index]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReaderBackgroundSettings>(
      valueListenable: readerBackgroundSetting,
      builder: (context, backgroundSettings, _) {
        return Scaffold(
          backgroundColor: backgroundSettings.palette.color,
          body: ReaderBackgroundSurface(
            settings: backgroundSettings,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const _SubtleReadabilityOverlay(),
                SafeArea(
                  child: Column(
                    children: [
                      _ListPageHeader(
                        title: '${widget.shelfTitle} · 已读',
                        count: _cards.length,
                      ),
                      Expanded(child: _buildBody()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReadCardItem extends StatelessWidget {
  const _ReadCardItem({
    required this.card,
    required this.readAtText,
    required this.onCopy,
    required this.onShowContext,
  });

  final BookCard card;
  final String readAtText;
  final VoidCallback onCopy;
  final VoidCallback onShowContext;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onLongPress: onCopy,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                card.content,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(height: 1.5, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      '#${card.cardIndex} · 已读于 $readAtText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    icon: const Icon(Icons.unfold_more),
                    tooltip: '展开上下文',
                    onPressed: onShowContext,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubtleReadabilityOverlay extends StatelessWidget {
  const _SubtleReadabilityOverlay();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.10),
    );
  }
}

class _ListPageHeader extends StatelessWidget {
  const _ListPageHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_back),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 14, left: 8),
            child: Text(
              '$count 张',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
