import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../widgets/glass.dart';
import 'context_controller.dart';
import 'context_settings.dart';
import 'widgets/context_card_tile.dart';

class ContextSheet extends StatefulWidget {
  const ContextSheet({
    super.key,
    required this.controller,
    required this.bookTitle,
  });

  final ContextController controller;
  final String bookTitle;

  @override
  State<ContextSheet> createState() => _ContextSheetState();
}

class _ContextSheetState extends State<ContextSheet> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _cardKeys = <int, GlobalKey>{};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _ensureCenterVisible() {
    if (!mounted) return;
    final key = _cardKeys[widget.controller.centerCard.id];
    final keyContext = key?.currentContext;
    if (keyContext == null) return;

    Scrollable.ensureVisible(
      keyContext,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: 0.24,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  GlobalKey _keyFor(int cardId) {
    return _cardKeys.putIfAbsent(cardId, GlobalKey.new);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mediaQuery = MediaQuery.of(context);
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.zero,
        child: Glass(
          color: cs.surface.withValues(alpha: isDark ? 0.97 : 0.985),
          borderColor: cs.outlineVariant.withValues(alpha: 0.22),
          // 桌面端弹窗贴着屏幕底边，下面两个角用直角（弹出菜单样式），
          // 上面保留圆角。
          borderRadius: isDesktop
              ? const BorderRadius.vertical(top: Radius.circular(20))
              : null,
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final settings = widget.controller.settings;
              return SizedBox(
                width: double.infinity,
                height: mediaQuery.size.height * 0.86,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 8, 5),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '上下文',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                height: 1.05,
                                              ),
                                        ),
                                        const SizedBox(width: 4),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          constraints:
                                              const BoxConstraints.tightFor(
                                                width: 28,
                                                height: 28,
                                              ),
                                          padding: EdgeInsets.zero,
                                          tooltip: '定位当前卡片',
                                          onPressed: _ensureCenterVisible,
                                          iconSize: 17,
                                          color: cs.onSurfaceVariant,
                                          icon: const Icon(Icons.my_location),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${widget.bookTitle} · 中心 #${widget.controller.centerCard.cardIndex}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                            height: 1.05,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest.withValues(
                                    alpha: 0.55,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: IconButton(
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 32,
                                    height: 32,
                                  ),
                                  padding: EdgeInsets.zero,
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
                      child:
                          widget.controller.isLoading &&
                              widget.controller.cards.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          : SingleChildScrollView(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
                              child: Column(
                                children: [
                                  for (final card in widget.controller.cards)
                                    KeyedSubtree(
                                      key: _keyFor(card.id),
                                      child: ContextCardTile(
                                        card: card,
                                        repository:
                                            widget.controller.repository,
                                        isCenter:
                                            card.id ==
                                            widget.controller.centerCard.id,
                                        onToggleRead: () =>
                                            widget.controller.toggleRead(card),
                                        onToggleFavorite: () => widget
                                            .controller
                                            .toggleFavorite(card),
                                        onShowContext: () =>
                                            widget.controller.focusOn(card),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                    ),
                    Padding(
                      padding: isDesktop
                          ? const EdgeInsets.fromLTRB(16, 6, 16, 16)
                          : const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: Row(
                        children: [
                          _RangeStepper(
                            label: '前文',
                            value: settings.before,
                            compact: isDesktop,
                            onDecrease:
                                settings.before > ContextSettings.minCount
                                ? () => widget.controller.updateSettings(
                                    settings.copyWith(
                                      before: settings.before - 1,
                                    ),
                                  )
                                : null,
                            onIncrease:
                                settings.before < ContextSettings.maxCount
                                ? () => widget.controller.updateSettings(
                                    settings.copyWith(
                                      before: settings.before + 1,
                                    ),
                                  )
                                : null,
                          ),
                          SizedBox(width: isDesktop ? 16 : 8),
                          _RangeStepper(
                            label: '后文',
                            value: settings.after,
                            compact: isDesktop,
                            onDecrease:
                                settings.after > ContextSettings.minCount
                                ? () => widget.controller.updateSettings(
                                    settings.copyWith(
                                      after: settings.after - 1,
                                    ),
                                  )
                                : null,
                            onIncrease:
                                settings.after < ContextSettings.maxCount
                                ? () => widget.controller.updateSettings(
                                    settings.copyWith(
                                      after: settings.after + 1,
                                    ),
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ),
                    if (widget.controller.isLoading &&
                        widget.controller.cards.isNotEmpty)
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
    this.compact = false,
  });

  final String label;
  final int value;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  /// 桌面端用：样式不变，整体缩小一点。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 桌面端紧凑模式不用 IconButton（默认带 8px 内边距和视觉密度换算，
    // 图标容易被挤偏），改用固定尺寸、图标严格居中的小按钮。
    Widget stepperButton(IconData icon, VoidCallback? onPressed) {
      if (!compact) {
        return IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          constraints: const BoxConstraints.tightFor(width: 30, height: 30),
          onPressed: onPressed,
          icon: Icon(icon),
        );
      }
      return _CompactStepperButton(icon: icon, onTap: onPressed);
    }

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
          padding: EdgeInsets.symmetric(
            horizontal: 4,
            vertical: compact ? 1 : 4,
          ),
          child: Row(
            children: [
              stepperButton(Icons.remove, onDecrease),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: compact ? 1.05 : null,
                      ),
                    ),
                    Text(
                      '$value',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: compact ? 1.1 : null,
                      ),
                    ),
                  ],
                ),
              ),
              stepperButton(Icons.add, onIncrease),
            ],
          ),
        ),
      ),
    );
  }
}

/// 紧凑步进器（桌面端）里的小按钮：24×24 固定尺寸，图标严格居中。
class _CompactStepperButton extends StatelessWidget {
  const _CompactStepperButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkResponse(
      onTap: onTap,
      radius: 18,
      child: SizedBox(
        width: 24,
        height: 24,
        child: Center(
          child: Icon(
            icon,
            size: 15,
            color: onTap == null
                ? cs.onSurface.withValues(alpha: 0.38)
                : null,
          ),
        ),
      ),
    );
  }
}
