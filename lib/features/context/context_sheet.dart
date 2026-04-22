import 'package:flutter/material.dart';

import '../../widgets/glass.dart';
import 'context_controller.dart';
import 'widgets/context_card_tile.dart';

class ContextSheet extends StatelessWidget {
  const ContextSheet({
    super.key,
    required this.controller,
    required this.bookTitle,
  });

  final ContextController controller;
  final String bookTitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mediaQuery = MediaQuery.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: Glass(
          color: cs.surface.withValues(alpha: isDark ? 0.97 : 0.985),
          borderColor: cs.outlineVariant.withValues(alpha: 0.22),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final settings = controller.settings;
              return SizedBox(
                width: double.infinity,
                height: mediaQuery.size.height * 0.86,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 10, 10),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '上下文',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$bookTitle · 中心 #${controller.centerCard.cardIndex}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest
                                      .withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: IconButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  icon: const Icon(Icons.close),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: cs.outlineVariant.withValues(alpha: 0.45),
                    ),
                    Expanded(
                      child: controller.isLoading && controller.cards.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(8, 10, 8, 14),
                              itemCount: controller.cards.length,
                              itemBuilder: (context, index) {
                                final card = controller.cards[index];
                                return ContextCardTile(
                                  card: card,
                                  isCenter: card.id == controller.centerCard.id,
                                  onToggleRead: () => controller.toggleRead(card),
                                  onToggleFavorite: () => controller.toggleFavorite(card),
                                  onShowContext: () => controller.focusOn(card),
                                );
                              },
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: Row(
                        children: [
                          _RangeStepper(
                            label: '前文',
                            value: settings.before,
                            onDecrease: settings.before > 1
                                ? () => controller.updateSettings(
                                      settings.copyWith(
                                        before: settings.before - 1,
                                      ),
                                    )
                                : null,
                            onIncrease: settings.before < 6
                                ? () => controller.updateSettings(
                                      settings.copyWith(
                                        before: settings.before + 1,
                                      ),
                                    )
                                : null,
                          ),
                          const SizedBox(width: 8),
                          _RangeStepper(
                            label: '后文',
                            value: settings.after,
                            onDecrease: settings.after > 1
                                ? () => controller.updateSettings(
                                      settings.copyWith(
                                        after: settings.after - 1,
                                      ),
                                    )
                                : null,
                            onIncrease: settings.after < 6
                                ? () => controller.updateSettings(
                                      settings.copyWith(
                                        after: settings.after + 1,
                                      ),
                                    )
                                : null,
                          ),
                        ],
                      ),
                    ),
                    if (controller.isLoading && controller.cards.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 14),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RangeStepper extends StatelessWidget {
  const _RangeStepper({
    required this.label,
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String label;
  final int value;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.32),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                onPressed: onDecrease,
                icon: const Icon(Icons.remove),
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                    Text(
                      '$value',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                onPressed: onIncrease,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
