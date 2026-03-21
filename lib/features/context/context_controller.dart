import 'package:flutter/foundation.dart';

import '../../models/book_card.dart';
import '../../repositories/book_card_repository.dart';
import 'context_settings.dart';

class ContextController extends ChangeNotifier {
  ContextController({
    required this.repository,
    required this.bookId,
    required BookCard initialCard,
    required ContextSettings initialSettings,
  })  : _centerCard = initialCard,
        _settings = initialSettings;

  final BookCardRepository repository;
  final int bookId;

  BookCard _centerCard;
  ContextSettings _settings;
  final List<BookCard> _cards = <BookCard>[];
  bool _isLoading = false;

  BookCard get centerCard => _centerCard;
  ContextSettings get settings => _settings;
  List<BookCard> get cards => List.unmodifiable(_cards);
  bool get isLoading => _isLoading;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    try {
      final loaded = await repository.loadContextCards(
        bookId: bookId,
        centerCardIndex: _centerCard.cardIndex,
        before: _settings.before,
        after: _settings.after,
      );
      _cards
        ..clear()
        ..addAll(loaded);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> focusOn(BookCard card) async {
    _centerCard = card;
    await load();
  }

  Future<void> updateSettings(ContextSettings settings) async {
    _settings = settings;
    await load();
  }

  Future<void> toggleFavorite(BookCard card) async {
    await repository.toggleFavorite(card);
    notifyListeners();
  }
}
