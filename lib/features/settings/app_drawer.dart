import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/app_logger.dart';
import '../../widgets/glass.dart';
import '../../widgets/shelf_glyph.dart';
import '../context/context_settings.dart';
import '../reader/reading_order.dart';
import 'update_notice.dart';

/// 应用菜单面板：默认是贴边常驻侧边栏（桌面端）；[floating] 为 true
/// 时是悬浮毛玻璃抽屉（移动端 Scaffold.drawer 使用，手势不抢滚动）。
class AppSidePanel extends StatelessWidget {
  const AppSidePanel({
    super.key,
    required this.onOpenBookshelf,
    this.onOpenSearch,
    required this.readingOrder,
    required this.onReadingOrderChanged,
    required this.themeMode,
    required this.onThemeModeChanged,
    this.showUnreadOnly = false,
    this.onShowUnreadOnlyChanged,
    this.onOpenReadList,
    this.onOpenFavoriteList,
    this.onOpenReaderBackgroundSettings,
    this.onOpenReadingAnalysis,
    this.contextBefore,
    this.contextAfter,
    this.onContextBeforeChanged,
    this.onContextAfterChanged,
    this.onRequestClose,
    this.floating = false,
  });

  final VoidCallback onOpenBookshelf;

  /// 全文搜索入口；为 null（Isar 回滚路径）时不显示搜索按钮。
  final VoidCallback? onOpenSearch;
  final ReadingOrder readingOrder;
  final ValueChanged<ReadingOrder> onReadingOrderChanged;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final bool showUnreadOnly;
  final ValueChanged<bool>? onShowUnreadOnlyChanged;
  final VoidCallback? onOpenReadList;
  final VoidCallback? onOpenFavoriteList;
  final VoidCallback? onOpenReaderBackgroundSettings;
  final VoidCallback? onOpenReadingAnalysis;
  final int? contextBefore;
  final int? contextAfter;
  final ValueChanged<int>? onContextBeforeChanged;
  final ValueChanged<int>? onContextAfterChanged;

  /// 面板内的导航动作触发前调用，用于收起面板（贴边模式）。
  final VoidCallback? onRequestClose;

  /// true 时渲染为悬浮毛玻璃 [Drawer]（移动端），导航动作前自动 pop 抽屉。
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasContextSettings =
        contextBefore != null &&
        contextAfter != null &&
        onContextBeforeChanged != null &&
        onContextAfterChanged != null;
    final close = floating
        ? () => Navigator.of(context).pop()
        : (onRequestClose ?? () {});
    // 移动端抽屉是一层路由，打开子页面前必须 pop 抽屉；
    // 桌面贴边面板只有「书架」按钮需要收起面板，其余按钮保持展开。
    final closeDrawer = floating ? close : null;

    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 12, 8),
          child: Row(
            children: [
              const _RepoLinkTitle(),
              const Spacer(),
              _QuietIconButton(
                tooltip: _themeTooltip(themeMode),
                onTap: () => onThemeModeChanged(_nextThemeMode(themeMode)),
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
                Row(
                  children: [
                    Expanded(
                      child: _ShelfButton(
                        onTap: onOpenBookshelf,
                        onClose: close,
                      ),
                    ),
                    if (onOpenSearch != null) ...[
                      const SizedBox(width: 8),
                      _QuietIconButton(
                        tooltip: '搜索',
                        onTap: _closeThen(onOpenSearch, closeDrawer),
                        child: Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                    title: const Text('过滤已读'),
                    value: showUnreadOnly,
                    onChanged: onShowUnreadOnlyChanged,
                  ),
                ],
                const SizedBox(height: 12),
                const UpdateNoticeBlock(),
                if (hasContextSettings) ...[
                  const SizedBox(height: 28),
                  _ContextCountStepper(
                    label: '上文数量',
                    value: contextBefore!,
                    onChanged: onContextBeforeChanged!,
                  ),
                  const SizedBox(height: 12),
                  _ContextCountStepper(
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
                tooltip: '外观设置',
                onTap: _closeThen(onOpenReaderBackgroundSettings, closeDrawer),
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
                tooltip: '阅读分析',
                onTap: _closeThen(onOpenReadingAnalysis, closeDrawer),
                child: Icon(
                  Icons.insights_rounded,
                  size: 18,
                  color: onOpenReadingAnalysis == null
                      ? cs.onSurface.withValues(alpha: 0.32)
                      : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              _QuietIconButton(
                tooltip: '收藏',
                onTap: _closeThen(onOpenFavoriteList, closeDrawer),
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
                onTap: _closeThen(onOpenReadList, closeDrawer),
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
    );

    if (floating) {
      return Drawer(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Glass(
              color: cs.surface.withValues(alpha: isDark ? 0.48 : 0.68),
              borderColor: cs.outlineVariant.withValues(
                alpha: isDark ? 0.18 : 0.34,
              ),
              child: content,
            ),
          ),
        ),
      );
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: isDark ? 0.48 : 0.68),
            border: Border(
              right: BorderSide(
                color: cs.outlineVariant.withValues(
                  alpha: isDark ? 0.28 : 0.55,
                ),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.07),
                blurRadius: 24,
                offset: const Offset(6, 0),
              ),
            ],
          ),
          child: SafeArea(child: content),
        ),
      ),
    );
  }

  VoidCallback? _closeThen(VoidCallback? callback, VoidCallback? close) {
    if (callback == null) return null;
    if (close == null) return callback;
    return () {
      close();
      callback();
    };
  }
}

/// 侧边栏标题：样式与普通文本完全一致；10 秒内连点两次弹出提示，
/// 第三次点击打开项目仓库页面。
class _RepoLinkTitle extends StatefulWidget {
  const _RepoLinkTitle();

  static final Uri _repoUrl = Uri.parse(
    'https://github.com/Vanishia/fluidtext',
  );

  @override
  State<_RepoLinkTitle> createState() => _RepoLinkTitleState();
}

class _RepoLinkTitleState extends State<_RepoLinkTitle> {
  static const Duration _window = Duration(seconds: 10);

  DateTime? _windowStart;
  var _tapCount = 0;

  void _onTap() {
    final now = DateTime.now();
    if (_windowStart == null || now.difference(_windowStart!) > _window) {
      _windowStart = now;
      _tapCount = 0;
    }
    _tapCount++;
    if (_tapCount == 2) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('再点击一次将打开项目仓库页面'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(milliseconds: 1200),
            margin: const EdgeInsets.fromLTRB(24, 0, 24, 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
    } else if (_tapCount >= 3) {
      _tapCount = 0;
      _windowStart = null;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _openRepo();
    }
  }

  Future<void> _openRepo() async {
    try {
      final launched = await launchUrl(
        _RepoLinkTitle._repoUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        AppLogger.instance.warning('AppSidePanel', '无法打开项目仓库链接');
      }
    } catch (error, stackTrace) {
      AppLogger.instance.warning(
        'AppSidePanel',
        '打开项目仓库链接失败',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: Text(
        'FluidText',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _ShelfButton extends StatelessWidget {
  const _ShelfButton({required this.onTap, this.onClose});

  final VoidCallback onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        onClose?.call();
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

class _ContextCountStepper extends StatelessWidget {
  const _ContextCountStepper({
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
    final canDecrease = value > ContextSettings.minCount;
    final canIncrease = value < ContextSettings.maxCount;

    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Spacer(),
        DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StepperButton(
                icon: Icons.remove_rounded,
                tooltip: '减少',
                onTap: canDecrease ? () => onChanged(value - 1) : null,
              ),
              SizedBox(
                width: 28,
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              _StepperButton(
                icon: Icons.add_rounded,
                tooltip: '增加',
                onTap: canIncrease ? () => onChanged(value + 1) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.tooltip, this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(
            icon,
            size: 16,
            color: onTap == null
                ? cs.onSurface.withValues(alpha: 0.24)
                : cs.onSurface,
          ),
        ),
      ),
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
