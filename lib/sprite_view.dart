import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import 'sprite_parts.dart';

/// 灵动精灵视图（v0.3 - 图层合成版）
///
/// 行为：
/// - 鼠标进入：呼吸加快 + halo 渐强 + 头部 perspective tilt 跟随鼠标
/// - 鼠标离开 8s 后 idle drift：随机看一下别处
/// - 点击：pulse 前倾 + halo 闪
/// - 眨眼：间隔 2800ms + rand(0~2200ms)，闭/睁各 70ms，10% 双眨眼
///
/// 渲染：
/// - 若 [manifest] 不为 null → Stack(base.png + 透明 eyes.png)，眨眼时 eyes 层 scaleY 收缩
/// - 否则降级为单张原图
class SpiritView extends StatefulWidget {
  final String spritePath;
  final PartsManifest? manifest;
  final double width;
  final double height;
  final BorderRadius borderRadius;
  final Offset? pointer; // 归一化 [-1,1]
  final int pulseToken;

  /// v2.3 强制眨眼触发器：父组件在想要 SpiritView 立即眨一次眼时
  /// 把这个值 +1（自增 token 风格，跟 pulseToken 一致）。
  /// SpiritView 会在 didUpdateWidget 检测到变大时立即 _playBlink() 一次，
  /// 并重置下一次自然眨眼的计时——这正是"刚醒过来"破冰仪式需要的瞬间。
  final int forceBlinkToken;

  final VoidCallback? onTap;

  const SpiritView({
    super.key,
    required this.spritePath,
    this.manifest,
    required this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.pointer,
    this.pulseToken = 0,
    this.forceBlinkToken = 0,
    this.onTap,
  });

  @override
  State<SpiritView> createState() => _SpiritViewState();
}

class _SpiritViewState extends State<SpiritView>
    with TickerProviderStateMixin {
  late final Ticker _ticker;
  late final AnimationController _breathe;
  late final AnimationController _pulse;

  // tilt 平滑
  double _tiltX = 0, _tiltY = 0;
  double _targetTiltX = 0, _targetTiltY = 0;
  double _halo = 0;

  // 眨眼
  double _blinkY = 1.0; // eyes 层 scaleY
  Timer? _blinkScheduler;
  final _rng = math.Random();

  // idle drift
  Timer? _idleTimer;
  bool _drifting = false;

  static const double _maxTilt = 0.052;
  static const double _lerpFactor = 0.08;
  static const Duration _breatheCalm = Duration(milliseconds: 5500);
  static const Duration _breatheAlert = Duration(milliseconds: 4200);

  @override
  void initState() {
    super.initState();
    _breathe = AnimationController(vsync: this, duration: _breatheCalm)
      ..repeat(reverse: true);
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 520));
    _ticker = createTicker(_onTick)..start();
    _scheduleNextDrift();
    if (widget.manifest != null) {
      _scheduleNextBlink();
    }
  }

  @override
  void didUpdateWidget(covariant SpiritView old) {
    super.didUpdateWidget(old);
    if (widget.pulseToken != old.pulseToken && widget.pulseToken > 0) {
      _pulse.forward(from: 0);
    }
    // v2.3 强制眨眼：父组件（通常是 SpiritScenePage 破冰仪式）传一个
    // 更大的 forceBlinkToken 进来 → 立即眨一次，并把下一次自然眨眼
    // 计时器从"现在"重新算起，避免紧接着又眨一次显得仓促。
    if (widget.forceBlinkToken != old.forceBlinkToken &&
        widget.forceBlinkToken > old.forceBlinkToken &&
        widget.manifest != null) {
      _playBlink();
      _scheduleNextBlink();
    }
    final hadPointer = old.pointer != null;
    final hasPointer = widget.pointer != null;
    if (hadPointer != hasPointer) {
      _breathe.duration = hasPointer ? _breatheAlert : _breatheCalm;
      if (hasPointer) {
        _idleTimer?.cancel();
        _drifting = false;
      } else {
        _scheduleNextDrift();
      }
    }
    if (widget.manifest != null && old.manifest == null) {
      _scheduleNextBlink();
    }
  }

  void _scheduleNextDrift() {
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: 8), _doDrift);
  }

  void _doDrift() async {
    if (!mounted || widget.pointer != null) return;
    _drifting = true;
    final dx = (_rng.nextDouble() - 0.5) * 2;
    final dy = (_rng.nextDouble() - 0.5) * 1.2;
    _targetTiltX = dx * 0.035;
    _targetTiltY = dy * 0.035;
    await Future.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;
    if (widget.pointer == null) {
      _targetTiltX = 0;
      _targetTiltY = 0;
    }
    _drifting = false;
    _scheduleNextDrift();
  }

  void _scheduleNextBlink() {
    _blinkScheduler?.cancel();
    final delay = 2800 + _rng.nextInt(2200);
    _blinkScheduler = Timer(Duration(milliseconds: delay), () async {
      if (!mounted) return;
      await _playBlink();
      if (!mounted) return;
      if (_rng.nextDouble() < 0.10) {
        await Future.delayed(const Duration(milliseconds: 90));
        if (!mounted) return;
        await _playBlink();
      }
      if (!mounted) return;
      _scheduleNextBlink();
    });
  }

  Future<void> _playBlink() async {
    // 闭眼 70ms：1 → 0.05 (easeIn)
    const closeMs = 70;
    const openMs = 70;
    final closeStart = DateTime.now();
    while (mounted) {
      final t = DateTime.now().difference(closeStart).inMilliseconds / closeMs;
      if (t >= 1) break;
      final e = t * t;
      _blinkY = 1.0 - 0.95 * e;
      await Future.delayed(const Duration(milliseconds: 16));
    }
    if (!mounted) return;
    _blinkY = 0.05;
    final openStart = DateTime.now();
    while (mounted) {
      final t = DateTime.now().difference(openStart).inMilliseconds / openMs;
      if (t >= 1) break;
      final e = 1 - (1 - t) * (1 - t);
      _blinkY = 0.05 + 0.95 * e;
      await Future.delayed(const Duration(milliseconds: 16));
    }
    if (!mounted) return;
    _blinkY = 1.0;
  }

  void _onTick(Duration _) {
    final p = widget.pointer;
    if (p != null) {
      _targetTiltX = p.dx * _maxTilt;
      _targetTiltY = p.dy * _maxTilt;
      _halo += (1.0 - _halo) * 0.06;
    } else if (!_drifting) {
      _targetTiltX += (0 - _targetTiltX) * 0.04;
      _targetTiltY += (0 - _targetTiltY) * 0.04;
      _halo += (0.0 - _halo) * 0.04;
    } else {
      _halo += (0.3 - _halo) * 0.04;
    }
    _tiltX += (_targetTiltX - _tiltX) * _lerpFactor;
    _tiltY += (_targetTiltY - _tiltY) * _lerpFactor;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    _breathe.dispose();
    _pulse.dispose();
    _idleTimer?.cancel();
    _blinkScheduler?.cancel();
    super.dispose();
  }

  bool _isAssetPath(String p) =>
      !p.contains(':') && !p.startsWith('/');

  Widget _imageFromPath(String path, {BoxFit fit = BoxFit.cover}) {
    if (_isAssetPath(path)) {
      return Image.asset(path, fit: fit, gaplessPlayback: true);
    }
    return Image.file(File(path), fit: fit, gaplessPlayback: true);
  }

  /// 角色合成层：base + 眨眼的 eyes 图层
  Widget _buildCharacter() {
    final m = widget.manifest;
    if (m == null) {
      return _imageFromPath(widget.spritePath);
    }
    // 眼睛中心在画面中的相对位置（-1..1）
    final eyesAlignX = (m.eyesRect.cxPct - 0.5) * 2;
    final eyesAlignY = (m.eyesRect.cyPct - 0.5) * 2;
    final eyesAlign = Alignment(eyesAlignX, eyesAlignY);

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(File(m.basePath),
            fit: BoxFit.cover, gaplessPlayback: true),
        Transform(
          alignment: eyesAlign,
          transform: Matrix4.identity()..scaleByDouble(1.0, _blinkY, 1.0, 1.0),
          child: Image.file(File(m.eyesOverlayPath),
              fit: BoxFit.cover, gaplessPlayback: true),
        ),
        if (kShowPartsDebugBox)
          Positioned.fill(
            child: CustomPaint(
              painter: _RectDebugPainter(
                  rect: m.eyesRect, color: const Color(0xFFFF5577)),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 外层光晕
            AnimatedBuilder(
              animation: Listenable.merge([_pulse, _breathe]),
              builder: (_, __) {
                final breatheV = _breathe.value;
                final pulseV = _pulse.value;
                final pulseGlow =
                    pulseV > 0 ? math.sin(pulseV * math.pi) * 0.25 : 0.0;
                final baseAlpha = 0.16 + breatheV * 0.05;
                final addAlpha = _halo * 0.22 + pulseGlow;
                return Container(
                  width: widget.width + 20,
                  height: widget.height + 20,
                  decoration: BoxDecoration(
                    borderRadius: widget.borderRadius * 1.2,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFE8B96A)
                            .withValues(alpha: baseAlpha + addAlpha),
                        Colors.transparent,
                      ],
                      stops: const [0.3, 1.0],
                    ),
                  ),
                );
              },
            ),
            // 主体：perspective tilt + 呼吸 scale + pulse
            AnimatedBuilder(
              animation: Listenable.merge([_breathe, _pulse]),
              builder: (_, __) {
                final breatheV = _breathe.value;
                final pulseV = _pulse.value;
                final pulseScale =
                    pulseV > 0 ? math.sin(pulseV * math.pi) * 0.04 : 0.0;
                final scale = 1.0 + breatheV * 0.018 + pulseScale;
                final dy = -breatheV * 2;
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0015)
                    ..rotateY(_tiltX)
                    ..rotateX(-_tiltY),
                  child: Transform.scale(
                    scale: scale,
                    child: Transform.translate(
                      offset: Offset(0, dy),
                      child: Container(
                        width: widget.width * 0.82,
                        height: widget.height * 0.86,
                        decoration: BoxDecoration(
                          borderRadius: widget.borderRadius,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE8B96A)
                                  .withValues(alpha: 0.28 + _halo * 0.15),
                              blurRadius: 32 + _halo * 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: widget.borderRadius,
                          child: _buildCharacter(),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RectDebugPainter extends CustomPainter {
  final PartsRect rect;
  final Color color;
  _RectDebugPainter({required this.rect, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(
      rect.xPct * size.width,
      rect.yPct * size.height,
      rect.wPct * size.width,
      rect.hPct * size.height,
    );
    final fill = Paint()..color = color.withValues(alpha: 0.18);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(r, fill);
    canvas.drawRect(r, stroke);
  }

  @override
  bool shouldRepaint(covariant _RectDebugPainter old) =>
      old.rect.xPct != rect.xPct ||
      old.rect.yPct != rect.yPct ||
      old.rect.wPct != rect.wPct ||
      old.rect.hPct != rect.hPct;
}
