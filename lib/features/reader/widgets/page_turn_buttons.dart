import 'package:flutter/material.dart';

/// 阅读区右侧的翻页按钮：滚动时淡入，停止滚动后由外部收起。
/// 点击按 90% 视口高度向上/向下翻页。
class PageTurnButtons extends StatelessWidget {
  const PageTurnButtons({
    super.key,
    required this.visible,
    required this.onPageUp,
    required this.onPageDown,
  });

  final bool visible;
  final VoidCallback onPageUp;
  final VoidCallback onPageDown;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        opacity: visible ? 1 : 0,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          offset: visible ? Offset.zero : const Offset(0.25, 0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: isDark ? 0.72 : 0.88),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: cs.outlineVariant.withValues(
                  alpha: isDark ? 0.3 : 0.55,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PageTurnButton(
                  icon: Icons.keyboard_arrow_up_rounded,
                  tooltip: '向上翻页',
                  onTap: onPageUp,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                _PageTurnButton(
                  icon: Icons.keyboard_arrow_down_rounded,
                  tooltip: '向下翻页',
                  onTap: onPageDown,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PageTurnButton extends StatelessWidget {
  const _PageTurnButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 22, color: cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
