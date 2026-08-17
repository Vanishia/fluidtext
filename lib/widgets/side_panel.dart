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
///
/// 手势全程跟手：关闭时从左边缘向右拖、打开时在任意位置向左拖，
/// 松手后按滑动速度和当前位置吸到全开或全关。
class SlideSidePanel extends StatefulWidget {
  const SlideSidePanel({
    super.key,
    required this.visible,
    required this.onVisibilityChanged,
    required this.panel,
    required this.child,
  });

  /// 目标开合状态；手势拖动改变状态后通过 [onVisibilityChanged] 回报。
  final bool visible;
  final ValueChanged<bool> onVisibilityChanged;
  final Widget panel;
  final Widget child;

  @override
  State<SlideSidePanel> createState() => _SlideSidePanelState();
}

class _SlideSidePanelState extends State<SlideSidePanel>
    with SingleTickerProviderStateMixin {
  static const _edgeDragWidth = 28.0;
  static const _flingVelocity = 300.0;

  late final AnimationController _controller;
  late bool _visible = widget.visible;
  var _dragActive = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      value: widget.visible ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(SlideSidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != _visible) {
      _settleTo(widget.visible);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _settleTo(bool open, {double velocity = 0}) {
    _visible = open;
    final target = open ? 1.0 : 0.0;
    if ((_controller.value - target).abs() < 0.001) {
      _controller.value = target;
      return;
    }
    if (velocity.abs() > 50) {
      // 保留松手时的惯性。
      _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } else {
      _controller.animateTo(
        target,
        duration: _kPanelAnimationDuration,
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _handleDragStart(DragStartDetails details) {
    // 关闭时只响应左边缘起拖；打开后任意位置都可以拖。
    _dragActive =
        _controller.value > 0 || details.localPosition.dx <= _edgeDragWidth;
    if (_dragActive) {
      _controller.stop();
    }
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_dragActive) return;
    final delta = details.primaryDelta ?? 0;
    _controller.value = (_controller.value + delta / kSidePanelWidth).clamp(
      0.0,
      1.0,
    );
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_dragActive) return;
    _dragActive = false;
    final velocity = details.primaryVelocity ?? 0;
    final open = velocity.abs() > _flingVelocity
        ? velocity > 0
        : _controller.value > 0.5;
    widget.onVisibilityChanged(open);
    _settleTo(open, velocity: velocity);
  }

  void _handleDragCancel() {
    if (!_dragActive) return;
    _dragActive = false;
    final open = _controller.value > 0.5;
    widget.onVisibilityChanged(open);
    _settleTo(open);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _handleDragStart,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      onHorizontalDragCancel: _handleDragCancel,
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                // 面板与主界面是一块整体画布，一起左右平移：
                // 关闭时画布左移一个面板宽（面板在屏外），打开时归位。
                return Transform.translate(
                  offset: Offset((_controller.value - 1) * kSidePanelWidth, 0),
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: width + kSidePanelWidth,
                    maxWidth: width + kSidePanelWidth,
                    minHeight: height,
                    maxHeight: height,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: kSidePanelWidth, child: widget.panel),
                        SizedBox(
                          width: width,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ?child,
                              // 打开后点击右侧内容区收起侧边栏。
                              IgnorePointer(
                                ignoring: _controller.value < 0.5,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    widget.onVisibilityChanged(false);
                                    _settleTo(false);
                                  },
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              child: widget.child,
            );
          },
        ),
      ),
    );
  }
}
