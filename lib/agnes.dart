import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Agnes 封装
/// 图像：https://apihub.agnes-ai.com/v1/images/generations
/// 视频：https://apihub.agnes-ai.com/v1/videos

const _agnesImageUrl = 'https://apihub.agnes-ai.com/v1/images/generations';
const _agnesImageModel = 'agnes-image-2.1-flash';
const _agnesVideoUrl = 'https://apihub.agnes-ai.com/v1/videos';
const _agnesVideoQueryUrl = 'https://apihub.agnes-ai.com/agnesapi';
const _agnesVideoModel = 'agnes-video-v2.0';

/// 性别枚举
enum SpiritGender { female, male, neutral }

String _genderWord(SpiritGender g) {
  switch (g) {
    case SpiritGender.female:
      return '女性';
    case SpiritGender.male:
      return '男性';
    case SpiritGender.neutral:
      return '中性';
  }
}

/// 风格枚举（控制画风氛围）
enum SpiritStyle { sunny, cool, warm }

String _styleWords(SpiritStyle s) {
  switch (s) {
    case SpiritStyle.sunny:
      return '明亮阳光，清新自然，温暖光线，柔和阴影';
    case SpiritStyle.cool:
      return '清冷月色，冷色调，柔和高光，淡蓝紫氛围';
    case SpiritStyle.warm:
      return '暖调暮色，琥珀色光晕，金色逆光，温馨氛围';
  }
}

/// 通用画质后缀
const _qualitySuffix = '日漫风格半身立绘，2.5D 体积感，有层次，高细节，干净背景，居中构图，竖版';

/// 从项目根 agnes.txt 读 API key
Future<String> _loadApiKey() async {
  final env = Platform.environment['AGNES_API_KEY'];
  if (env != null && env.isNotEmpty) return env;

  final candidates = <File>[];
  candidates.add(File('agnes.txt'));
  final exeDir = File(Platform.resolvedExecutable).parent;
  for (var d = exeDir; d.path != d.parent.path; d = d.parent) {
    candidates.add(File('${d.path}/agnes.txt'));
  }
  try {
    final doc = await getApplicationDocumentsDirectory();
    candidates.add(File('${doc.path}/agnes.txt'));
  } catch (_) {}

  for (final f in candidates) {
    if (await f.exists()) {
      final lines = await f.readAsLines();
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('API')) {
          final sep = trimmed.contains('：') ? '：' : ':';
          final key = trimmed.split(sep).sublist(1).join(sep).trim();
          if (key.isNotEmpty) return key;
        }
      }
    }
  }
  throw Exception('agnes.txt not found or API key missing');
}

// ============================================================
// 图像生成
// ============================================================

class SpriteImageResult {
  final Uint8List bytes;
  final String? remoteUrl; // 公网 URL（用于后续视频生成）
  SpriteImageResult({required this.bytes, this.remoteUrl});
}

String buildTextPrompt({
  required SpiritGender gender,
  required List<String> temperaments,
  required SpiritStyle style,
  String extra = '',
}) {
  final parts = <String>[];
  final g = _genderWord(gender);
  if (temperaments.isNotEmpty) {
    parts.add('一位${temperaments.join('、')}气质的$g');
  } else {
    parts.add('一位$g');
  }
  if (extra.trim().isNotEmpty) {
    parts.add(extra.trim());
  }
  parts.add(_styleWords(style));
  parts.add(_qualitySuffix);
  return parts.join('，');
}

/// 解析图像生成响应；优先取 URL（用于视频生成），同时下载字节
Future<SpriteImageResult> _parseImageResponse(http.Response resp) async {
  if (resp.statusCode != 200) {
    throw Exception('Agnes 图像 HTTP ${resp.statusCode}: ${resp.body}');
  }
  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  final items = data['data'] as List;
  if (items.isEmpty) throw Exception('Agnes 空 data');
  final item = items[0] as Map<String, dynamic>;
  final url = item['url'] as String?;
  if (url != null && url.isNotEmpty) {
    final r = await http.get(Uri.parse(url));
    if (r.statusCode != 200) {
      throw Exception('下载 URL 失败 HTTP ${r.statusCode}');
    }
    return SpriteImageResult(bytes: r.bodyBytes, remoteUrl: url);
  }
  final b64 = item['b64_json'] as String?;
  if (b64 != null && b64.isNotEmpty) {
    return SpriteImageResult(bytes: base64Decode(b64), remoteUrl: null);
  }
  throw Exception('Agnes 无 url 也无 b64_json');
}

/// 文生图：返回字节 + 公网 URL
Future<SpriteImageResult> generateSpriteFromText({
  required SpiritGender gender,
  required List<String> temperaments,
  required SpiritStyle style,
  String extra = '',
}) async {
  final apiKey = await _loadApiKey();
  final prompt = buildTextPrompt(
    gender: gender,
    temperaments: temperaments,
    style: style,
    extra: extra,
  );
  final body = jsonEncode({
    'model': _agnesImageModel,
    'prompt': prompt,
    'size': '1024x1024',
    // 不传 return_base64，由服务端返回 URL
  });
  final resp = await http.post(
    Uri.parse(_agnesImageUrl),
    headers: {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json; charset=utf-8',
    },
    body: body,
  ).timeout(const Duration(seconds: 240));
  return _parseImageResponse(resp);
}

/// 图生图：返回字节 + 公网 URL
Future<SpriteImageResult> generateSpriteFromPhoto({
  required File photo,
  SpiritStyle style = SpiritStyle.sunny,
  String extra = '',
}) async {
  final apiKey = await _loadApiKey();
  final bytes = await photo.readAsBytes();
  final b64 = base64Encode(bytes);
  final dataUri = 'data:image/png;base64,$b64';

  final styleWords = _styleWords(style);
  final extraPart = extra.trim().isEmpty ? '' : '${extra.trim()}，';
  final prompt = '将这张照片转换为日漫风格半身立绘，'
      '高度还原原图人物特征（性别、年龄段、五官比例、发型、发色、肤色、神态、穿着风格），'
      '不要改变性别或年龄段，不要过度美型化，保持人物辨识度，'
      '$extraPart'
      '$styleWords，'
      '2.5D 体积感，有层次，高细节，干净背景，居中构图，竖版';

  final body = jsonEncode({
    'model': _agnesImageModel,
    'prompt': prompt,
    'size': '1024x1024',
    'extra_body': {
      'image': [dataUri],
      // 不指定 response_format，让服务端返回 URL
    },
  });
  final resp = await http.post(
    Uri.parse(_agnesImageUrl),
    headers: {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json; charset=utf-8',
    },
    body: body,
  ).timeout(const Duration(seconds: 360));
  return _parseImageResponse(resp);
}

/// 把生成的立绘字节存到应用文档目录
Future<String> saveCustomSprite(Uint8List bytes, String name) async {
  final doc = await getApplicationDocumentsDirectory();
  final dir = Directory('${doc.path}/Lumora/sprites');
  if (!await dir.exists()) await dir.create(recursive: true);
  final path = '${dir.path}/$name.png';
  await File(path).writeAsBytes(bytes);
  return path;
}

// ============================================================
// 精灵索引
// ============================================================

class SpriteRecord {
  final String path;          // 本地 PNG 路径
  final String name;
  final int createdAt;
  final String? sourceImageUrl; // 远端公网 URL（用于视频生成）

  SpriteRecord({
    required this.path,
    required this.name,
    required this.createdAt,
    this.sourceImageUrl,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'createdAt': createdAt,
        if (sourceImageUrl != null) 'sourceImageUrl': sourceImageUrl,
      };

  factory SpriteRecord.fromJson(Map<String, dynamic> j) => SpriteRecord(
        path: j['path'] as String,
        name: j['name'] as String,
        createdAt: j['createdAt'] as int,
        sourceImageUrl: j['sourceImageUrl'] as String?,
      );
}

Future<File> _indexFile() async {
  final doc = await getApplicationDocumentsDirectory();
  final dir = Directory('${doc.path}/Lumora');
  if (!await dir.exists()) await dir.create(recursive: true);
  return File('${dir.path}/sprites_index.json');
}

Future<List<SpriteRecord>> loadSpriteIndex() async {
  final f = await _indexFile();
  if (!await f.exists()) return [];
  try {
    final raw = await f.readAsString();
    final list = jsonDecode(raw) as List;
    final records = list
        .map((e) => SpriteRecord.fromJson(e as Map<String, dynamic>))
        .toList();
    final valid = <SpriteRecord>[];
    for (final r in records) {
      if (await File(r.path).exists()) valid.add(r);
    }
    return valid;
  } catch (_) {
    return [];
  }
}

Future<void> _saveSpriteIndex(List<SpriteRecord> records) async {
  final f = await _indexFile();
  final list = records.map((r) => r.toJson()).toList();
  await f.writeAsString(jsonEncode(list));
}

Future<void> addSpriteToIndex(SpriteRecord record) async {
  final list = await loadSpriteIndex();
  list.removeWhere((r) => r.path == record.path);
  list.add(record);
  await _saveSpriteIndex(list);
}

Future<void> removeSpriteFromIndex(String path) async {
  final list = await loadSpriteIndex();
  list.removeWhere((r) => r.path == path);
  await _saveSpriteIndex(list);
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
  // 同时清理对应的视频缓存（idle + reaction）
  try {
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    final fileName = slash >= 0 ? path.substring(slash + 1) : path;
    final dot = fileName.lastIndexOf('.');
    final id = dot > 0 ? fileName.substring(0, dot) : fileName;
    for (final tag in const ['idle', 'reaction']) {
      final vf = await _videoFile(id, tag: tag);
      if (await vf.exists()) await vf.delete();
    }
  } catch (_) {}
}

// ============================================================
// 视频生成
// ============================================================

class VideoTaskInfo {
  final String videoId;
  final String? taskId;
  VideoTaskInfo({required this.videoId, this.taskId});
}

/// 创建图生视频任务，返回 videoId
Future<VideoTaskInfo> createImageToVideoTask({
  required String imageUrl,
  required String prompt,
  int numFrames = 121,
  int frameRate = 24,
}) async {
  final apiKey = await _loadApiKey();
  final body = jsonEncode({
    'model': _agnesVideoModel,
    'prompt': prompt,
    'image': imageUrl,
    'num_frames': numFrames,
    'frame_rate': frameRate,
  });
  final resp = await http.post(
    Uri.parse(_agnesVideoUrl),
    headers: {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json; charset=utf-8',
    },
    body: body,
  ).timeout(const Duration(seconds: 180));
  if (resp.statusCode != 200) {
    throw Exception('创建视频任务失败 HTTP ${resp.statusCode}: ${resp.body}');
  }
  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  final videoId = data['video_id'] as String?;
  final taskId = data['task_id'] as String?;
  if (videoId == null || videoId.isEmpty) {
    throw Exception('未返回 video_id: ${resp.body}');
  }
  return VideoTaskInfo(videoId: videoId, taskId: taskId);
}

class VideoTaskStatus {
  final String status; // queued / in_progress / completed / failed
  final int progress;
  final String? videoUrl;
  final String? error;
  VideoTaskStatus({
    required this.status,
    required this.progress,
    this.videoUrl,
    this.error,
  });

  bool get isDone => status == 'completed';
  bool get isFailed => status == 'failed';
}

/// 查询视频任务状态
Future<VideoTaskStatus> queryVideoTask(String videoId) async {
  final apiKey = await _loadApiKey();
  final uri = Uri.parse('$_agnesVideoQueryUrl?video_id=$videoId&model_name=$_agnesVideoModel');
  final resp = await http.get(
    uri,
    headers: {'Authorization': 'Bearer $apiKey'},
  ).timeout(const Duration(seconds: 30));
  if (resp.statusCode != 200) {
    throw Exception('查询视频失败 HTTP ${resp.statusCode}: ${resp.body}');
  }
  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  final status = (data['status'] as String?) ?? 'unknown';
  final progress = (data['progress'] as int?) ?? 0;
  // 完成时视频 URL 在 remixed_from_video_id 字段
  final videoUrl = data['remixed_from_video_id'] as String?;
  final error = data['error']?.toString();
  return VideoTaskStatus(
    status: status,
    progress: progress,
    videoUrl: (videoUrl != null && videoUrl.startsWith('http')) ? videoUrl : null,
    error: error,
  );
}

/// 轮询直到完成或失败；onProgress 可上报百分比
Future<String> pollVideoUntilDone(
  String videoId, {
  Duration interval = const Duration(seconds: 5),
  Duration timeout = const Duration(minutes: 10),
  void Function(int progress)? onProgress,
}) async {
  final start = DateTime.now();
  while (true) {
    if (DateTime.now().difference(start) > timeout) {
      throw Exception('视频生成超时');
    }
    try {
      final s = await queryVideoTask(videoId);
      onProgress?.call(s.progress);
      if (s.isDone) {
        if (s.videoUrl == null) throw Exception('完成但无视频 URL');
        return s.videoUrl!;
      }
      if (s.isFailed) {
        throw Exception('视频生成失败: ${s.error ?? "未知错误"}');
      }
    } catch (e) {
      // 单次查询失败不直接终止；等下一轮
    }
    await Future.delayed(interval);
  }
}

Future<File> _videoFile(String spiritId, {String tag = 'idle'}) async {
  final doc = await getApplicationDocumentsDirectory();
  final dir = Directory('${doc.path}/Lumora/videos');
  if (!await dir.exists()) await dir.create(recursive: true);
  return File('${dir.path}/${spiritId}_$tag.mp4');
}

/// 视频缓存路径（如果存在）
Future<String?> cachedVideoPath(String spiritId, {String tag = 'idle'}) async {
  final f = await _videoFile(spiritId, tag: tag);
  if (await f.exists() && (await f.length()) > 10000) {
    return f.path;
  }
  return null;
}

/// 下载 MP4 到本地
Future<String> downloadVideo(String url, String spiritId,
    {String tag = 'idle'}) async {
  final f = await _videoFile(spiritId, tag: tag);
  final resp =
      await http.get(Uri.parse(url)).timeout(const Duration(seconds: 180));
  if (resp.statusCode != 200) {
    throw Exception('下载视频失败 HTTP ${resp.statusCode}');
  }
  await f.writeAsBytes(resp.bodyBytes);
  return f.path;
}

/// 默认待机循环 prompt
const defaultIdleVideoPrompt =
    'The character stays in place with subtle breathing motion, '
    'occasional natural eye blinks, very slight head tilt, hair gently '
    'swaying in soft breeze, calm and warm cinematic lighting, '
    'consistent character identity, no large movement, loopable ambient scene';

/// 点击反应 prompt：被注视/被点到的轻微反应
const defaultReactionVideoPrompt =
    'The character notices the viewer, turns head slightly toward camera, '
    'eyes meet the camera, a gentle warm smile appears, soft natural breathing, '
    'subtle hair sway, consistent character identity, calm and warm cinematic '
    'lighting, single continuous motion, no large gesture';
