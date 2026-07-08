import 'package:flutter/material.dart';

import 'widgets/pressable.dart';
import 'preferences.dart';
import 'main.dart' show LumoraColors;

/// 用户偏好设置页 v2.3-B
///
/// 设计要点：
///   - 4 个开关对应宪法语境下用户可能想关掉的"产品感"细节
///   - 不做复杂表单，只 4 个 SwitchListTile，调一次 PreferencesService 持久化
///   - 实时生效：ValueNotifier 触发订阅者重建（SpiritScenePage / ChatPage / SkeletonBox）
///
/// 风格延续 Lumora 暗色调性（与 SplashPage / ChatPage 一致）。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = PreferencesService.I;
    return Scaffold(
      body: Stack(
        children: [
          const _SettingsBackground(),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(context),
                const SizedBox(height: 24),
                const _SettingsIntro(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                    children: [
                      _PrefTile(
                        title: '破冰淡入',
                        subtitle: '立绘从透明渐变显形的过程',
                        valueListenable: prefs.disableEntranceAnim,
                        onChanged: prefs.setDisableEntranceAnim,
                      ),
                      _PrefTile(
                        title: '自动进入对话',
                        subtitle: '立绘显形后自动跳到对话页（关闭后需手动点击）',
                        valueListenable: prefs.disableAutoEnterChat,
                        onChanged: prefs.setDisableAutoEnterChat,
                      ),
                      _PrefTile(
                        title: '打字机效果',
                        subtitle: '精灵消息逐字出现并闪烁光标',
                        valueListenable: prefs.disableTypewriter,
                        onChanged: prefs.setDisableTypewriter,
                      ),
                      _PrefTile(
                        title: '骨架屏',
                        subtitle: '生成等待时的流光占位',
                        valueListenable: prefs.disableSkeleton,
                        onChanged: prefs.setDisableSkeleton,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Pressable(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: LumoraColors.glass,
                border: Border.all(
                  color: LumoraColors.glassBorder,
                  width: 0.5,
                ),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: LumoraColors.textPrimary,
                size: 18,
              ),
            ),
          ),
          const Expanded(
            child: Center(
              child: Text(
                '偏好设置',
                style: TextStyle(
                  fontSize: 14,
                  color: LumoraColors.textPrimary,
                  letterSpacing: 6,
                ),
              ),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

/// 单条偏好开关
///
/// 用 ValueListenableBuilder 订阅 prefs.disableXxx.value 的变化，
/// 改完立刻反映，不用 setState 包整个页。
class _PrefTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final ValueListenable<bool> valueListenable;
  final Future<void> Function(bool) onChanged;

  const _PrefTile({
    required this.title,
    required this.subtitle,
    required this.valueListenable,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ValueListenableBuilder<bool>(
        valueListenable: valueListenable,
        builder: (_, v, __) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: LumoraColors.glass,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: LumoraColors.glassBorder,
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        color: LumoraColors.textPrimary,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: LumoraColors.textMuted,
                        letterSpacing: 1,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch(
                value: v,
                onChanged: (nv) => onChanged(nv),
                activeColor: LumoraColors.amber,
                inactiveTrackColor: LumoraColors.glassBorder,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 设置页顶部说明：宪法视角下的"为什么有这些开关"
class _SettingsIntro extends StatelessWidget {
  const _SettingsIntro();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Text(
        '这里是 Lumora 的几个产品感细节。\n关掉任何一个都不会影响核心功能，\n只是少一些"在活着"的感觉。',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          color: LumoraColors.textSecondary,
          height: 1.8,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

/// 设置页背景：复用 SplashPage 的渐变 + 粒子调性（让"设置"也像 Lumora 的页）
class _SettingsBackground extends StatelessWidget {
  const _SettingsBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.6),
              radius: 1.4,
              colors: [
                Color(0xFF1A2138),
                Color(0xFF0E1424),
                Color(0xFF050810),
              ],
            ),
          ),
        ),
        // 顶部一点柔光呼应 SplashPage 的 Lumora logo 氛围
        Positioned(
          top: -120,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              height: 240,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.6,
                  colors: [
                    const Color(0xFFE8B96A).withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}