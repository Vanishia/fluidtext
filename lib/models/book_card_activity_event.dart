class BookCardActivityEvent {
  const BookCardActivityEvent({
    required this.cardId,
    required this.bookId,
    required this.cardIndex,
    required this.timestamp,
  });

  final int cardId;
  final int bookId;
  final int cardIndex;
  final DateTime timestamp;

  BookCardActivityEvent copyWith({
    int? cardId,
    int? bookId,
    int? cardIndex,
    DateTime? timestamp,
  }) {
    return BookCardActivityEvent(
      cardId: cardId ?? this.cardId,
      bookId: bookId ?? this.bookId,
      cardIndex: cardIndex ?? this.cardIndex,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
