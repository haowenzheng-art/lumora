import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// 调试可视化开关：true = 在 SpriteView 上画出眼睛/嘴的 rect 边框，方便人眼检查位置
const bool kShowPartsDebugBox = false;

/// 默认百分比（半身居中竖版日漫立绘，1024×1024）
const PartsRect kDefaultEyesRect = PartsRect(
  xPct: 0.28, yPct: 0.18, wPct: 0.44, hPct: 0.08,
);
const PartsRect kDefaultMouthRect = PartsRect(
  xPct: 0.42, yPct: 0.31, wPct: 0.16, hPct: 0.05,
);

/// 像素百分比矩形
class PartsRect {
  final double xPct;
  final double yPct;
  final double wPct;
  final double hPct;

  const PartsRect({
    required this.xPct,
    required this.yPct,
    required this.wPct,
    required this.hPct,
  });

  Map<String, dynamic> toJson() =>
      {'x': xPct, 'y': yPct, 'w': wPct, 'h': hPct};

  factory PartsRect.fromJson(Map<String, dynamic> j) => PartsRect(
        xPct: (j['x'] as num).toDouble(),
        yPct: (j['y'] as num).toDouble(),
        wPct: (j['w'] as num).toDouble(),
        hPct: (j['h'] as num).toDouble(),
      );

  /// 中心点（百分比）
  double get cxPct => xPct + wPct / 2;
  double get cyPct => yPct + hPct / 2;
}

/// 一个精灵的图层产物索引
class PartsManifest {
  final String basePath;       // 修补后的底图（眼睛区域已用肤色涂掉）
  final String eyesOverlayPath; // 眼睛透明图层（同尺寸 1024×1024）
  final String? mouthOverlayPath;
  final PartsRect eyesRect;
  final PartsRect? mouthRect;
  final int imageWidth;
  final int imageHeight;

  PartsManifest({
    required this.basePath,
    required this.eyesOverlayPath,
    this.mouthOverlayPath,
    required this.eyesRect,
    this.mouthRect,
    required this.imageWidth,
    required this.imageHeight,
  });

  Map<String, dynamic> toJson() => {
        'basePath': basePath,
        'eyesOverlayPath': eyesOverlayPath,
        'mouthOverlayPath': mouthOverlayPath,
        'eyesRect': eyesRect.toJson(),
        'mouthRect': mouthRect?.toJson(),
        'imageWidth': imageWidth,
        'imageHeight': imageHeight,
      };

  factory PartsManifest.fromJson(Map<String, dynamic> j) => PartsManifest(
        basePath: j['basePath'] as String,
        eyesOverlayPath: j['eyesOverlayPath'] as String,
        mouthOverlayPath: j['mouthOverlayPath'] as String?,
        eyesRect: PartsRect.fromJson(j['eyesRect'] as Map<String, dynamic>),
        mouthRect: j['mouthRect'] == null
            ? null
            : PartsRect.fromJson(j['mouthRect'] as Map<String, dynamic>),
        imageWidth: j['imageWidth'] as int,
        imageHeight: j['imageHeight'] as int,
      );
}

/// 每精灵 override（路径 → 自定义 rect）
class PartsOverrides {
  final Map<String, PartsRect> eyesByPath;
  final Map<String, PartsRect> mouthByPath;
  PartsOverrides({
    required this.eyesByPath,
    required this.mouthByPath,
  });

  factory PartsOverrides.empty() =>
      PartsOverrides(eyesByPath: {}, mouthByPath: {});

  static Future<PartsOverrides> load() async {
    try {
      final f = await _overridesFile();
      if (!await f.exists()) return PartsOverrides.empty();
      final raw = await f.readAsString();
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final eyes = <String, PartsRect>{};
      final mouth = <String, PartsRect>{};
      final e = j['eyes'] as Map<String, dynamic>? ?? const {};
      for (final entry in e.entries) {
        eyes[entry.key] =
            PartsRect.fromJson(entry.value as Map<String, dynamic>);
      }
      final m = j['mouth'] as Map<String, dynamic>? ?? const {};
      for (final entry in m.entries) {
        mouth[entry.key] =
            PartsRect.fromJson(entry.value as Map<String, dynamic>);
      }
      return PartsOverrides(eyesByPath: eyes, mouthByPath: mouth);
    } catch (_) {
      return PartsOverrides.empty();
    }
  }
}

Future<File> _overridesFile() async {
  final doc = await getApplicationDocumentsDirectory();
  final dir = Directory('${doc.path}/Lumora');
  if (!await dir.exists()) await dir.create(recursive: true);
  return File('${dir.path}/parts_overrides.json');
}

Future<Directory> _partsDir(String spiritId) async {
  final doc = await getApplicationDocumentsDirectory();
  final dir = Directory('${doc.path}/Lumora/parts/$spiritId');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

/// 主入口：保证给定精灵的图层已生成，返回 manifest。
/// - 已生成且 rect 未变 → 直接读 manifest
/// - 否则在后台 isolate 处理后写盘
Future<PartsManifest?> ensureParts({
  required String spritePath,
  required String spiritId,
  required Uint8List Function() readSourceBytes,
}) async {
  try {
    final partsDir = await _partsDir(spiritId);
    final manifestFile = File('${partsDir.path}/manifest.json');

    final overrides = await PartsOverrides.load();
    final eyesRect = overrides.eyesByPath[spritePath] ?? kDefaultEyesRect;

    // 已有 manifest 且 rect 没变 → 直接复用
    if (await manifestFile.exists()) {
      try {
        final j = jsonDecode(await manifestFile.readAsString())
            as Map<String, dynamic>;
        final old = PartsManifest.fromJson(j);
        final rectSame = (old.eyesRect.xPct - eyesRect.xPct).abs() < 1e-6 &&
            (old.eyesRect.yPct - eyesRect.yPct).abs() < 1e-6 &&
            (old.eyesRect.wPct - eyesRect.wPct).abs() < 1e-6 &&
            (old.eyesRect.hPct - eyesRect.hPct).abs() < 1e-6;
        if (rectSame &&
            await File(old.basePath).exists() &&
            await File(old.eyesOverlayPath).exists()) {
          return old;
        }
      } catch (_) {
        // fallthrough → rebuild
      }
    }

    final sourceBytes = readSourceBytes();
    final args = _PartsArgs(
      sourceBytes: sourceBytes,
      outDir: partsDir.path,
      eyesRect: eyesRect,
    );
    final result = await compute(_processInIsolate, args);
    if (result == null) return null;

    await manifestFile.writeAsString(jsonEncode(result.toJson()));
    return result;
  } catch (e) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('ensureParts failed: $e');
    }
    return null;
  }
}

class _PartsArgs {
  final Uint8List sourceBytes;
  final String outDir;
  final PartsRect eyesRect;
  _PartsArgs({
    required this.sourceBytes,
    required this.outDir,
    required this.eyesRect,
  });
}

/// 后台 isolate 中执行的纯函数
PartsManifest? _processInIsolate(_PartsArgs args) {
  final decoded = img.decodeImage(args.sourceBytes);
  if (decoded == null) return null;
  // 强制 RGBA
  final src = decoded.convert(numChannels: 4);
  final w = src.width;
  final h = src.height;

  final rectX = (args.eyesRect.xPct * w).round();
  final rectY = (args.eyesRect.yPct * h).round();
  final rectW = (args.eyesRect.wPct * w).round();
  final rectH = (args.eyesRect.hPct * h).round();
  if (rectW <= 1 || rectH <= 1) return null;

  // 1) 采样上方一条肤色（脸部，避免头发/背景）
  //    取眼睛 rect 中心列上方 rectH 行的中央像素均值
  final skin = _sampleSkin(src, rectX, rectY, rectW, rectH);

  // 2) base：复制原图，眼睛区域用肤色径向羽化覆盖
  final base = img.Image.from(src);
  _paintSkinPatch(base, rectX, rectY, rectW, rectH, skin);

  // 3) eyes overlay：透明同尺寸画布，复制眼睛区域 + 径向羽化
  final overlay = img.Image(width: w, height: h, numChannels: 4);
  _copyWithRadialFeather(src, overlay, rectX, rectY, rectW, rectH);

  // 4) 写盘
  final basePath = '${args.outDir}/base.png';
  final eyesPath = '${args.outDir}/eyes.png';
  File(basePath).writeAsBytesSync(img.encodePng(base));
  File(eyesPath).writeAsBytesSync(img.encodePng(overlay));

  return PartsManifest(
    basePath: basePath,
    eyesOverlayPath: eyesPath,
    eyesRect: args.eyesRect,
    imageWidth: w,
    imageHeight: h,
  );
}

/// 在眼睛 rect 上方采样 rectH 高的肤色均值
List<int> _sampleSkin(img.Image src, int rx, int ry, int rw, int rh) {
  final w = src.width;
  final h = src.height;
  // 上方采样带：在 [ry - rh, ry - rh*0.2) 之间
  final sampleY1 = math.max(0, (ry - rh).toInt());
  final sampleY2 = math.max(sampleY1 + 1, (ry - rh * 0.2).round());
  final sampleX1 = math.max(0, rx + rw ~/ 4);
  final sampleX2 = math.min(w - 1, rx + (rw * 3) ~/ 4);

  int rr = 0, gg = 0, bb = 0, n = 0;
  for (int y = sampleY1; y < sampleY2 && y < h; y++) {
    for (int x = sampleX1; x < sampleX2 && x < w; x++) {
      final p = src.getPixel(x, y);
      if (p.a < 200) continue; // 跳过透明像素
      rr += p.r.toInt();
      gg += p.g.toInt();
      bb += p.b.toInt();
      n++;
    }
  }
  if (n == 0) return [220, 190, 170, 255]; // fallback 米色
  return [rr ~/ n, gg ~/ n, bb ~/ n, 255];
}

/// 用肤色在 base 上覆盖眼睛 rect，中心 alpha=1，向边缘 smoothstep→0
void _paintSkinPatch(
    img.Image base, int rx, int ry, int rw, int rh, List<int> skin) {
  final cx = rx + rw / 2;
  final cy = ry + rh / 2;
  // 椭圆归一化：dx/(rw/2), dy/(rh/2)
  final hx = rw / 2;
  final hy = rh / 2;
  for (int y = ry; y < ry + rh; y++) {
    if (y < 0 || y >= base.height) continue;
    for (int x = rx; x < rx + rw; x++) {
      if (x < 0 || x >= base.width) continue;
      final ndx = (x + 0.5 - cx) / hx;
      final ndy = (y + 0.5 - cy) / hy;
      final d = math.sqrt(ndx * ndx + ndy * ndy);
      if (d >= 1) continue;
      // smoothstep: 中心(d=0) → 1, 边缘(d=1) → 0
      // 直接用 1 - smoothstep(0.4, 1.0, d) 让中心区域全覆盖
      final t = ((d - 0.4) / 0.6).clamp(0.0, 1.0);
      final mask = 1.0 - (t * t * (3 - 2 * t));
      if (mask <= 0.001) continue;
      final p = base.getPixel(x, y);
      // alpha-混合 skin -> p
      final nr = (skin[0] * mask + p.r * (1 - mask)).round().clamp(0, 255);
      final ng = (skin[1] * mask + p.g * (1 - mask)).round().clamp(0, 255);
      final nb = (skin[2] * mask + p.b * (1 - mask)).round().clamp(0, 255);
      base.setPixelRgba(x, y, nr, ng, nb, p.a.toInt());
    }
  }
}

/// 复制 src 在 rect 内的像素到 dst，alpha 用径向 smoothstep 羽化
void _copyWithRadialFeather(
    img.Image src, img.Image dst, int rx, int ry, int rw, int rh) {
  final cx = rx + rw / 2;
  final cy = ry + rh / 2;
  final hx = rw / 2;
  final hy = rh / 2;
  // 椭圆距离 < 1 内拷贝；t = smoothstep(0.55, 1.0, d) → 边缘 alpha=0
  for (int y = ry; y < ry + rh; y++) {
    if (y < 0 || y >= src.height) continue;
    for (int x = rx; x < rx + rw; x++) {
      if (x < 0 || x >= src.width) continue;
      final ndx = (x + 0.5 - cx) / hx;
      final ndy = (y + 0.5 - cy) / hy;
      final d = math.sqrt(ndx * ndx + ndy * ndy);
      if (d >= 1) continue;
      final t = ((d - 0.55) / 0.45).clamp(0.0, 1.0);
      final mask = 1.0 - (t * t * (3 - 2 * t));
      if (mask <= 0.001) continue;
      final p = src.getPixel(x, y);
      final a = (p.a * mask).round().clamp(0, 255);
      dst.setPixelRgba(
          x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), a);
    }
  }
}
