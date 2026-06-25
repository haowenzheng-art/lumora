import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 无缝循环 + 反应淡入的视频视图。
///
/// 解决"5s 视频每次循环到头看得见接缝"的问题：
/// 用两个 Player 错位播放 idle，在尾部 [_crossFade] 内交叉淡入。
/// 同时支持一个一次性 reaction 视频，触发时淡入播完，再淡回 idle。
class LoopVideoView extends StatefulWidget {
  final String idlePath;
  final String? reactionPath;
  final int reactionToken; // 每次变化触发一次 reaction
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const LoopVideoView({
    super.key,
    required this.idlePath,
    this.reactionPath,
    this.reactionToken = 0,
    required this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
  });

  @override
  State<LoopVideoView> createState() => _LoopVideoViewState();
}

class _LoopVideoViewState extends State<LoopVideoView> {
  static const Duration _crossFade = Duration(milliseconds: 450);

  late final Player _a;
  late final Player _b;
  Player? _r;
  late final VideoController _ca;
  late final VideoController _cb;
  VideoController? _cr;

  bool _ready = false;
  // 0 = a, 1 = b
  int _active = 0;
  bool _reactionShowing = false;

  StreamSubscription<Duration>? _subA;
  StreamSubscription<Duration>? _subB;
  StreamSubscription<bool>? _subRDone;
  Duration _idleDuration = Duration.zero;

  bool _switching = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _a = Player();
    _b = Player();
    _ca = VideoController(_a);
    _cb = VideoController(_b);
    _boot();
  }

  Future<void> _boot() async {
    await _a.open(Media(widget.idlePath), play: false);
    await _b.open(Media(widget.idlePath), play: false);
    await _a.setVolume(0);
    await _b.setVolume(0);
    // 拿 duration（同一个 mp4，监听 a 即可）
    final completer = Completer<Duration>();
    late StreamSubscription<Duration> sub;
    sub = _a.stream.duration.listen((d) {
      if (d > Duration.zero && !completer.isCompleted) {
        completer.complete(d);
        sub.cancel();
      }
    });
    _idleDuration =
        await completer.future.timeout(const Duration(seconds: 5), onTimeout: () {
      return const Duration(seconds: 5);
    });

    await _a.play();
    _subA = _a.stream.position.listen((p) => _onPositionTick(0, p));
    _subB = _b.stream.position.listen((p) => _onPositionTick(1, p));

    if (mounted && !_disposed) setState(() => _ready = true);

    if (widget.reactionPath != null) await _prepareReaction();
  }

  Future<void> _prepareReaction() async {
    final r = Player();
    final cr = VideoController(r);
    await r.open(Media(widget.reactionPath!), play: false);
    await r.setVolume(0);
    await r.setPlaylistMode(PlaylistMode.none);
    _subRDone = r.stream.completed.listen((done) {
      if (done && _reactionShowing) _endReaction();
    });
    if (_disposed) {
      await r.dispose();
      return;
    }
    _r = r;
    _cr = cr;
  }

  void _onPositionTick(int who, Duration p) {
    if (_switching || !_ready) return;
    if (_idleDuration <= Duration.zero) return;
    if (who != _active) return;
    final remaining = _idleDuration - p;
    if (remaining <= _crossFade && remaining > Duration.zero) {
      _startCrossFade();
    }
  }

  Future<void> _startCrossFade() async {
    _switching = true;
    final next = _active == 0 ? 1 : 0;
    final nextPlayer = next == 0 ? _a : _b;
    await nextPlayer.seek(Duration.zero);
    await nextPlayer.play();
    if (mounted) setState(() => _active = next);
    await Future.delayed(_crossFade + const Duration(milliseconds: 30));
    // 旧的那个停回 0，等下次轮到再播
    final old = next == 0 ? _b : _a;
    try {
      await old.pause();
      await old.seek(Duration.zero);
    } catch (_) {}
    _switching = false;
  }

  @override
  void didUpdateWidget(covariant LoopVideoView old) {
    super.didUpdateWidget(old);
    if (widget.reactionToken != old.reactionToken &&
        widget.reactionToken > 0 &&
        _r != null) {
      _playReaction();
    }
    if (widget.reactionPath != null && old.reactionPath == null) {
      _prepareReaction();
    }
  }

  Future<void> _playReaction() async {
    if (_r == null || _reactionShowing) return;
    _reactionShowing = true;
    try {
      await _r!.seek(Duration.zero);
      await _r!.play();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _endReaction() {
    _reactionShowing = false;
    if (mounted) setState(() {});
    // reaction 播完后，当前 idle player 继续平滑跑
  }

  @override
  void dispose() {
    _disposed = true;
    _subA?.cancel();
    _subB?.cancel();
    _subRDone?.cancel();
    _a.dispose();
    _b.dispose();
    _r?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 双 idle player 始终都画，opacity 切换
            AnimatedOpacity(
              opacity: _active == 0 ? 1.0 : 0.0,
              duration: _crossFade,
              curve: Curves.linear,
              child: Video(
                controller: _ca,
                controls: NoVideoControls,
                fill: Colors.transparent,
              ),
            ),
            AnimatedOpacity(
              opacity: _active == 1 ? 1.0 : 0.0,
              duration: _crossFade,
              curve: Curves.linear,
              child: Video(
                controller: _cb,
                controls: NoVideoControls,
                fill: Colors.transparent,
              ),
            ),
            // reaction 层（淡入淡出叠在 idle 之上）
            if (_cr != null)
              AnimatedOpacity(
                opacity: _reactionShowing ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut,
                child: Video(
                  controller: _cr!,
                  controls: NoVideoControls,
                  fill: Colors.transparent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
