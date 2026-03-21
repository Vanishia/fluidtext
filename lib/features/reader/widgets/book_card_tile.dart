import 'package:flutter/material.dart';

import '../../../models/book_card.dart';

class BookCardTile extends StatelessWidget {
  const BookCardTile({
    super.key,
    required this.card,
    required this.onToggleFavorite,
    required this.onShowContext,
  });

  final BookCard card;
  final VoidCallback onToggleFavorite;
  final VoidCallback onShowContext;

  @override
  Widget build(BuildContext context) {
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
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              card.content,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: Icon(
                    card.isFavorite ? Icons.favorite : Icons.favorite_outline,
                    color: card.isFavorite
                        ? Colors.red
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  tooltip: card.isFavorite ? '取消收藏' : '收藏',
                  onPressed: onToggleFavorite,
                ),
                IconButton(
                  icon: const Icon(Icons.unfold_more),
                  tooltip: '展开上下文',
                  onPressed: onShowContext,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
