import 'package:flutter/material.dart';

import '../../../models/book_card.dart';
import '../../../widgets/glass.dart';

class BookCardTile extends StatelessWidget {
  const BookCardTile({
    super.key,
    required this.card,
    required this.onToggleRead,
    required this.onToggleFavorite,
    required this.onShowContext,
    this.bookTitle,
    this.showBookTitle = false,
  });

  final BookCard card;
  final VoidCallback onToggleRead;
  final VoidCallback onToggleFavorite;
  final VoidCallback onShowContext;
  final String? bookTitle;
  final bool showBookTitle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final glassColor = isDark
        ? Colors.black.withValues(alpha: 0.32)
        : Colors.white.withValues(alpha: 0.52);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : cs.outlineVariant.withValues(alpha: 0.48);

    return Opacity(
      opacity: card.isRead ? 0.5 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Glass(
          color: glassColor,
          borderColor: borderColor,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggleRead,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 10, 9, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showBookTitle) ...[
                      Text(
                        bookTitle ?? card.bookTitle,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      '#${card.cardIndex}',
                      style: Theme.of(
                        context,
                      ).textTheme.labelMedium?.copyWith(color: cs.primary),
                    ),
                    const SizedBox(height: 8),
                    _CardContentText(
                      content: card.content,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(8),
                          icon: Icon(
                            card.isRead
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            color: card.isRead
                                ? Colors.green
                                : cs.onSurfaceVariant,
                          ),
                          tooltip: card.isRead ? '取消已读' : '标记已读',
                          onPressed: onToggleRead,
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(8),
                          icon: Icon(
                            card.isFavorite
                                ? Icons.favorite
                                : Icons.favorite_outline,
                            color: card.isFavorite
                                ? Colors.red
                                : cs.onSurfaceVariant,
                          ),
                          tooltip: card.isFavorite ? '取消收藏' : '收藏',
                          onPressed: onToggleFavorite,
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(8),
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
          ),
        ),
      ),
    );
  }
}

class _CardContentText extends StatelessWidget {
  const _CardContentText({required this.content, required this.style});

  final String content;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final paragraphs = content
        .split(RegExp(r'\n+'))
        .map((paragraph) => paragraph.trimRight())
        .where((paragraph) => paragraph.trim().isNotEmpty)
        .toList(growable: false);
    final textStyle = style?.copyWith(height: 1.5);

    if (paragraphs.isEmpty) {
      return Text('', style: textStyle);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < paragraphs.length; index += 1) ...[
          Text(paragraphs[index], style: textStyle),
          if (index < paragraphs.length - 1) const SizedBox(height: 2),
        ],
      ],
    );
  }
}
