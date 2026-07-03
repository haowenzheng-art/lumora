import 'package:flutter/material.dart';

import '../main.dart' show LumoraColors;

/// 骨架屏（v2.2-E）。
///
/// 用 shimmer 渐变占位，提示"内容正在加载"。
/// 用法：
/// ```
/// SkeletonBox(width: 200, height: 200, borderRadius: 16)
/// ```
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
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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