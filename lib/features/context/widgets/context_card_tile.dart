import 'package:flutter/material.dart';

import '../../../models/book_card.dart';

class ContextCardTile extends StatelessWidget {
  const ContextCardTile({
    super.key,
    required this.card,
    required this.isCenter,
    required this.onToggleRead,
    required this.onToggleFavorite,
    required this.onShowContext,
  });

  final BookCard card;
  final bool isCenter;
  final VoidCallback onToggleRead;
  final VoidCallback onToggleFavorite;
  final VoidCallback onShowContext;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isCenter
              ? colorScheme.primary.withValues(alpha: 0.18)
              : colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      color: isCenter
          ? colorScheme.primaryContainer.withValues(alpha: 0.58)
          : colorScheme.surface.withValues(alpha: 0.68),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isCenter
                    ? colorScheme.primary.withValues(alpha: 0.12)
                    : colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                isCenter ? '当前卡片 #${card.cardIndex}' : '#${card.cardIndex}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              card.content,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    card.isRead ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: card.isRead ? Colors.green : colorScheme.onSurfaceVariant,
                  ),
                  tooltip: card.isRead ? '取消已读' : '标记已读',
                  onPressed: onToggleRead,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    card.isFavorite ? Icons.favorite : Icons.favorite_outline,
                    color: card.isFavorite
                        ? Colors.red
                        : colorScheme.onSurfaceVariant,
                  ),
                  tooltip: card.isFavorite ? '取消收藏' : '收藏',
                  onPressed: onToggleFavorite,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.unfold_more),
                  tooltip: isCenter ? '当前中心卡片' : '展开上下文',
                  onPressed: isCenter ? null : onShowContext,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
