import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 140),
      opacity: card.isRead ? 0.52 : 1,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isCenter
                ? colorScheme.primary.withValues(alpha: 0.18)
                : colorScheme.outlineVariant.withValues(alpha: 0.42),
          ),
        ),
        color: isCenter
            ? colorScheme.primaryContainer.withValues(alpha: 0.72)
            : colorScheme.surface.withValues(alpha: 0.62),
        child: InkWell(
          onTap: onToggleRead,
          onLongPress: () => _copyCardContent(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isCenter
                        ? colorScheme.primary.withValues(alpha: 0.14)
                        : colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.62,
                          ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isCenter ? '当前卡片 #${card.cardIndex}' : '#${card.cardIndex}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  card.content,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontSize: 15, height: 1.5),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 36,
                      ),
                      icon: Icon(
                        card.isRead
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: card.isRead
                            ? Colors.green
                            : colorScheme.onSurfaceVariant,
                      ),
                      tooltip: card.isRead ? '取消已读' : '标记已读',
                      onPressed: onToggleRead,
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 36,
                      ),
                      icon: Icon(
                        card.isFavorite
                            ? Icons.favorite
                            : Icons.favorite_outline,
                        color: card.isFavorite
                            ? Colors.red
                            : colorScheme.onSurfaceVariant,
                      ),
                      tooltip: card.isFavorite ? '取消收藏' : '收藏',
                      onPressed: onToggleFavorite,
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 36,
                      ),
                      icon: const Icon(Icons.unfold_more),
                      tooltip: isCenter ? '当前中心卡片' : '展开上下文',
                      onPressed: isCenter ? null : onShowContext,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _copyCardContent(BuildContext context) async {
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
}
