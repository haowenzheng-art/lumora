import 'package:flutter/material.dart';

/// 淡入 + 微缩放路由（v2.2-C）
///
/// 替代平台默认的左滑切换，符合 Lumora"沉静"调性。
/// 设计原则：
/// - 只做淡入 + 0.97→1.0 缩放，不做方向滑动（避免"工具感"）
/// - 进场 250ms / 退场 200ms（退场略快，避免用户觉得"拖"）
/// - easeOutCubic 曲线，开头快、收尾柔
///
/// 用法：
/// ```
/// Navigator.push(context, FadeScaleRoute(builder: (_) => MyPage()));
/// ```
class FadeScaleRoute<T> extends PageRouteBuilder<T> {
  FadeScaleRoute({required WidgetBuilder builder})
      : super(
          transitionDuration: const Duration(milliseconds: 250),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder:
              (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
                child: child,
              ),
            );
          },
        );
}