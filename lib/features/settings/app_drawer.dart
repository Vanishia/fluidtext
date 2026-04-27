import 'package:flutter/material.dart';

import '../../widgets/glass.dart';
import '../../widgets/shelf_glyph.dart';
import '../context/context_settings.dart';
import '../reader/reading_order.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.onOpenBookshelf,
    required this.readingOrder,
    required this.onReadingOrderChanged,
    required this.themeMode,
    required this.onThemeModeChanged,
    this.showUnreadOnly = false,
    this.onShowUnreadOnlyChanged,
    this.onOpenReadList,
    this.onOpenFavoriteList,
    this.onOpenReaderBackgroundSettings,
    this.contextBefore,
    this.contextAfter,
    this.onContextBeforeChanged,
    this.onContextAfterChanged,
  });

  final VoidCallback onOpenBookshelf;
  final ReadingOrder readingOrder;
  final ValueChanged<ReadingOrder> onReadingOrderChanged;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final bool showUnreadOnly;
  final ValueChanged<bool>? onShowUnreadOnlyChanged;
  final VoidCallback? onOpenReadList;
  final VoidCallback? onOpenFavoriteList;
  final VoidCallback? onOpenReaderBackgroundSettings;
  final int? contextBefore;
  final int? contextAfter;
  final ValueChanged<int>? onContextBeforeChanged;
  final ValueChanged<int>? onContextAfterChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glass = cs.surface.withValues(alpha: isDark ? 0.48 : 0.68);
    final hasContextSettings =
        contextBefore != null &&
        contextAfter != null &&
        onContextBeforeChanged != null &&
        onContextAfterChanged != null;

    return Drawer(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Glass(
            color: glass,
            borderColor: cs.outlineVariant.withValues(
              alpha: isDark ? 0.18 : 0.34,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 12, 8),
                  child: Row(
                    children: [
                      Text(
                        'FluidText',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const Spacer(),
                      _QuietIconButton(
                        tooltip: _themeTooltip(themeMode),
                        onTap: () =>
                            onThemeModeChanged(_nextThemeMode(themeMode)),
                        child: Icon(
                          _themeIcon(themeMode),
                          size: 20,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ShelfButton(onTap: onOpenBookshelf),
                        const SizedBox(height: 18),
                        SegmentedButton<ReadingOrder>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment<ReadingOrder>(
                              value: ReadingOrder.sequential,
                              icon: Icon(Icons.format_list_numbered_rounded),
                              label: Text('顺序阅读'),
                            ),
                            ButtonSegment<ReadingOrder>(
                              value: ReadingOrder.random,
                              icon: Icon(Icons.shuffle_rounded),
                              label: Text('乱序阅读'),
                            ),
                          ],
                          selected: {readingOrder},
                          onSelectionChanged: (selection) {
                            onReadingOrderChanged(selection.first);
                          },
                        ),
                        if (onShowUnreadOnlyChanged != null) ...[
                          const SizedBox(height: 12),
                          SwitchListTile.adaptive(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 2,
                            ),
                            title: const Text('过滤已读'),
                            value: showUnreadOnly,
                            onChanged: onShowUnreadOnlyChanged,
                          ),
                        ],
                        if (hasContextSettings) ...[
                          const SizedBox(height: 28),
                          _DrawerSlider(
                            label: '上文数量',
                            value: contextBefore!,
                            onChanged: onContextBeforeChanged!,
                          ),
                          const SizedBox(height: 12),
                          _DrawerSlider(
                            label: '下文数量',
                            value: contextAfter!,
                            onChanged: onContextAfterChanged!,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                  child: Row(
                    children: [
                      _QuietIconButton(
                        tooltip: '阅读背景',
                        onTap: _popThen(
                          context,
                          onOpenReaderBackgroundSettings,
                        ),
                        child: Icon(
                          Icons.settings_rounded,
                          size: 18,
                          color: onOpenReaderBackgroundSettings == null
                              ? cs.onSurface.withValues(alpha: 0.32)
                              : cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _QuietIconButton(
                        tooltip: '收藏',
                        onTap: _popThen(context, onOpenFavoriteList),
                        child: Icon(
                          Icons.favorite_border_rounded,
                          size: 18,
                          color: onOpenFavoriteList == null
                              ? cs.onSurface.withValues(alpha: 0.32)
                              : cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _QuietIconButton(
                        tooltip: '已读',
                        onTap: _popThen(context, onOpenReadList),
                        child: Icon(
                          Icons.done_all_rounded,
                          size: 18,
                          color: onOpenReadList == null
                              ? cs.onSurface.withValues(alpha: 0.32)
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

VoidCallback? _popThen(BuildContext context, VoidCallback? callback) {
  if (callback == null) return null;
  return () {
    Navigator.of(context).pop();
    callback();
  };
}

class _ShelfButton extends StatelessWidget {
  const _ShelfButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            ShelfGlyph(size: 22, color: cs.onSurface),
            const SizedBox(width: 10),
            Text(
              '书架',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerSlider extends StatelessWidget {
  const _DrawerSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '$value',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            activeTrackColor: cs.onSurface.withValues(alpha: 0.72),
            inactiveTrackColor: cs.outlineVariant.withValues(alpha: 0.55),
            thumbColor: cs.onSurface,
            overlayShape: SliderComponentShape.noOverlay,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 5,
              pressedElevation: 0,
            ),
          ),
          child: Slider(
            padding: const EdgeInsets.symmetric(horizontal: 0),
            value: value.toDouble(),
            min: ContextSettings.minCount.toDouble(),
            max: ContextSettings.maxCount.toDouble(),
            divisions: ContextSettings.maxCount - ContextSettings.minCount,
            label: '$value',
            onChanged: (next) => onChanged(next.toInt()),
          ),
        ),
      ],
    );
  }
}

class _QuietIconButton extends StatelessWidget {
  const _QuietIconButton({required this.child, this.tooltip, this.onTap});

  final Widget child;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Ink(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(
                alpha: onTap == null ? 0.28 : 0.58,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

ThemeMode _nextThemeMode(ThemeMode current) {
  switch (current) {
    case ThemeMode.light:
      return ThemeMode.dark;
    case ThemeMode.dark:
      return ThemeMode.system;
    case ThemeMode.system:
      return ThemeMode.light;
  }
}

String _themeTooltip(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return '日间';
    case ThemeMode.dark:
      return '夜间';
    case ThemeMode.system:
      return '系统';
  }
}

IconData _themeIcon(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return Icons.light_mode_outlined;
    case ThemeMode.dark:
      return Icons.dark_mode_outlined;
    case ThemeMode.system:
      return Icons.brightness_auto_outlined;
  }
}
