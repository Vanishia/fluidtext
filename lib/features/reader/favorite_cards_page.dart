import 'package:flutter/material.dart';

import '../../app_settings.dart';
import '../../models/book_card.dart';
import '../../repositories/book_card_repository.dart';
import 'reader_background_settings.dart';
import 'widgets/reader_background_surface.dart';

class FavoriteCardsPage extends StatefulWidget {
  const FavoriteCardsPage({
    super.key,
    required this.bookIds,
    required this.shelfTitle,
    required this.repository,
  });

  final List<int> bookIds;
  final String shelfTitle;
  final BookCardRepository repository;

  @override
  State<FavoriteCardsPage> createState() => _FavoriteCardsPageState();
}

class _FavoriteCardsPageState extends State<FavoriteCardsPage> {
  final _cards = <BookCard>[];
  var _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cards = await widget.repository.loadFavoriteCards(widget.bookIds);
    if (!mounted) return;
    setState(() {
      _cards
        ..clear()
        ..addAll(cards);
      _isLoading = false;
    });
  }

  String _formatFavoriteAt(DateTime? favoritedAt) {
    if (favoritedAt == null) return '未知时间';
    final local = favoritedAt.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReaderBackgroundSettings>(
      valueListenable: readerBackgroundSetting,
      builder: (context, backgroundSettings, _) {
        return Scaffold(
          backgroundColor: backgroundSettings.palette.color,
          appBar: AppBar(title: Text('${widget.shelfTitle} · 收藏')),
          body: ReaderBackgroundSurface(
            settings: backgroundSettings,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _cards.isEmpty
                ? const Center(child: Text('还没有收藏卡片'))
                : ListView.separated(
                    itemCount: _cards.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final card = _cards[index];
                      return ListTile(
                        title: Text(
                          card.content,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${card.bookTitle} · #${card.cardIndex} · 收藏于 ${_formatFavoriteAt(card.favoritedAt)}',
                        ),
                      );
                    },
                  ),
          ),
        );
      },
    );
  }
}
