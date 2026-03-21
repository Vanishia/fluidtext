import 'package:flutter/material.dart';

import '../reader/reading_order.dart';
import '../../widgets/glass.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.isImporting,
    required this.onImport,
    required this.onOpenBookshelf,
    required this.readingOrder,
    required this.onReadingOrderChanged,
    required this.themeMode,
    required this.onThemeModeChanged,
    this.contextBefore = 2,
    this.contextAfter = 2,
    this.onContextBeforeChanged,
    this.onContextAfterChanged,
  });

  final bool isImporting;
  final VoidCallback onImport;
  final VoidCallback onOpenBookshelf;
  final ReadingOrder readingOrder;
  final ValueChanged<ReadingOrder> onReadingOrderChanged;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final int contextBefore;
  final int contextAfter;
  final ValueChanged<int>? onContextBeforeChanged;
  final ValueChanged<int>? onContextAfterChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glass = cs.surface.withValues(alpha: isDark ? 0.46 : 0.62);

    return Drawer(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Glass(
            color: glass,
            borderColor: cs.outlineVariant.withValues(
              alpha: isDark ? 0.22 : 0.42,
            ),
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FluidText',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Bookshelf · Import · Reading',
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.library_books_outlined),
                  title: const Text('书架'),
                  onTap: () {
                    Navigator.of(context).pop();
                    onOpenBookshelf();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.file_upload_outlined),
                  title: const Text('导入 EPUB'),
                  enabled: !isImporting,
                  onTap: () {
                    Navigator.of(context).pop();
                    onImport();
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.format_list_numbered),
                  title: const Text('顺序阅读'),
                  trailing: readingOrder == ReadingOrder.sequential
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () {
                    onReadingOrderChanged(ReadingOrder.sequential);
                    Navigator.of(context).pop();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.shuffle),
                  title: const Text('乱序阅读'),
                  trailing: readingOrder == ReadingOrder.random
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () {
                    onReadingOrderChanged(ReadingOrder.random);
                    Navigator.of(context).pop();
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.dark_mode_outlined),
                  title: const Text('夜间模式'),
                  subtitle: Text(themeMode == ThemeMode.system ? '跟随系统' : ''),
                  value: themeMode == ThemeMode.dark,
                  onChanged: (value) {
                    onThemeModeChanged(value ? ThemeMode.dark : ThemeMode.light);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.settings_suggest_outlined),
                  title: const Text('跟随系统主题'),
                  trailing: themeMode == ThemeMode.system
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => onThemeModeChanged(ThemeMode.system),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    '上下文展开',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ),
                ListTile(
                  dense: true,
                  title: const Text('上文数量'),
                  subtitle: Slider(
                    value: contextBefore.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: '$contextBefore',
                    onChanged: onContextBeforeChanged != null
                        ? (value) => onContextBeforeChanged!(value.toInt())
                        : null,
                  ),
                  trailing: Text('$contextBefore'),
                ),
                ListTile(
                  dense: true,
                  title: const Text('下文数量'),
                  subtitle: Slider(
                    value: contextAfter.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: '$contextAfter',
                    onChanged: onContextAfterChanged != null
                        ? (value) => onContextAfterChanged!(value.toInt())
                        : null,
                  ),
                  trailing: Text('$contextAfter'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

