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

/// 推移式布局：打开侧边栏时把整个主界面向右推，面板与主界面
/// 连在一起同步滑动，无遮罩。用于窄屏（手机竖屏、极窄窗口）。
/// 打开后面板或主界面上向左快速滑动即可收起。
class SlideSidePanel extends StatelessWidget {
  const SlideSidePanel({
    super.key,
    required this.visible,
    required this.onClose,
    required this.panel,
    required this.child,
  });

  final bool visible;
  final VoidCallback onClose;
  final Widget panel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        if (visible && (details.primaryVelocity ?? 0) < -240) {
          onClose();
        }
      },
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final fraction = width > 0
                ? (kSidePanelWidth / width).clamp(0.0, 1.0)
                : 0.0;
            return Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: kSidePanelWidth,
                  child: panel,
                ),
                Positioned.fill(
                  child: AnimatedSlide(
                    duration: _kPanelAnimationDuration,
                    curve: Curves.easeOutCubic,
                    offset: Offset(visible ? fraction : 0, 0),
                    child: child,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
