import 'package:flutter/material.dart';

import '../main.dart' show LumoraColors;
import 'pressable.dart';

/// 空状态组件（v2.2-E）。
///
/// 用法：
/// ```
/// EmptyState(
///   message: '还没有人被你想起',
///   hint: '定制一只属于你的精灵',
///   actionLabel: '记住第一个 ta',
///   onAction: () => _openCustom(),
/// )
/// ```
class EmptyState extends StatelessWidget {
  final String message;
  final String? hint;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.message,
    this.hint,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 长引号符号（琥珀色，呼应 Lumora 主色）
            Text(
              '「',
              style: TextStyle(
                fontSize: 36,
                color: LumoraColors.amber.withValues(alpha: 0.6),
                height: 1.0,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: LumoraColors.textSecondary,
                letterSpacing: 2,
                height: 1.7,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: LumoraColors.textMuted,
                  letterSpacing: 1,
                  height: 1.7,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 28),
              Pressable(
                onTap: onAction,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 10),
                  decoration: BoxDecoration(
                    color: LumoraColors.glass,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: LumoraColors.amber.withValues(alpha: 0.4),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    actionLabel!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: LumoraColors.amber,
                      letterSpacing: 3,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}