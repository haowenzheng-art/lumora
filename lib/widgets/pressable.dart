import 'package:flutter/material.dart';

/// 通用按下反馈组件（v2.2-B）。
///
/// 设计选择：用 AnimatedScale 而非 InkWell：
/// - InkWell 水波纹是 Material 风格，跟 Lumora 暗色夜色调性匹配度一般
/// - SplashPage 已有 _BackgroundGradient + 60 个 _FloatingParticle，
///   水波纹会跟粒子视觉冲突
/// - scale 反馈更"现代"，按下有"实体感"
///
/// 用法：
/// ```
/// Pressable(
///   onTap: () => doSomething(),
///   child: MyWidget(),
/// )
/// ```
///
/// onTap 为 null 时不响应触摸（disabled 状态），调用方负责视觉降级。
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final Duration duration;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.96,
    this.duration = const Duration(milliseconds: 150),
  });

  bool get enabled => onTap != null;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (!widget.enabled) return;
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.enabled ? widget.onTap : null,
      onLongPress: widget.enabled ? widget.onLongPress : null,
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: widget.duration,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}