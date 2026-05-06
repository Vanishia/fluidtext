import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/book_card.dart';
import '../../repositories/book_card_repository.dart';
import 'reading_order.dart';

class ReaderController extends ChangeNotifier {
  ReaderController({
    required this.repository,
    required this.bookIds,
    this.initialReadingOrder = ReadingOrder.random,
    this.initialShowUnreadOnly = false,
  }) : _readingOrder = initialReadingOrder,
       _showUnreadOnly = initialShowUnreadOnly;

  final BookCardRepository repository;
  final List<int> bookIds;
  final ReadingOrder initialReadingOrder;
  final bool initialShowUnreadOnly;
  final Random _random = Random();

  static const pageSize = 60;

  ReadingOrder _readingOrder;
  final List<BookCard> _cards = <BookCard>[];
  final List<int> _orderedCardIds = <int>[];
  final List<int> _shuffledCardIds = <int>[];
  bool _showUnreadOnly;

  bool _hasMore = true;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  int _offset = 0;
  int _randomOffset = 0;

  List<BookCard> get cards => List.unmodifiable(_cards);
  ReadingOrder get readingOrder => _readingOrder;
  bool get showUnreadOnly => _showUnreadOnly;
  bool get hasMore => _hasMore;
  bool get isLoadingInitial => _isLoadingInitial;
  bool get isLoadingMore => _isLoadingMore;

  Future<void> reloadCards() async {
    _isLoadingInitial = true;
    notifyListeners();

    final ids = _showUnreadOnly
        ? await repository.loadUnreadOrderedCardIds(bookIds)
        : await repository.loadOrderedCardIds(bookIds);

    _cards.clear();
    _offset = 0;
    _randomOffset = 0;
    _orderedCardIds
      ..clear()
      ..addAll(ids);
    _shuffledCardIds
      ..clear()
      ..addAll(ids);

    if (_readingOrder == ReadingOrder.random) {
      _shuffledCardIds.shuffle(_random);
    }

    _hasMore = ids.isNotEmpty;
    _isLoadingInitial = false;
    notifyListeners();

    await loadMore();
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      while (true) {
        final pageIds = _nextPageIds();
        if (pageIds.isEmpty) {
          _hasMore = false;
          return;
        }

        final page = _showUnreadOnly
            ? await repository.loadUnreadCardsByIds(pageIds)
            : await repository.loadCardsByIds(pageIds);

        if (page.isNotEmpty) {
          _cards.addAll(page);
          _hasMore = _hasMoreAfterCurrentPage();
          return;
        }

        if (!_hasMoreAfterCurrentPage()) {
          _hasMore = false;
          return;
        }
      }
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> setReadingOrder(ReadingOrder next) async {
    if (_readingOrder == next) return;
    _readingOrder = next;
    await reloadCards();
  }

  Future<void> setShowUnreadOnly(bool value) async {
    if (_showUnreadOnly == value) return;
    _showUnreadOnly = value;
    await reloadCards();
  }

  Future<void> toggleRead(BookCard card) async {
    await repository.toggleRead(card);
    await refreshCard(card);
  }

  Future<void> toggleFavorite(BookCard card) async {
    await repository.toggleFavorite(card);
    await refreshCard(card);
  }

  Future<void> refreshCard(BookCard card) async {
    final index = _cards.indexWhere((item) => item.id == card.id);
    if (index == -1) return;
    _cards[index] = card;
    notifyListeners();
  }

  List<int> _nextPageIds() {
    if (_readingOrder == ReadingOrder.sequential) {
      final start = _offset;
      if (start >= _orderedCardIds.length) return const [];
      final end = min(start + pageSize, _orderedCardIds.length);
      _offset = end;
      return _orderedCardIds.sublist(start, end);
    }

    final start = _randomOffset;
    if (start >= _shuffledCardIds.length) return const [];
    final end = min(start + pageSize, _shuffledCardIds.length);
    _randomOffset = end;
    return _shuffledCardIds.sublist(start, end);
  }

  bool _hasMoreAfterCurrentPage() {
    if (_readingOrder == ReadingOrder.sequential) {
      return _offset < _orderedCardIds.length;
    }
    return _randomOffset < _shuffledCardIds.length;
  }
}
