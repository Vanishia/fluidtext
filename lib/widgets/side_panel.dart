import 'package:flutter/material.dart';

/// 贴边侧边栏的固定宽度。
const double kSidePanelWidth = 304;

/// 可用宽度达到该值时侧边栏使用推动布局（挤压阅读区），
/// 否则使用覆盖布局（浮在阅读区上方）。
const double kSidePanelPushBreakpoint = 600;

/// 宽高比达到该值（横 3 竖 2）时默认展开侧边栏。
const double kSidePanelDefaultOpenAspectRatio = 1.5;

const Duration _kPanelAnimationDuration = Duration(milliseconds: 240);

/// 推动式贴边面板：宽度动画展开/收起，内容保持固定宽度并被裁剪，
/// 不会因宽度变化而重排内部布局。
class PushSidePanel extends StatelessWidget {
  const PushSidePanel({super.key, required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: _kPanelAnimationDuration,
      curve: Curves.easeOutCubic,
      width: visible ? kSidePanelWidth : 0,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: kSidePanelWidth,
          maxWidth: kSidePanelWidth,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            opacity: visible ? 1 : 0,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 覆盖式贴边面板：面板滑入滑出，背景遮罩淡入淡出。
/// 收起后面板会从树中移除，不会常驻 BackdropFilter 的开销。
///
/// 需要放在 [Stack] 内使用（自身会填满父级）。
class OverlaySidePanel extends StatelessWidget {
  const OverlaySidePanel({
    super.key,
    required this.visible,
    required this.onClose,
    required this.child,
  });

  final bool visible;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !visible,
            child: AnimatedOpacity(
              duration: _kPanelAnimationDuration,
              curve: Curves.easeOut,
              opacity: visible ? 1 : 0,
              child: GestureDetector(
                onTap: onClose,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.18),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: AnimatedSwitcher(
            duration: _kPanelAnimationDuration,
            transitionBuilder: (child, animation) {
              return SlideTransition(
                position:
                    Tween<Offset>(
                      begin: const Offset(-1, 0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                child: child,
              );
            },
            child: visible
                ? SizedBox(
                    key: const ValueKey('side-panel'),
                    width: kSidePanelWidth,
                    height: double.infinity,
                    child: child,
                  )
                : const SizedBox.shrink(key: ValueKey('side-panel-empty')),
          ),
        ),
      ],
    );
  }
}
