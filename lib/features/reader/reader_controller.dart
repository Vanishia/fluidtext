import 'dart:math';

import 'package:flutter/foundation.dart';
import '../../models/book_card.dart';
import '../../repositories/book_card_repository.dart';
import 'reading_order.dart';

class ReaderController extends ChangeNotifier {
  ReaderController({
    required this.repository,
    required this.bookId,
    this.initialReadingOrder = ReadingOrder.sequential,
  }) : _readingOrder = initialReadingOrder;

  final BookCardRepository repository;
  final int bookId;
  final ReadingOrder initialReadingOrder;
  final Random _random = Random();

  static const pageSize = 60;

  ReadingOrder _readingOrder;
  final List<BookCard> _cards = <BookCard>[];
  final List<int> _orderedCardIds = <int>[];
  final List<int> _shuffledCardIds = <int>[];

  bool _hasMore = true;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  int _offset = 0;
  int _randomOffset = 0;

  List<BookCard> get cards => List.unmodifiable(_cards);
  ReadingOrder get readingOrder => _readingOrder;
  bool get hasMore => _hasMore;
  bool get isLoadingInitial => _isLoadingInitial;
  bool get isLoadingMore => _isLoadingMore;

  Future<void> reloadCards() async {
    _isLoadingInitial = true;
    notifyListeners();

    final ids = await repository.loadOrderedCardIds(bookId);

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
      final pageIds = _nextPageIds();
      if (pageIds.isEmpty) {
        _hasMore = false;
        return;
      }

      final page = await repository.loadCardsByIds(pageIds);

      _cards.addAll(page);
      _hasMore = _hasMoreAfterCurrentPage();
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
