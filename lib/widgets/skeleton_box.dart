import 'package:flutter/material.dart';

import '../main.dart' show LumoraColors;
import '../preferences.dart';

/// 骨架屏（v2.2-E，v2.3-B 加偏好开关）。
///
/// 用 shimmer 渐变占位，提示"内容正在加载"。
/// 用法：
/// ```
/// SkeletonBox(width: 200, height: 200, borderRadius: 16)
/// ```
///
/// v2.3-B：用户关掉"骨架屏"偏好时退化为空 SizedBox（保留原宽高，
/// 布局不变——只是不再有 shimmer 动画）。
///
/// 设计：手写 AnimatedBuilder 而非用 shimmer 包——避免新依赖。
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double? height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 8,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    // v2.3-B：关掉骨架屏时干脆不启动 shimmer 动画，节省 ticker
    if (!PreferencesService.I.disableSkeleton.value) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // v2.3-B：用户关掉骨架屏偏好 → 退化为纯占位（保持原宽高，布局不变）
    if (PreferencesService.I.disableSkeleton.value) {
      return SizedBox(width: widget.width, height: widget.height);
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        // shimmer 位置：0.0 → 1.0 横向滑动
        final t = _ctrl.value;
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-1.0 + t * 2, 0),
                end: Alignment(-0.5 + t * 2, 0),
                colors: [
                  LumoraColors.glass,
                  LumoraColors.amber.withValues(alpha: 0.06),
                  LumoraColors.glass,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        );
      },
    );
  }
}